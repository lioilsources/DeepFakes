// Package service orchestrates an analysis: fetch → extract → temperature,
// persisting results and streaming events to subscribers.
package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/lioilsources/DeepFakes/api/internal/extract"
	"github.com/lioilsources/DeepFakes/api/internal/llm"
	"github.com/lioilsources/DeepFakes/api/internal/quote"
	"github.com/lioilsources/DeepFakes/api/internal/store"
	"github.com/lioilsources/DeepFakes/api/internal/temperature"
)

// Request validation errors.
var (
	ErrBadRequest = errors.New("bad request")
	ErrTooLarge   = errors.New("too large")
	ErrBusy       = errors.New("queue full")
)

// MaxTextBytes limits pasted text.
const MaxTextBytes = 200 << 10

// Fetcher downloads a page.
type Fetcher interface {
	Fetch(ctx context.Context, rawURL string) (extract.Page, error)
}

// Analyzer computes temperature.
type Analyzer interface {
	Run(ctx context.Context, in temperature.Input, onParagraph func(temperature.Paragraph)) (temperature.Summary, error)
}

// SubmitRequest is either a URL or pasted text.
type SubmitRequest struct {
	URL   string `json:"url"`
	Text  string `json:"text"`
	Title string `json:"title"`
}

// Service runs analyses.
type Service struct {
	Store      store.Store
	Fetcher    Fetcher
	Analyzer   Analyzer
	Now        func() time.Time
	NewID      func() string
	CacheTTL   time.Duration
	JobTimeout time.Duration
	Log        *slog.Logger

	queue chan job
	hub   *hub
}

type job struct {
	id  string
	req SubmitRequest
}

// Start launches workers; they stop when ctx is cancelled.
func (s *Service) Start(ctx context.Context, workers, queueSize int) {
	s.queue = make(chan job, queueSize)
	s.hub = newHub()
	if s.JobTimeout == 0 {
		s.JobTimeout = 10 * time.Minute
	}
	if n, err := s.Store.FailUnfinished(ctx, s.Now()); err != nil {
		s.Log.Error("fail unfinished", "err", err)
	} else if n > 0 {
		s.Log.Warn("marked unfinished analyses failed after restart", "n", n)
	}
	for range workers {
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case j := <-s.queue:
					s.process(ctx, j)
				}
			}
		}()
	}
}

// NormalizeURL canonicalises a URL for the cache key: lowercase host, no
// fragment, no tracking parameters, sorted query.
func NormalizeURL(raw string) (string, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return "", fmt.Errorf("%w: invalid URL", ErrBadRequest)
	}
	if err := extract.CheckURL(u); err != nil {
		return "", fmt.Errorf("%w: %v", ErrBadRequest, err)
	}
	u.Scheme = strings.ToLower(u.Scheme)
	u.Host = strings.ToLower(u.Host)
	u.Fragment, u.RawFragment = "", ""
	q := u.Query()
	for k := range q {
		lk := strings.ToLower(k)
		if strings.HasPrefix(lk, "utm_") || lk == "fbclid" || lk == "gclid" || lk == "mc_cid" || lk == "mc_eid" {
			q.Del(k)
		}
	}
	keys := make([]string, 0, len(q))
	for k := range q {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var parts []string
	for _, k := range keys {
		for _, v := range q[k] {
			parts = append(parts, url.QueryEscape(k)+"="+url.QueryEscape(v))
		}
	}
	u.RawQuery = strings.Join(parts, "&")
	return u.String(), nil
}

