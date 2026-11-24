// Package claims extracts checkable claims from a document and checks them
// against downloaded evidence (plan chapter 4.3).
//
// Rules that the code enforces:
//   - No verdict without evidence: a claim without a relevant, verbatim
//     quoted passage is "unverifiable", never a guess.
//   - Every quote (claim in the article, evidence in a source) is validated
//     against the stored text; invalid quotes are dropped.
//   - The verdict is computed deterministically from the evidence with the
//     weights in config/claims.json; the model only judges single passages.
package claims

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

// Claim kinds.
const (
	KindFact       = "fact"
	KindOpinion    = "opinion"
	KindPrediction = "prediction"
)

// Verdict labels.
const (
	LabelSupported       = "supported"
	LabelMostlySupported = "mostly_supported"
	LabelDisputed        = "disputed"
	LabelRefuted         = "refuted"
	LabelUnverifiable    = "unverifiable"
	LabelNotChecked      = "not_checked"
)

// Stances of a passage towards a claim.
const (
	StanceSupports = "supports"
	StanceRefutes  = "refutes"
)

// Claim is one extracted claim. Start/End are UTF-16 offsets into the
// paragraph P (1-based) of the analysed document.
type Claim struct {
	ID          string   `json:"id"`
	P           int      `json:"p"`
	Quote       string   `json:"quote"`
	Start       int      `json:"start"`
	End         int      `json:"end"`
	Claim       string   `json:"claim"`
	Kind        string   `json:"kind"`
	Checkworthy float64  `json:"checkworthy"`
	Entities    []string `json:"entities,omitempty"`
	Queries     []Query  `json:"-"`
}

// Query is a search query proposed for a claim.
type Query struct {
	Q    string `json:"q"`
	Lang string `json:"lang"`
}

// FactCheck is rating metadata reported by a fact-check database.
type FactCheck struct {
	Publisher string `json:"publisher"`
	Rating    string `json:"rating"`
}

// Evidence is one source passage with a validated quote.
type Evidence struct {
	URL         string     `json:"url"`
	Title       string     `json:"title,omitempty"`
	Site        string     `json:"site"`
	SourceType  string     `json:"source_type"`
	Stance      string     `json:"stance"`
	Quote       string     `json:"quote"`
	Confidence  float64    `json:"confidence"`
	Weight      float64    `json:"weight"`
	Cluster     int        `json:"cluster"`
	PublishedAt *time.Time `json:"published_at,omitempty"`
	RetrievedAt time.Time  `json:"retrieved_at"`
	FactCheck   *FactCheck `json:"factcheck,omitempty"`
}

// Verdict is the result for one claim.
type Verdict struct {
	ClaimID            string     `json:"claim_id"`
	Label              string     `json:"label"`
	Reason             string     `json:"reason,omitempty"` // for not_checked: opinion|prediction|low_priority|limit; for unverifiable: no_sources|no_relevant_evidence|weak_evidence|check_failed
	Confidence         float64    `json:"confidence"`
	Explanation        string     `json:"explanation,omitempty"`
	Support            float64    `json:"support"`
	Refute             float64    `json:"refute"`
	IndependentSources int        `json:"independent_sources"`
	SourcesConsidered  int        `json:"sources_considered"`
	Evidence           []Evidence `json:"evidence"`
}

// Summary aggregates the claims of a document.
type Summary struct {
	ClaimsFound           int            `json:"claims_found"`
	Checked               int            `json:"checked"`
	ByLabel               map[string]int `json:"by_label"`
	QuotesDropped         int            `json:"quotes_dropped"`
	EvidenceQuotesDropped int            `json:"evidence_quotes_dropped"`
	EvidenceOffTopic      int            `json:"evidence_off_topic"`
	RefutesRejected       int            `json:"refutes_rejected"`
	Searches              int            `json:"searches"`
	SearchErrors          int            `json:"search_errors"`
	PagesFetched          int            `json:"pages_fetched"`
	Providers             []string       `json:"providers"`
	Model                 string         `json:"model"`
	Method                string         `json:"method"`
	LatencyMS             int64          `json:"latency_ms"`
	Error                 string         `json:"error,omitempty"`
}

// Config is config/claims.json.
type Config struct {
	Method string `json:"method"`
	Limits struct {
		MaxClaimsChecked  int     `json:"max_claims_checked"`
		MinCheckworthy    float64 `json:"min_checkworthy"`
		ExtractChunkChars int     `json:"extract_chunk_chars"`
		QueriesPerClaim   int     `json:"queries_per_claim"`
		HitsPerQuery      int     `json:"hits_per_query"`
		PagesPerClaim     int     `json:"pages_per_claim"`
		PassagesPerClaim  int     `json:"passages_per_claim"`
		PassagesPerPage   int     `json:"passages_per_page"`
		PassageChars      int     `json:"passage_chars"`
		FetchConcurrency  int     `json:"fetch_concurrency"`
		ClaimConcurrency  int     `json:"claim_concurrency"`
	} `json:"limits"`
	SourceWeights map[string]float64 `json:"source_weights"`
	DomainTypes   map[string]string  `json:"domain_types"`
	Verdict       struct {
		MinRelevant          float64 `json:"min_relevant"`
		Supported            float64 `json:"supported"`
		MostlySupported      float64 `json:"mostly_supported"`
		Refuted              float64 `json:"refuted"`
		DisputeRatio         float64 `json:"dispute_ratio"`
		NearDuplicateJaccard float64 `json:"near_duplicate_jaccard"`
		// RefutedNeedsKnownSource: "refuted" needs at least one refuting
		// source whose type is not "unknown" (an agency site plus a company
		// catalogue is not enough to call a claim false).
		RefutedNeedsKnownSource bool `json:"refuted_needs_known_source"`
		// LaterRefuteGraceHours: a refutation from a page published more
		// than this many hours after the claim was made is dropped (later
		// events do not refute a statement about the situation at that
		// time). Fact-checkers and primary sources (official denials) are
		// exempt. Negative disables the rule.
		LaterRefuteGraceHours int `json:"later_refute_grace_hours"`
	} `json:"verdict"`
}

// ParseConfig decodes and sanity-checks the configuration.
func ParseConfig(b []byte) (Config, error) {
	var c Config
	if err := json.Unmarshal(b, &c); err != nil {
		return c, fmt.Errorf("claims config: %w", err)
	}
	l := c.Limits
	switch {
	case c.Method == "":
		return c, errors.New("claims config: method missing")
	case l.MaxClaimsChecked <= 0 || l.PagesPerClaim <= 0 || l.PassagesPerClaim <= 0 || l.PassageChars <= 0 || l.HitsPerQuery <= 0:
		return c, errors.New("claims config: limits must be positive")
	case c.SourceWeights["unknown"] <= 0:
		return c, errors.New("claims config: source_weights.unknown missing")
	case c.Verdict.MostlySupported > c.Verdict.Supported || c.Verdict.MinRelevant <= 0:
		return c, errors.New("claims config: inconsistent verdict thresholds")
	}
	for d, t := range c.DomainTypes {
		if _, ok := c.SourceWeights[t]; !ok {
			return c, fmt.Errorf("claims config: domain %s has unknown type %q", d, t)
		}
	}
	return c, nil
}
