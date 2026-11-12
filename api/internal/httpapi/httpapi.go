// Package httpapi exposes the service over HTTP + SSE (see docs/API.md).
package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net/http"
	"strconv"
	"sync"
	"time"

	"golang.org/x/time/rate"

	"github.com/lioilsources/DeepFakes/api/internal/service"
	"github.com/lioilsources/DeepFakes/api/internal/store"
)

// Server holds HTTP dependencies.
type Server struct {
	Svc *service.Service
	Log *slog.Logger
	// SubmitRate limits POST /v1/analyses per device.
	SubmitRate  rate.Limit
	SubmitBurst int
	// KeepAlive is the SSE comment interval.
	KeepAlive time.Duration

	limMu    sync.Mutex
	limiters map[string]*rate.Limiter
}

// Handler returns the router.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { io.WriteString(w, "ok") })
	mux.HandleFunc("POST /v1/analyses", s.submit)
	mux.HandleFunc("GET /v1/analyses/{id}", s.get)
	mux.HandleFunc("GET /v1/analyses/{id}/events", s.events)
	return mux
}

type apiError struct {
	Error store.Error `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v) //nolint:errcheck // client gone
}

func writeErr(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, apiError{store.Error{Code: code, Message: msg}})
}

func (s *Server) limiter(device string) *rate.Limiter {
	s.limMu.Lock()
	defer s.limMu.Unlock()
	if s.limiters == nil {
		s.limiters = map[string]*rate.Limiter{}
	}
	if len(s.limiters) > 100_000 { // crude bound against id spraying
		s.limiters = map[string]*rate.Limiter{}
	}
	l, ok := s.limiters[device]
	if !ok {
		l = rate.NewLimiter(s.SubmitRate, s.SubmitBurst)
		s.limiters[device] = l
	}
	return l
}

func (s *Server) submit(w http.ResponseWriter, r *http.Request) {
	device := r.Header.Get("X-Device-Id")
	if device == "" || len(device) > 64 {
		writeErr(w, http.StatusBadRequest, "bad_request", "X-Device-Id header required")
		return
	}
	res := s.limiter(device).Reserve()
	if d := res.Delay(); d > 0 {
		res.Cancel()
		w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(d.Seconds()))))
		writeErr(w, http.StatusTooManyRequests, "rate_limited", "Too many requests, try again later.")
		return
	}
	body := http.MaxBytesReader(w, r.Body, service.MaxTextBytes+16<<10)
	var req service.SubmitRequest
	if err := json.NewDecoder(body).Decode(&req); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			writeErr(w, http.StatusRequestEntityTooLarge, "too_large", "Text is too long.")
			return
		}
		writeErr(w, http.StatusBadRequest, "bad_request", "Invalid JSON body.")
		return
	}
	id, cached, err := s.Svc.Submit(r.Context(), req)
	switch {
	case errors.Is(err, service.ErrBadRequest):
		writeErr(w, http.StatusBadRequest, "bad_request", err.Error())
		return
	case errors.Is(err, service.ErrTooLarge):
		writeErr(w, http.StatusRequestEntityTooLarge, "too_large", "Text is too long.")
		return
	case errors.Is(err, service.ErrBusy):
		w.Header().Set("Retry-After", "30")
		writeErr(w, http.StatusServiceUnavailable, "busy", "Server is busy, try again later.")
		return
	case err != nil:
		s.Log.Error("submit", "err", err)
		writeErr(w, http.StatusInternalServerError, "internal", "Internal error.")
		return
	}
	status, code := "queued", http.StatusAccepted
	if cached {
		code = http.StatusOK
		if r, err := s.Svc.Get(r.Context(), id); err == nil {
			status = r.Status
		}
	}
	writeJSON(w, code, map[string]string{"id": id, "status": status, "events": "/v1/analyses/" + id + "/events"})
}

func (s *Server) get(w http.ResponseWriter, r *http.Request) {
	res, err := s.Svc.Get(r.Context(), r.PathValue("id"))
	if errors.Is(err, store.ErrNotFound) {
		writeErr(w, http.StatusNotFound, "not_found", "Unknown analysis.")
		return
	}
	if err != nil {
		s.Log.Error("get", "err", err)
		writeErr(w, http.StatusInternalServerError, "internal", "Internal error.")
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func writeEvent(w io.Writer, e service.Event) error {
	b, err := json.Marshal(e.Data)
	if err != nil {
		return fmt.Errorf("marshal event: %w", err)
	}
	_, err = fmt.Fprintf(w, "event: %s\ndata: %s\n\n", e.Name, b)
	return err
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	past, ch, cancel, err := s.Svc.Subscribe(r.Context(), r.PathValue("id"))
	if errors.Is(err, store.ErrNotFound) {
		writeErr(w, http.StatusNotFound, "not_found", "Unknown analysis.")
		return
	}
	if err != nil {
		s.Log.Error("subscribe", "err", err)
		writeErr(w, http.StatusInternalServerError, "internal", "Internal error.")
		return
	}
	defer cancel()
	rc := http.NewResponseController(w)
	h := w.Header()
	h.Set("Content-Type", "text/event-stream")
	h.Set("Cache-Control", "no-cache")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	// Long analyses: do not let the server write timeout cut the stream.
	rc.SetWriteDeadline(time.Time{}) //nolint:errcheck // unsupported writers just keep defaults
	for _, e := range past {
		if writeEvent(w, e) != nil {
			return
		}
	}
	rc.Flush() //nolint:errcheck
	if ch == nil {
		return
	}
	ka := s.KeepAlive
	if ka == 0 {
		ka = 15 * time.Second
	}
	tick := time.NewTicker(ka)
	defer tick.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case e, ok := <-ch:
			if !ok {
				return
			}
			if writeEvent(w, e) != nil {
				return
			}
			rc.Flush() //nolint:errcheck
		case <-tick.C:
			if _, err := io.WriteString(w, ": keep-alive\n\n"); err != nil {
				return
			}
			rc.Flush() //nolint:errcheck
		}
	}
}
