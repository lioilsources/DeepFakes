// Command pravdomer-api serves the Pravdoměr API.
package main

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
	"time"

	"github.com/oklog/ulid/v2"
	"golang.org/x/time/rate"

	"github.com/lioilsources/DeepFakes/api/config"
	"github.com/lioilsources/DeepFakes/api/internal/claims"
	"github.com/lioilsources/DeepFakes/api/internal/extract"
	"github.com/lioilsources/DeepFakes/api/internal/httpapi"
	"github.com/lioilsources/DeepFakes/api/internal/llm"
	"github.com/lioilsources/DeepFakes/api/internal/search"
	"github.com/lioilsources/DeepFakes/api/internal/service"
	"github.com/lioilsources/DeepFakes/api/internal/store"
	"github.com/lioilsources/DeepFakes/api/internal/temperature"
)

const defaultUA = "DeepFakeBot/0.1 (+https://github.com/lioilsources/DeepFakes)"

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envInt(k string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(k)); err == nil {
		return v
	}
	return def
}

func envDur(k string, def time.Duration) time.Duration {
	if v, err := time.ParseDuration(os.Getenv(k)); err == nil {
		return v
	}
	return def
}

func main() {
	var level slog.Level
	level.UnmarshalText([]byte(env("LOG_LEVEL", "info"))) //nolint:errcheck // invalid → info
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
	if err := run(log); err != nil {
		log.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	weightsJSON := config.TemperatureJSON
	if p := os.Getenv("TEMPERATURE_WEIGHTS"); p != "" {
		b, err := os.ReadFile(p)
		if err != nil {
			return fmt.Errorf("read weights: %w", err)
		}
		weightsJSON = b
	}
	weights, err := temperature.ParseWeights(weightsJSON)
	if err != nil {
		return err
	}

	var st store.Store
	if dsn := os.Getenv("DATABASE_URL"); dsn != "" {
		if err := store.Migrate(dsn); err != nil {
			return err
		}
		pg, err := store.OpenPostgres(ctx, dsn)
		if err != nil {
			return err
		}
		defer pg.Close()
		st = pg
	} else {
		log.Warn("DATABASE_URL not set: using in-memory store (dev only)")
		st = store.NewMemory()
	}

	model := env("LLM_MODEL", "deepfake-llm")
	client := &llm.Client{BaseURL: env("LLM_BASE_URL", "http://localhost:8080/v1"), APIKey: os.Getenv("LLM_API_KEY"),
		Model: model, HTTP: &http.Client{Timeout: envDur("LLM_TIMEOUT", 3*time.Minute)}}

	ua := env("BOT_USER_AGENT", defaultUA)
	checker, err := newChecker(log, client, model, ua)
	if err != nil {
		return err
	}

	var idMu sync.Mutex
	entropy := ulid.Monotonic(rand.Reader, 0)
	svc := &service.Service{
		Store:   st,
		Fetcher: extract.NewFetcher(ua),
		Analyzer: &temperature.Analyzer{LLM: client, Model: model, Weights: weights,
			Concurrency: envInt("LLM_CONCURRENCY", 6), BlockChars: envInt("LLM_BLOCK_CHARS", 1200), Now: time.Now, Log: log},
		Now: time.Now,
		NewID: func() string {
			idMu.Lock()
			defer idMu.Unlock()
			return ulid.MustNew(ulid.Now(), entropy).String()
		},
		CacheTTL:   envDur("CACHE_TTL", 7*24*time.Hour),
		JobTimeout: envDur("JOB_TIMEOUT", 10*time.Minute),
		Log:        log,
	}
	if checker != nil {
		svc.Claims = checker
	}
	svc.Start(ctx, envInt("WORKERS", 4), envInt("QUEUE_SIZE", 200))
	go svc.PurgeLoop(ctx, time.Hour)

	srv := &http.Server{
		Addr: env("LISTEN_ADDR", ":8096"),
		Handler: (&httpapi.Server{Svc: svc, Log: log,
			SubmitRate: rate.Every(envDur("SUBMIT_EVERY", 20*time.Second)), SubmitBurst: envInt("SUBMIT_BURST", 5)}).Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second, // SSE handler lifts it per stream
		IdleTimeout:       2 * time.Minute,
	}
	go func() {
		<-ctx.Done()
		sctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.Shutdown(sctx) //nolint:errcheck
	}()
	log.Info("listening", "addr", srv.Addr, "model", model)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return fmt.Errorf("listen: %w", err)
	}
	return nil
}

// newChecker configures claim checking from env; nil when CLAIMS=off.
func newChecker(log *slog.Logger, client *llm.Client, model, ua string) (*claims.Checker, error) {
	if env("CLAIMS", "on") == "off" {
		log.Warn("claim checking disabled (CLAIMS=off)")
		return nil, nil
	}
	cfgJSON := config.ClaimsJSON
	if p := os.Getenv("CLAIMS_CONFIG"); p != "" {
		b, err := os.ReadFile(p)
		if err != nil {
			return nil, fmt.Errorf("read claims config: %w", err)
		}
		cfgJSON = b
	}
	cfg, err := claims.ParseConfig(cfgJSON)
	if err != nil {
		return nil, err
	}
	hc := &http.Client{Timeout: 15 * time.Second}
	c := &claims.Checker{LLM: client, Model: model, Config: cfg, Fetcher: extract.NewFetcher(ua), Now: time.Now, Log: log}
	if k := os.Getenv("GOOGLE_FACTCHECK_API_KEY"); k != "" {
		c.FactCheck = &search.FactCheckAPI{APIKey: k, HTTP: hc}
	}
	if k := os.Getenv("BRAVE_API_KEY"); k != "" {
		// Brave bills per query; the daily cap keeps the monthly free credit.
		c.Providers = append(c.Providers, &search.Budget{Provider: &search.Brave{APIKey: k, HTTP: hc},
			PerDay: envInt("BRAVE_DAILY_LIMIT", 30), Now: time.Now})
	}
	if env("WIKIPEDIA", "on") != "off" {
		c.Providers = append(c.Providers, &search.Wikipedia{UserAgent: ua, HTTP: hc})
	}
	log.Info("claim checking", "providers", len(c.Providers), "factcheck", c.FactCheck != nil, "method", cfg.Method)
	return c, nil
}
