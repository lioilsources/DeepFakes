// Package search finds candidate evidence pages for a claim. Providers
// return URLs only; the pipeline downloads and reads pages itself, so search
// results (SERPs) are never stored (Brave ToS, PRAVDOMER_SOURCES.md).
package search

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

// ErrBudget means the provider's daily query budget is used up.
var ErrBudget = errors.New("search budget exhausted")

// Query is one search request.
type Query struct {
	Text  string
	Lang  string // ISO 639-1, may be empty
	Limit int
}

// FactCheck is ClaimReview metadata from a fact-check database.
type FactCheck struct {
	Publisher string `json:"publisher"`
	Rating    string `json:"rating"`
	ClaimText string `json:"claim_text,omitempty"`
}

// Hit is one candidate page.
type Hit struct {
	URL       string
	Title     string
	Provider  string
	Published *time.Time
	FactCheck *FactCheck
}

// Provider is a search backend.
type Provider interface {
	Name() string
	Search(ctx context.Context, q Query) ([]Hit, error)
}

// Budget wraps a provider with a per-day query cap (UTC days).
type Budget struct {
	Provider
	PerDay int
	Now    func() time.Time

	mu   sync.Mutex
	day  string
	used int
}

// Search counts the query against the budget before delegating.
func (b *Budget) Search(ctx context.Context, q Query) ([]Hit, error) {
	if b.PerDay > 0 {
		b.mu.Lock()
		d := b.Now().UTC().Format(time.DateOnly)
		if d != b.day {
			b.day, b.used = d, 0
		}
		if b.used >= b.PerDay {
			b.mu.Unlock()
			return nil, fmt.Errorf("%s: %w", b.Name(), ErrBudget)
		}
		b.used++
		b.mu.Unlock()
	}
	return b.Provider.Search(ctx, q)
}

func getJSON(ctx context.Context, hc *http.Client, u string, hdr map[string]string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return fmt.Errorf("request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	if hc == nil {
		hc = &http.Client{Timeout: 15 * time.Second}
	}
	resp, err := hc.Do(req)
	if err != nil {
		return fmt.Errorf("get: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return fmt.Errorf("read: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		msg := strings.TrimSpace(string(body))
		if len(msg) > 200 {
			msg = msg[:200]
		}
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, msg)
	}
	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("decode: %w", err)
	}
	return nil
}

func parseTime(s string) *time.Time {
	for _, layout := range []string{time.RFC3339, "2006-01-02T15:04:05", time.DateOnly} {
		if t, err := time.Parse(layout, s); err == nil {
			return &t
		}
	}
	return nil
}
