package store

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/lioilsources/DeepFakes/api/internal/temperature"
)

// Runs only with PRAVDOMER_TEST_DSN pointing at a disposable database.
func TestPostgres(t *testing.T) {
	dsn := os.Getenv("PRAVDOMER_TEST_DSN")
	if dsn == "" {
		t.Skip("PRAVDOMER_TEST_DSN not set")
	}
	if err := Migrate(dsn); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	s, err := OpenPostgres(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	s.pool.Exec(ctx, "TRUNCATE analyses CASCADE")

	t0 := time.Date(2026, 11, 12, 10, 0, 0, 0, time.UTC)
	if err := s.CreateAnalysis(ctx, Analysis{ID: "A1", CacheKey: "k", Kind: "url", SourceURL: "https://x.example", CreatedAt: t0}); err != nil {
		t.Fatal(err)
	}
	if id, ok, _ := s.FindCached(ctx, "k", t0.Add(-time.Hour)); !ok || id != "A1" {
		t.Fatalf("cached %v %v", id, ok)
	}
	pub := t0.Add(-24 * time.Hour)
	if err := s.SaveDocument(ctx, "A1", Document{Title: "T", Language: "cs", ContentHash: "h", PublishedAt: &pub,
		Paragraphs: []Paragraph{{1, "Text odstavce"}}}); err != nil {
		t.Fatal(err)
	}
	p := temperature.Paragraph{P: 1, Score: 55, Emotions: temperature.Emotions{Anger: 0.5},
		Techniques: []temperature.Technique{{Technique: "doubt", Quote: "Text", Start: 0, End: 4, Confidence: 0.7}}}
	if err := s.SaveParagraph(ctx, "A1", p); err != nil {
		t.Fatal(err)
	}
	if err := s.SaveSummary(ctx, "A1", temperature.Summary{Score: 55, Method: "llm-v1"}); err != nil {
		t.Fatal(err)
	}
	if err := s.SetStatus(ctx, "A1", StatusDone, nil, t0); err != nil {
		t.Fatal(err)
	}
	r, err := s.Get(ctx, "A1")
	if err != nil {
		t.Fatal(err)
	}
	if r.Status != "done" || r.Document.Paragraphs[0].Text != "Text odstavce" || r.Paragraphs[0].Techniques[0].Quote != "Text" ||
		r.Summary.Score != 55 || !r.Document.PublishedAt.Equal(pub) {
		t.Fatalf("%+v", r)
	}
	if n, err := s.Purge(ctx, t0.Add(time.Minute), t0); err != nil || n != 1 {
		t.Fatalf("purge %d %v", n, err)
	}
	r, _ = s.Get(ctx, "A1")
	if !r.Document.Purged || len(r.Document.Paragraphs) != 0 || r.Paragraphs[0].Techniques[0].Quote != "" || r.Paragraphs[0].Techniques[0].Technique != "doubt" {
		t.Fatalf("after purge %+v", r)
	}
	if _, ok, _ := s.FindCached(ctx, "k", t0.Add(-time.Hour)); ok {
		t.Fatal("purged analysis must not be served from cache")
	}
	if _, err := s.Get(ctx, "nope"); err != ErrNotFound {
		t.Fatalf("not found: %v", err)
	}
}
