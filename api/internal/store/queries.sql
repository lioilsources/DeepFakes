-- name: CreateAnalysis :exec
INSERT INTO analyses (id, cache_key, kind, source_url, status, created_at)
VALUES ($1, $2, $3, $4, 'queued', $5);

-- name: FindCached :one
SELECT a.id FROM analyses a
LEFT JOIN documents d ON d.analysis_id = a.id
WHERE a.cache_key = $1 AND a.created_at >= $2
  AND a.status IN ('queued', 'running', 'done')
  AND d.purged_at IS NULL
ORDER BY a.created_at DESC
LIMIT 1;

-- name: SetStatus :exec
UPDATE analyses SET status = $2, error_code = $3, error_message = $4, finished_at = $5 WHERE id = $1;

-- name: FailUnfinished :execrows
UPDATE analyses SET status = 'failed', error_code = 'internal', error_message = 'server restarted', finished_at = $1
WHERE status IN ('queued', 'running');

-- name: SaveDocument :exec
INSERT INTO documents (analysis_id, url, title, author, published_at, site, language, content_hash, truncated, paragraphs)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);

-- name: SaveParagraph :exec
INSERT INTO temperature (analysis_id, p, score, emotions, loaded_language, techniques)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (analysis_id, p) DO UPDATE
SET score = EXCLUDED.score, emotions = EXCLUDED.emotions,
    loaded_language = EXCLUDED.loaded_language, techniques = EXCLUDED.techniques;

-- name: SaveSummary :exec
INSERT INTO temperature_summaries (analysis_id, score, method, summary) VALUES ($1, $2, $3, $4)
ON CONFLICT (analysis_id) DO UPDATE SET score = EXCLUDED.score, method = EXCLUDED.method, summary = EXCLUDED.summary;

-- name: GetAnalysis :one
SELECT * FROM analyses WHERE id = $1;

-- name: GetDocument :one
SELECT * FROM documents WHERE analysis_id = $1;

-- name: ListParagraphs :many
SELECT * FROM temperature WHERE analysis_id = $1 ORDER BY p;

-- name: GetSummary :one
SELECT * FROM temperature_summaries WHERE analysis_id = $1;

-- name: PurgeTexts :many
UPDATE documents SET paragraphs = NULL, purged_at = $1
WHERE purged_at IS NULL
  AND analysis_id IN (SELECT id FROM analyses WHERE created_at < $2)
RETURNING analysis_id;

-- name: StripQuotes :exec
UPDATE temperature
SET techniques = (
    SELECT coalesce(jsonb_agg(jsonb_build_object('technique', t ->> 'technique', 'confidence', t -> 'confidence')), '[]'::jsonb)
    FROM jsonb_array_elements(techniques) AS t)
WHERE analysis_id = ANY(@ids::text[]);
