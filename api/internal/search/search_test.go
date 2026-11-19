package search

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func serve(t *testing.T, check func(r *http.Request), body string) *httptest.Server {
	t.Helper()
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		check(r)
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(body)) //nolint:errcheck
	}))
	t.Cleanup(s.Close)
	return s
}

func TestBrave(t *testing.T) {
	s := serve(t, func(r *http.Request) {
		if r.Header.Get("X-Subscription-Token") != "k" || r.URL.Query().Get("search_lang") != "cs" || r.URL.Path != "/web/search" {
			t.Errorf("bad request %s %v", r.URL, r.Header)
		}
	}, `{"web":{"results":[{"url":"https://a.cz/x","title":"A","page_age":"2026-01-02T03:04:05"}]}}`)
	hits, err := (&Brave{APIKey: "k", BaseURL: s.URL}).Search(context.Background(), Query{Text: "q", Lang: "cs", Limit: 3})
	if err != nil || len(hits) != 1 || hits[0].URL != "https://a.cz/x" || hits[0].Published == nil {
		t.Fatalf("hits=%+v err=%v", hits, err)
	}
}

func TestWikipedia(t *testing.T) {
	s := serve(t, func(r *http.Request) {
		if r.Header.Get("User-Agent") != "bot" || r.URL.Path != "/cs/w/rest.php/v1/search/page" {
			t.Errorf("bad request %s", r.URL)
		}
	}, `{"pages":[{"key":"Praha_(město)","title":"Praha"}]}`)
	hits, err := (&Wikipedia{UserAgent: "bot", BaseURL: s.URL + "/%s"}).Search(context.Background(), Query{Text: "Praha", Lang: "cs", Limit: 2})
	if err != nil || len(hits) != 1 || hits[0].URL != s.URL+"/cs/wiki/Praha_%28m%C4%9Bsto%29" {
		t.Fatalf("hits=%+v err=%v", hits, err)
	}
}

func TestFactCheck(t *testing.T) {
	s := serve(t, func(r *http.Request) {
		if r.URL.Query().Get("key") != "k" || r.URL.Query().Get("languageCode") != "sk" {
			t.Errorf("bad request %s", r.URL)
		}
	}, `{"claims":[{"text":"T","claimReview":[{"publisher":{"name":"Demagog.sk"},"url":"https://demagog.sk/v/1","title":"V","reviewDate":"2026-03-01T00:00:00Z","textualRating":"Nepravda"},{"url":""}]}]}`)
	hits, err := (&FactCheckAPI{APIKey: "k", BaseURL: s.URL}).Search(context.Background(), Query{Text: "x", Lang: "sk"})
	if err != nil || len(hits) != 1 || hits[0].FactCheck.Rating != "Nepravda" || hits[0].FactCheck.Publisher != "Demagog.sk" {
		t.Fatalf("hits=%+v err=%v", hits, err)
	}
}

type fake struct{ n int }

func (f *fake) Name() string { return "fake" }
func (f *fake) Search(context.Context, Query) ([]Hit, error) {
	f.n++
	return nil, nil
}

func TestBudget(t *testing.T) {
	now := time.Date(2026, 11, 20, 23, 0, 0, 0, time.UTC)
	f := &fake{}
	b := &Budget{Provider: f, PerDay: 2, Now: func() time.Time { return now }}
	ctx := context.Background()
	for i := 0; i < 2; i++ {
		if _, err := b.Search(ctx, Query{}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := b.Search(ctx, Query{}); !errors.Is(err, ErrBudget) {
		t.Fatalf("want budget error, got %v", err)
	}
	now = now.Add(2 * time.Hour)
	if _, err := b.Search(ctx, Query{}); err != nil || f.n != 3 {
		t.Fatalf("new day: err=%v n=%d", err, f.n)
	}
}

func TestHTTPError(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "quota", http.StatusTooManyRequests)
	}))
	defer s.Close()
	if _, err := (&Brave{BaseURL: s.URL}).Search(context.Background(), Query{Text: "q"}); err == nil {
		t.Fatal("want error")
	}
}
