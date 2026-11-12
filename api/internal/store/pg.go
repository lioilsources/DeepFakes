package store

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5" // migrate driver "pgx5"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lioilsources/DeepFakes/api/internal/store/db"
	"github.com/lioilsources/DeepFakes/api/internal/temperature"
)

//go:embed migrations/*.sql
var migrations embed.FS

// Migrate applies all pending migrations. dsn is a postgres:// URL.
func Migrate(dsn string) error {
	src, err := iofs.New(migrations, "migrations")
	if err != nil {
		return fmt.Errorf("migrations source: %w", err)
	}
	m, err := migrate.NewWithSourceInstance("iofs", src, "pgx5://"+trimScheme(dsn))
	if err != nil {
		return fmt.Errorf("migrate init: %w", err)
	}
	defer m.Close()
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("migrate up: %w", err)
	}
	return nil
}

func trimScheme(dsn string) string {
	for _, p := range []string{"postgres://", "postgresql://"} {
		if len(dsn) > len(p) && dsn[:len(p)] == p {
			return dsn[len(p):]
		}
	}
	return dsn
}

// Postgres is the production Store.
type Postgres struct {
	pool *pgxpool.Pool
	q    *db.Queries
}

// OpenPostgres connects to the database (migrations are separate).
func OpenPostgres(ctx context.Context, dsn string) (*Postgres, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("pg pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pg ping: %w", err)
	}
	return &Postgres{pool: pool, q: db.New(pool)}, nil
}

// Close releases the pool.
func (s *Postgres) Close() { s.pool.Close() }

func ts(t time.Time) pgtype.Timestamptz { return pgtype.Timestamptz{Time: t, Valid: !t.IsZero()} }

func txt(s string) pgtype.Text { return pgtype.Text{String: s, Valid: s != ""} }

func (s *Postgres) CreateAnalysis(ctx context.Context, a Analysis) error {
	err := s.q.CreateAnalysis(ctx, db.CreateAnalysisParams{ID: a.ID, CacheKey: a.CacheKey, Kind: a.Kind,
		SourceUrl: txt(a.SourceURL), CreatedAt: ts(a.CreatedAt)})
	if err != nil {
		return fmt.Errorf("create analysis: %w", err)
	}
	return nil
}

func (s *Postgres) FindCached(ctx context.Context, key string, since time.Time) (string, bool, error) {
	id, err := s.q.FindCached(ctx, db.FindCachedParams{CacheKey: key, CreatedAt: ts(since)})
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("find cached: %w", err)
	}
	return id, true, nil
}

func (s *Postgres) SetStatus(ctx context.Context, id, status string, e *Error, at time.Time) error {
	p := db.SetStatusParams{ID: id, Status: status}
	if e != nil {
		p.ErrorCode, p.ErrorMessage = txt(e.Code), txt(e.Message)
	}
	if status == StatusDone || status == StatusFailed {
		p.FinishedAt = ts(at)
	}
	if err := s.q.SetStatus(ctx, p); err != nil {
		return fmt.Errorf("set status: %w", err)
	}
	return nil
}

func (s *Postgres) FailUnfinished(ctx context.Context, at time.Time) (int64, error) {
	n, err := s.q.FailUnfinished(ctx, ts(at))
	if err != nil {
		return 0, fmt.Errorf("fail unfinished: %w", err)
	}
	return n, nil
}

func (s *Postgres) SaveDocument(ctx context.Context, id string, d Document) error {
	paras, err := json.Marshal(d.Paragraphs)
	if err != nil {
		return fmt.Errorf("marshal paragraphs: %w", err)
	}
	p := db.SaveDocumentParams{AnalysisID: id, Url: txt(d.URL), Title: d.Title, Author: d.Author, Site: d.Site,
		Language: d.Language, ContentHash: d.ContentHash, Truncated: d.Truncated, Paragraphs: paras}
	if d.PublishedAt != nil {
		p.PublishedAt = ts(*d.PublishedAt)
	}
	if err := s.q.SaveDocument(ctx, p); err != nil {
		return fmt.Errorf("save document: %w", err)
	}
	return nil
}

