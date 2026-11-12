package store

import (
	"context"
	"sort"
	"sync"
	"time"

	"github.com/lioilsources/DeepFakes/api/internal/temperature"
)

type memEntry struct {
	a       Analysis
	status  string
	err     *Error
	doc     *Document
	paras   map[int]temperature.Paragraph
	summary *temperature.Summary
}

// Memory is an in-process Store. Data is lost on restart.
type Memory struct {
	mu sync.Mutex
	m  map[string]*memEntry
}

// NewMemory returns an empty in-memory store.
func NewMemory() *Memory { return &Memory{m: map[string]*memEntry{}} }

func (s *Memory) CreateAnalysis(_ context.Context, a Analysis) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.m[a.ID] = &memEntry{a: a, status: StatusQueued, paras: map[int]temperature.Paragraph{}}
	return nil
}

func (s *Memory) FindCached(_ context.Context, key string, since time.Time) (string, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var best *memEntry
	for _, e := range s.m {
		if e.a.CacheKey != key || e.a.CreatedAt.Before(since) || e.status == StatusFailed || (e.doc != nil && e.doc.Purged) {
			continue
		}
		if best == nil || e.a.CreatedAt.After(best.a.CreatedAt) {
			best = e
		}
	}
	if best == nil {
		return "", false, nil
	}
	return best.a.ID, true, nil
}

func (s *Memory) get(id string) (*memEntry, error) {
	e, ok := s.m[id]
	if !ok {
		return nil, ErrNotFound
	}
	return e, nil
}

func (s *Memory) SetStatus(_ context.Context, id, status string, er *Error, _ time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, err := s.get(id)
	if err != nil {
		return err
	}
	e.status, e.err = status, er
	return nil
}

func (s *Memory) FailUnfinished(context.Context, time.Time) (int64, error) { return 0, nil }

func (s *Memory) SaveDocument(_ context.Context, id string, d Document) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, err := s.get(id)
	if err != nil {
		return err
	}
	e.doc = &d
	return nil
}

func (s *Memory) SaveParagraph(_ context.Context, id string, p temperature.Paragraph) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, err := s.get(id)
	if err != nil {
		return err
	}
	e.paras[p.P] = p
	return nil
}

func (s *Memory) SaveSummary(_ context.Context, id string, sum temperature.Summary) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, err := s.get(id)
	if err != nil {
		return err
	}
	e.summary = &sum
	return nil
}

func (s *Memory) Get(_ context.Context, id string) (Result, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, err := s.get(id)
	if err != nil {
		return Result{}, err
	}
	r := Result{ID: id, Status: e.status, Error: e.err, Summary: e.summary, Paragraphs: []temperature.Paragraph{}}
	if e.doc != nil {
		d := *e.doc
		r.Document = &d
	}
	for _, p := range e.paras {
		r.Paragraphs = append(r.Paragraphs, p)
	}
	sort.Slice(r.Paragraphs, func(i, j int) bool { return r.Paragraphs[i].P < r.Paragraphs[j].P })
	return r, nil
}

func (s *Memory) Purge(_ context.Context, cutoff, _ time.Time) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	n := 0
	for _, e := range s.m {
		if !e.a.CreatedAt.Before(cutoff) || e.doc == nil || e.doc.Purged {
			continue
		}
		e.doc.Paragraphs, e.doc.Purged = nil, true
		for k, p := range e.paras {
			p.Techniques = stripQuotes(p.Techniques)
			e.paras[k] = p
		}
		n++
	}
	return n, nil
}
