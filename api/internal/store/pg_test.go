package store

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/lioilsources/DeepFakes/api/internal/claims"
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
	saveClaims(t, s, "A1")
	if err := s.SetStatus(ctx, "A1", StatusDone, nil, t0); err != nil {
		t.Fatal(err)
	}
	r, err := s.Get(ctx, "A1")
	if err != nil {
		t.Fatal(err)
	}
	checkClaims(t, r, false)
	if r.Status != "done" || r.Document.Paragraphs[0].Text != "Text odstavce" || r.Paragraphs[0].Techniques[0].Quote != "Text" ||
		r.Summary.Score != 55 || !r.Document.PublishedAt.Equal(pub) {
		t.Fatalf("%+v", r)
	}
	if n, err := s.Purge(ctx, t0.Add(time.Minute), t0); err != nil || n != 1 {
		t.Fatalf("purge %d %v", n, err)
	}
	r, _ = s.Get(ctx, "A1")
	checkClaims(t, r, true)
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

func saveClaims(t *testing.T, s Store, id string) {
	t.Helper()
	ctx := context.Background()
	c2 := claims.Claim{ID: "c2", P: 1, Quote: "odstavce", Start: 5, End: 13, Claim: "B", Kind: claims.KindOpinion, Checkworthy: 0.1}
	c1 := claims.Claim{ID: "c1", P: 1, Quote: "Text", Start: 0, End: 4, Claim: "A", Kind: claims.KindFact, Checkworthy: 0.9}
	for _, c := range []claims.Claim{c2, c1} {
		if err := s.SaveClaim(ctx, id, c); err != nil {
			t.Fatal(err)
		}
	}
	v := claims.Verdict{ClaimID: "c1", Label: claims.LabelSupported, Explanation: "E [1]", Confidence: 0.8,
		Evidence: []claims.Evidence{{URL: "https://czso.cz/x", Site: "czso.cz", SourceType: "primary", Stance: claims.StanceSupports, Quote: "Q"}}}
	if err := s.SaveVerdict(ctx, id, v); err != nil {
		t.Fatal(err)
	}
	if err := s.SaveClaimsSummary(ctx, id, claims.Summary{ClaimsFound: 2, Checked: 1, Method: "claims-v1"}); err != nil {
		t.Fatal(err)
	}
}

func checkClaims(t *testing.T, r Result, purged bool) {
	t.Helper()
	if len(r.Claims) != 2 || r.Claims[0].ID != "c1" || r.Claims[1].Verdict != nil || r.ClaimsSummary == nil || r.ClaimsSummary.ClaimsFound != 2 {
		t.Fatalf("claims %+v", r.Claims)
	}
	v := r.Claims[0].Verdict
	if v == nil || v.Label != claims.LabelSupported || v.Evidence[0].URL != "https://czso.cz/x" {
		t.Fatalf("verdict %+v", v)
	}
	if purged {
		if r.Claims[0].Quote != "" || r.Claims[0].Claim.Claim != "" || v.Explanation != "" || v.Evidence[0].Quote != "" || r.Claims[0].Kind != claims.KindFact {
			t.Fatalf("not purged %+v %+v", r.Claims[0], v)
		}
	} else if r.Claims[0].Quote != "Text" || v.Explanation == "" || v.Evidence[0].Quote != "Q" {
		t.Fatalf("lost data %+v %+v", r.Claims[0], v)
	}
}

func TestMemoryClaims(t *testing.T) {
	ctx := context.Background()
	s := NewMemory()
	t0 := time.Date(2026, 11, 12, 10, 0, 0, 0, time.UTC)
	if err := s.CreateAnalysis(ctx, Analysis{ID: "A1", CacheKey: "k", Kind: "text", CreatedAt: t0}); err != nil {
		t.Fatal(err)
	}
	if err := s.SaveDocument(ctx, "A1", Document{Title: "T", Language: "cs", Paragraphs: []Paragraph{{1, "Text odstavce"}}}); err != nil {
		t.Fatal(err)
	}
	saveClaims(t, s, "A1")
	if err := s.SaveVerdict(ctx, "A1", claims.Verdict{ClaimID: "nope"}); err == nil {
		t.Fatal("verdict for unknown claim must fail")
	}
	r, _ := s.Get(ctx, "A1")
	checkClaims(t, r, false)
	if n, err := s.Purge(ctx, t0.Add(time.Minute), t0); err != nil || n != 1 {
		t.Fatalf("purge %d %v", n, err)
	}
	r, _ = s.Get(ctx, "A1")
	checkClaims(t, r, true)
}
