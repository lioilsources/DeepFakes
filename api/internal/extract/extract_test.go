package extract

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
)

func TestFromHTML(t *testing.T) {
	raw, err := os.ReadFile("testdata/article.html")
	if err != nil {
		t.Fatal(err)
	}
	u, _ := url.Parse("https://www.zpravy.example/clanek/most")
	doc, err := FromHTML(Page{URL: u, HTML: raw, ContentType: "text/html; charset=utf-8"})
	if err != nil {
		t.Fatal(err)
	}
	if doc.Title != "Obec dostala nový most" {
		t.Errorf("title %q", doc.Title)
	}
	if doc.Site != "zpravy.example" || doc.Language != "cs" {
		t.Errorf("site %q lang %q", doc.Site, doc.Language)
	}
	if doc.PublishedAt == nil || doc.PublishedAt.Format("2006-01-02T15:04") != "2026-11-10T07:30" {
		t.Errorf("published %v", doc.PublishedAt)
	}
	if len(doc.Paragraphs) != 5 {
		t.Fatalf("paragraphs %d: %q", len(doc.Paragraphs), doc.Paragraphs)
	}
	for _, p := range doc.Paragraphs {
		if strings.Contains(p, "ilustrační") || p == "Sdílet" || strings.Contains(p, "Přečtěte") {
			t.Errorf("noise kept: %q", p)
		}
	}
	if !strings.Contains(doc.Paragraphs[1], "„konečně spojí obě části obce“") {
		t.Errorf("typography lost: %q", doc.Paragraphs[1])
	}
}

func TestFromText(t *testing.T) {
	doc, err := FromText("First paragraph of the text, long enough.\n\n\nSecond   paragraph\nwith a line break.", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(doc.Paragraphs) != 2 || doc.Paragraphs[1] != "Second paragraph with a line break." {
		t.Fatalf("%q", doc.Paragraphs)
	}
	if _, err := FromText("  \n ", ""); !errors.Is(err, ErrNoContent) {
		t.Fatalf("want ErrNoContent, got %v", err)
	}
}

func TestLimit(t *testing.T) {
	d := Document{Paragraphs: make([]string, MaxParagraphs+10)}
	for i := range d.Paragraphs {
		d.Paragraphs[i] = "x"
	}
	d.limit()
	if len(d.Paragraphs) != MaxParagraphs || !d.Truncated {
		t.Fatalf("len %d", len(d.Paragraphs))
	}
}

func TestFetchBlocksLoopback(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("<p>hi</p>"))
	}))
	defer srv.Close()
	f := NewFetcher("test")
	if _, err := f.Fetch(context.Background(), srv.URL); err == nil || !errors.Is(err, ErrFetch) {
		t.Fatalf("loopback must be refused, got %v", err)
	}
	f = NewFetcher("test")
	f.AllowPrivate = true
	p, err := f.Fetch(context.Background(), srv.URL)
	if err != nil || string(p.HTML) != "<p>hi</p>" {
		t.Fatalf("allowed fetch: %v", err)
	}
}

func TestFetchRejects(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("User-Agent") != "ua" {
			t.Errorf("ua %q", r.Header.Get("User-Agent"))
		}
		switch r.URL.Path {
		case "/pdf":
			w.Header().Set("Content-Type", "application/pdf")
		case "/404":
			w.WriteHeader(404)
		case "/big":
			w.Write([]byte(strings.Repeat("a", 2000)))
		}
	}))
	defer srv.Close()
	f := NewFetcher("ua")
	f.AllowPrivate = true
	f.MaxBytes = 1000
	for _, p := range []string{"/pdf", "/404", "/big"} {
		if _, err := f.Fetch(context.Background(), srv.URL+p); !errors.Is(err, ErrFetch) {
			t.Errorf("%s: %v", p, err)
		}
	}
	for _, u := range []string{"ftp://x/y", "file:///etc/passwd", "https://user:pw@example.com/"} {
		if _, err := f.Fetch(context.Background(), u); !errors.Is(err, ErrFetch) {
			t.Errorf("%s accepted", u)
		}
	}
}
