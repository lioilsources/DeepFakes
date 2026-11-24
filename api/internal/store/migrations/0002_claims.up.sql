CREATE TABLE claims (
    analysis_id text    NOT NULL REFERENCES analyses (id) ON DELETE CASCADE,
    claim_id    text    NOT NULL,
    p           integer NOT NULL,
    kind        text    NOT NULL,
    checkworthy real    NOT NULL,
    -- Claim text and quote; reduced to metadata after CACHE_TTL.
    data        jsonb   NOT NULL,
    label       text,
    -- Verdict with evidence; evidence quotes and explanation dropped after CACHE_TTL.
    verdict     jsonb,
    PRIMARY KEY (analysis_id, claim_id)
);

CREATE TABLE claims_summaries (
    analysis_id text  PRIMARY KEY REFERENCES analyses (id) ON DELETE CASCADE,
    method      text  NOT NULL,
    summary     jsonb NOT NULL
);
