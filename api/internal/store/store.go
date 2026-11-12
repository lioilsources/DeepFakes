// Package store persists analyses. Postgres in production, an in-memory
// implementation for tests and local runs without a database.
package store

import (
	"context"
	"errors"
	"time"

	"github.com/lioilsources/DeepFakes/api/internal/temperature"
)

// ErrNotFound is returned for unknown analysis ids.
var ErrNotFound = errors.New("not found")

// Statuses of an analysis.
const (
	StatusQueued  = "queued"
	StatusRunning = "running"
	StatusDone    = "done"
	StatusFailed  = "failed"
)

// Analysis is a submitted job.
type Analysis struct {
	ID        string
	CacheKey  string
	Kind      string // url | text
	SourceURL string
	CreatedAt time.Time
}

// Paragraph is one numbered paragraph of the document text.
type Paragraph struct {
	P    int    `json:"p"`
	Text string `json:"text"`
}

// Document is the stored, extracted document.
type Document struct {
	URL         string      `json:"url,omitempty"`
	Title       string      `json:"title"`
	Author      string      `json:"author,omitempty"`
	PublishedAt *time.Time  `json:"published_at,omitempty"`
	Site        string      `json:"site,omitempty"`
	Language    string      `json:"language"`
	ContentHash string      `json:"-"`
	Truncated   bool        `json:"truncated,omitempty"`
	Paragraphs  []Paragraph `json:"paragraphs"`
	Purged      bool        `json:"purged,omitempty"`
}

// Error is a terminal failure.
type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Result is the full state of an analysis.
type Result struct {
	ID         string                  `json:"id"`
	Status     string                  `json:"status"`
	Document   *Document               `json:"document,omitempty"`
	Paragraphs []temperature.Paragraph `json:"paragraphs"`
	Summary    *temperature.Summary    `json:"summary,omitempty"`
	Error      *Error                  `json:"error,omitempty"`
}

// Store is the persistence API used by the service.
type Store interface {
	CreateAnalysis(ctx context.Context, a Analysis) error
	// FindCached returns a not-failed, not-purged analysis with the key created at or after since.
	FindCached(ctx context.Context, key string, since time.Time) (string, bool, error)
	SetStatus(ctx context.Context, id, status string, e *Error, at time.Time) error
	// FailUnfinished marks queued/running analyses failed (after a restart).
	FailUnfinished(ctx context.Context, at time.Time) (int64, error)
	SaveDocument(ctx context.Context, id string, d Document) error
	SaveParagraph(ctx context.Context, id string, p temperature.Paragraph) error
	SaveSummary(ctx context.Context, id string, s temperature.Summary) error
	Get(ctx context.Context, id string) (Result, error)
	// Purge drops texts and quotes of analyses created before cutoff.
	Purge(ctx context.Context, cutoff, at time.Time) (int, error)
}

// stripQuotes keeps only technique names and confidences.
func stripQuotes(ts []temperature.Technique) []temperature.Technique {
	out := make([]temperature.Technique, len(ts))
	for i, t := range ts {
		out[i] = temperature.Technique{Technique: t.Technique, Confidence: t.Confidence}
	}
	return out
}