func (s *Postgres) SaveParagraph(ctx context.Context, id string, p temperature.Paragraph) error {
	emo, err := json.Marshal(p.Emotions)
	if err != nil {
		return fmt.Errorf("marshal emotions: %w", err)
	}
	tech, err := json.Marshal(p.Techniques)
	if err != nil {
		return fmt.Errorf("marshal techniques: %w", err)
	}
	err = s.q.SaveParagraph(ctx, db.SaveParagraphParams{AnalysisID: id, P: int32(p.P), Score: int32(p.Score),
		Emotions: emo, LoadedLanguage: float32(p.LoadedLanguage), Techniques: tech})
	if err != nil {
		return fmt.Errorf("save paragraph: %w", err)
	}
	return nil
}

func (s *Postgres) SaveSummary(ctx context.Context, id string, sum temperature.Summary) error {
	b, err := json.Marshal(sum)
	if err != nil {
		return fmt.Errorf("marshal summary: %w", err)
	}
	if err := s.q.SaveSummary(ctx, db.SaveSummaryParams{AnalysisID: id, Score: int32(sum.Score), Method: sum.Method, Summary: b}); err != nil {
		return fmt.Errorf("save summary: %w", err)
	}
	return nil
}

func (s *Postgres) Get(ctx context.Context, id string) (Result, error) {
	a, err := s.q.GetAnalysis(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return Result{}, ErrNotFound
	}
	if err != nil {
		return Result{}, fmt.Errorf("get analysis: %w", err)
	}
	r := Result{ID: a.ID, Status: a.Status, Paragraphs: []temperature.Paragraph{}}
	if a.ErrorCode.Valid {
		r.Error = &Error{Code: a.ErrorCode.String, Message: a.ErrorMessage.String}
	}
	d, err := s.q.GetDocument(ctx, id)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
	case err != nil:
		return Result{}, fmt.Errorf("get document: %w", err)
	default:
		doc := Document{URL: d.Url.String, Title: d.Title, Author: d.Author, Site: d.Site, Language: d.Language,
			ContentHash: d.ContentHash, Truncated: d.Truncated, Purged: d.PurgedAt.Valid, Paragraphs: []Paragraph{}}
		if d.PublishedAt.Valid {
			t := d.PublishedAt.Time.UTC()
			doc.PublishedAt = &t
		}
		if len(d.Paragraphs) > 0 {
			if err := json.Unmarshal(d.Paragraphs, &doc.Paragraphs); err != nil {
				return Result{}, fmt.Errorf("decode paragraphs: %w", err)
			}
		}
		r.Document = &doc
	}
	rows, err := s.q.ListParagraphs(ctx, id)
	if err != nil {
		return Result{}, fmt.Errorf("list paragraphs: %w", err)
	}
	for _, row := range rows {
		p := temperature.Paragraph{P: int(row.P), Score: int(row.Score), LoadedLanguage: float64(row.LoadedLanguage)}
		if err := json.Unmarshal(row.Emotions, &p.Emotions); err != nil {
			return Result{}, fmt.Errorf("decode emotions: %w", err)
		}
		if err := json.Unmarshal(row.Techniques, &p.Techniques); err != nil {
			return Result{}, fmt.Errorf("decode techniques: %w", err)
		}
		r.Paragraphs = append(r.Paragraphs, p)
	}
	sum, err := s.q.GetSummary(ctx, id)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
	case err != nil:
		return Result{}, fmt.Errorf("get summary: %w", err)
	default:
		var s temperature.Summary
		if err := json.Unmarshal(sum.Summary, &s); err != nil {
			return Result{}, fmt.Errorf("decode summary: %w", err)
		}
		r.Summary = &s
	}
	return r, nil
}

func (s *Postgres) Purge(ctx context.Context, cutoff, at time.Time) (int, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("purge begin: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck // no-op after commit
	q := s.q.WithTx(tx)
	ids, err := q.PurgeTexts(ctx, db.PurgeTextsParams{PurgedAt: ts(at), CreatedAt: ts(cutoff)})
	if err != nil {
		return 0, fmt.Errorf("purge texts: %w", err)
	}
	if len(ids) > 0 {
		if err := q.StripQuotes(ctx, ids); err != nil {
			return 0, fmt.Errorf("strip quotes: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("purge commit: %w", err)
	}
	return len(ids), nil
}
