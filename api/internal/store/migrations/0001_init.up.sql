CREATE TABLE analyses (
    id            text PRIMARY KEY,
    cache_key     text        NOT NULL,
    kind          text        NOT NULL CHECK (kind IN ('url', 'text')),
    source_url    text,
    status        text        NOT NULL CHECK (status IN ('queued', 'running', 'done', 'failed')),
    error_code    text,
    error_message text,
    created_at    timestamptz NOT NULL,
    finished_at   timestamptz
);
CREATE INDEX analyses_cache_key_idx ON analyses (cache_key, created_at DESC);
CREATE INDEX analyses_created_at_idx ON analyses (created_at);

CREATE TABLE documents (
    analysis_id  text PRIMARY KEY REFERENCES analyses (id) ON DELETE CASCADE,
    url          text,
    title        text        NOT NULL DEFAULT '',
    author       text        NOT NULL DEFAULT '',
    published_at timestamptz,
    site         text        NOT NULL DEFAULT '',
    language     text        NOT NULL,
    content_hash text        NOT NULL,
    truncated    boolean     NOT NULL DEFAULT false,
    -- Full paragraph texts; set to NULL after CACHE_TTL (only metrics stay).
    paragraphs   jsonb,
    purged_at    timestamptz
);
CREATE INDEX documents_content_hash_idx ON documents (content_hash);

CREATE TABLE temperature (
    analysis_id     text    NOT NULL REFERENCES analyses (id) ON DELETE CASCADE,
    p               integer NOT NULL,
    score           integer NOT NULL,
    emotions        jsonb   NOT NULL,
    loaded_language real    NOT NULL,
    techniques      jsonb   NOT NULL,
    PRIMARY KEY (analysis_id, p)
);

CREATE TABLE temperature_summaries (
    analysis_id text PRIMARY KEY REFERENCES analyses (id) ON DELETE CASCADE,
    score       integer NOT NULL,
    method      text    NOT NULL,
    summary     jsonb   NOT NULL
);