func hash(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

// Submit validates the request and enqueues it, or returns a cached id.
func (s *Service) Submit(ctx context.Context, r SubmitRequest) (id string, cached bool, err error) {
	r.URL, r.Text = strings.TrimSpace(r.URL), strings.TrimSpace(r.Text)
	var key, kind string
	switch {
	case r.URL != "" && r.Text != "":
		return "", false, fmt.Errorf("%w: send url or text, not both", ErrBadRequest)
	case r.URL != "":
		n, err := NormalizeURL(r.URL)
		if err != nil {
			return "", false, err
		}
		r.URL, key, kind = n, "url:"+hash(n), "url"
	case r.Text != "":
		if len(r.Text) > MaxTextBytes {
			return "", false, ErrTooLarge
		}
		key, kind = "text:"+hash(quote.Normalize(r.Title)+"\n"+quote.Normalize(r.Text)), "text"
	default:
		return "", false, fmt.Errorf("%w: url or text required", ErrBadRequest)
	}
	now := s.Now()
	if id, ok, err := s.Store.FindCached(ctx, key, now.Add(-s.CacheTTL)); err != nil {
		return "", false, err
	} else if ok {
		return id, true, nil
	}
	id = s.NewID()
	if err := s.Store.CreateAnalysis(ctx, store.Analysis{ID: id, CacheKey: key, Kind: kind, SourceURL: r.URL, CreatedAt: now}); err != nil {
		return "", false, err
	}
	s.hub.open(id)
	select {
	case s.queue <- job{id: id, req: r}:
		return id, false, nil
	default:
		s.fail(context.WithoutCancel(ctx), id, "internal", "queue full")
		return "", false, ErrBusy
	}
}

// Event is one SSE event.
type Event struct {
	Name string
	Data any
}

func (s *Service) emit(id string, name string, data any) {
	s.hub.publish(id, Event{Name: name, Data: data})
}

func (s *Service) fail(ctx context.Context, id, code, msg string) {
	e := &store.Error{Code: code, Message: msg}
	if err := s.Store.SetStatus(ctx, id, store.StatusFailed, e, s.Now()); err != nil {
		s.Log.Error("set failed", "id", id, "err", err)
	}
	s.emit(id, "error", e)
	s.hub.close(id)
}

func errorCode(err error) (string, string) {
	switch {
	case errors.Is(err, extract.ErrFetch):
		return "fetch_failed", "The page could not be downloaded."
	case errors.Is(err, extract.ErrNoContent):
		return "extract_failed", "No article text found on the page."
	case errors.Is(err, llm.ErrUnavailable):
		return "llm_unavailable", "The analysis model is not available right now."
	case errors.Is(err, context.DeadlineExceeded):
		return "internal", "The analysis took too long."
	}
	return "internal", "Internal error."
}

func (s *Service) process(parent context.Context, j job) {
	ctx, cancel := context.WithTimeout(parent, s.JobTimeout)
	defer cancel()
	log := s.Log.With("id", j.id)
	if err := s.run(ctx, j); err != nil {
		code, msg := errorCode(err)
		log.Warn("analysis failed", "code", code, "err", err)
		s.fail(context.WithoutCancel(ctx), j.id, code, msg)
	}
}

func (s *Service) run(ctx context.Context, j job) error {
	if err := s.Store.SetStatus(ctx, j.id, store.StatusRunning, nil, s.Now()); err != nil {
		return err
	}
	var (
		doc extract.Document
		err error
	)
	if j.req.URL != "" {
		s.emit(j.id, "status", map[string]string{"status": "fetching"})
		page, ferr := s.Fetcher.Fetch(ctx, j.req.URL)
		if ferr != nil {
			return ferr
		}
		doc, err = extract.FromHTML(page)
	} else {
		doc, err = extract.FromText(j.req.Text, j.req.Title)
	}
	if err != nil {
		return err
	}
	sd := store.Document{URL: doc.URL, Title: doc.Title, Author: doc.Author, PublishedAt: doc.PublishedAt,
		Site: doc.Site, Language: doc.Language, Truncated: doc.Truncated,
		ContentHash: hash(strings.Join(doc.Paragraphs, "\n")), Paragraphs: make([]store.Paragraph, len(doc.Paragraphs))}
	for i, p := range doc.Paragraphs {
		sd.Paragraphs[i] = store.Paragraph{P: i + 1, Text: p}
	}
	if err := s.Store.SaveDocument(ctx, j.id, sd); err != nil {
		return err
	}
	s.emit(j.id, "document", sd)
	s.emit(j.id, "status", map[string]string{"status": "analyzing"})

	var saveErr error
	var once sync.Once
	sum, err := s.Analyzer.Run(ctx, temperature.Input{Title: doc.Title, Paragraphs: doc.Paragraphs}, func(p temperature.Paragraph) {
		if err := s.Store.SaveParagraph(ctx, j.id, p); err != nil {
			once.Do(func() { saveErr = err })
			return
		}
		s.emit(j.id, "paragraph", p)
	})
	if err != nil {
		return err
	}
	if saveErr != nil {
		return saveErr
	}
	if err := s.Store.SaveSummary(ctx, j.id, sum); err != nil {
		return err
	}
	if err := s.Store.SetStatus(ctx, j.id, store.StatusDone, nil, s.Now()); err != nil {
		return err
	}
	s.emit(j.id, "summary", sum)
	s.emit(j.id, "done", struct{}{})
	s.hub.close(j.id)
	return nil
}

// Subscribe returns past events and a channel of future ones. The channel
// is nil when the analysis is already finished (replay is complete).
func (s *Service) Subscribe(ctx context.Context, id string) ([]Event, <-chan Event, func(), error) {
	if past, ch, cancel, ok := s.hub.subscribe(id); ok {
		return past, ch, cancel, nil
	}
	r, err := s.Store.Get(ctx, id)
	if err != nil {
		return nil, nil, func() {}, err
	}
	return replay(r), nil, func() {}, nil
}

// replay rebuilds the event sequence of a stored analysis.
func replay(r store.Result) []Event {
	var ev []Event
	if r.Document != nil {
		ev = append(ev, Event{"document", r.Document})
	}
	for _, p := range r.Paragraphs {
		ev = append(ev, Event{"paragraph", p})
	}
	switch r.Status {
	case store.StatusDone:
		if r.Summary != nil {
			ev = append(ev, Event{"summary", r.Summary})
		}
		ev = append(ev, Event{"done", struct{}{}})
	case store.StatusFailed:
		e := r.Error
		if e == nil {
			e = &store.Error{Code: "internal", Message: "Internal error."}
		}
		ev = append(ev, Event{"error", e})
	default:
		// Running on another instance or lost after restart: report as such.
		ev = append(ev, Event{"error", &store.Error{Code: "internal", Message: "Analysis is not running."}})
	}
	return ev
}

// Get returns the stored result.
func (s *Service) Get(ctx context.Context, id string) (store.Result, error) {
	return s.Store.Get(ctx, id)
}

// PurgeLoop drops texts older than CacheTTL every interval.
func (s *Service) PurgeLoop(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		s.PurgeOnce(ctx)
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// PurgeOnce runs one purge pass.
func (s *Service) PurgeOnce(ctx context.Context) {
	now := s.Now()
	n, err := s.Store.Purge(ctx, now.Add(-s.CacheTTL), now)
	if err != nil {
		s.Log.Error("purge", "err", err)
		return
	}
	if n > 0 {
		s.Log.Info("purged analysed texts", "n", n)
	}
}
