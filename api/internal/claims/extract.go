package claims

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/lioilsources/DeepFakes/api/internal/llm"
	"github.com/lioilsources/DeepFakes/api/internal/quote"
)

//go:embed claims.md
var extractPrompt string

//go:embed stance.md
var stancePrompt string

// Chatter is the LLM dependency.
type Chatter interface {
	ChatJSON(ctx context.Context, r llm.Request) (string, llm.Usage, error)
}

func sanitize(s string) string {
	r := strings.NewReplacer("<document>", "< document>", "</document>", "< /document>",
		"<passage", "< passage", "</passage>", "< /passage>", "<claim>", "< claim>", "</claim>", "< /claim>")
	return r.Replace(s)
}

type chunk struct{ first, n int }

func chunks(ps []string, limit int) []chunk {
	if limit <= 0 {
		limit = 6000
	}
	var out []chunk
	cur, size := chunk{}, 0
	for i, p := range ps {
		if cur.n > 0 && size+len(p) > limit {
			out = append(out, cur)
			cur, size = chunk{first: i}, 0
		}
		cur.n++
		size += len(p)
	}
	if cur.n > 0 {
		out = append(out, cur)
	}
	return out
}

// flexInt accepts 3, "3" and "p3".
type flexInt int

func (f *flexInt) UnmarshalJSON(b []byte) error {
	var n int
	if err := json.Unmarshal(b, &n); err == nil {
		*f = flexInt(n)
		return nil
	}
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	n, err := strconv.Atoi(strings.TrimPrefix(strings.ToLower(strings.TrimSpace(s)), "p"))
	if err != nil {
		*f = 0
		return nil //nolint:nilerr // unknown paragraph: validation searches all paragraphs
	}
	*f = flexInt(n)
	return nil
}

// flexQuery accepts {"q","lang"} or a plain string.
type flexQuery Query

func (f *flexQuery) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err == nil {
		*f = flexQuery{Q: s}
		return nil
	}
	var q Query
	if err := json.Unmarshal(b, &q); err != nil {
		return err
	}
	*f = flexQuery(q)
	return nil
}

type rawClaim struct {
	P           flexInt     `json:"p"`
	Quote       string      `json:"quote"`
	Claim       string      `json:"claim"`
	Kind        string      `json:"kind"`
	Checkworthy float64     `json:"checkworthy"`
	Entities    []string    `json:"entities"`
	Queries     []flexQuery `json:"search_queries"`
}

type rawExtract struct {
	Language string     `json:"language"`
	Claims   []rawClaim `json:"claims"`
}

func extractMessage(title string, ps []string, c chunk) string {
	var sb strings.Builder
	sb.WriteString("<document>\n")
	if title != "" {
		sb.WriteString("HEADLINE: " + sanitize(title) + "\n\n")
	}
	for i := c.first; i < c.first+c.n; i++ {
		fmt.Fprintf(&sb, "[p%d] %s\n\n", i+1, sanitize(ps[i]))
	}
	sb.WriteString("</document>")
	return sb.String()
}

// validateClaims keeps claims whose quote is verbatim in a paragraph of
// the chunk (the stated paragraph first, then the others).
func validateClaims(raw []rawClaim, ps []string, c chunk, lang string) (out []Claim, dropped int) {
	for _, r := range raw {
		kind := strings.ToLower(strings.TrimSpace(r.Kind))
		if kind != KindOpinion && kind != KindPrediction {
			kind = KindFact
		}
		text := strings.TrimSpace(r.Claim)
		if text == "" || strings.TrimSpace(r.Quote) == "" {
			dropped++
			continue
		}
		idx := int(r.P) - 1
		var sp quote.Span
		ok := false
		if idx >= c.first && idx < c.first+c.n {
			sp, ok = quote.Find(ps[idx], r.Quote, 0)
		}
		for j := c.first; !ok && j < c.first+c.n; j++ {
			if j != idx {
				if sp, ok = quote.Find(ps[j], r.Quote, 0); ok {
					idx = j
				}
			}
		}
		if !ok {
			dropped++
			continue
		}
		cl := Claim{P: idx + 1, Quote: sp.Quote, Start: sp.Start16, End: sp.End16, Claim: text, Kind: kind,
			Checkworthy: math.Max(0, math.Min(1, r.Checkworthy))}
		for _, e := range r.Entities {
			if e = strings.TrimSpace(e); e != "" && len(cl.Entities) < 6 {
				cl.Entities = append(cl.Entities, e)
			}
		}
		for _, q := range r.Queries {
			if q.Q = strings.TrimSpace(q.Q); q.Q != "" {
				if q.Lang = strings.ToLower(strings.TrimSpace(q.Lang)); len(q.Lang) != 2 {
					q.Lang = ""
				}
				cl.Queries = append(cl.Queries, Query(q))
			}
		}
		if len(cl.Queries) == 0 {
			cl.Queries = []Query{{Q: text, Lang: lang}}
		}
		out = append(out, cl)
	}
	return out, dropped
}

// extract runs the model over chunks of the document in parallel and
// returns validated, de-duplicated claims ordered by position.
func (c *Checker) extract(ctx context.Context, in Input) ([]Claim, int, error) {
	cs := chunks(in.Paragraphs, c.Config.Limits.ExtractChunkChars)
	type res struct {
		claims  []Claim
		dropped int
		err     error
	}
	results := make([]res, len(cs))
	var wg sync.WaitGroup
	for i, ch := range cs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req := llm.Request{System: extractPrompt, User: extractMessage(in.Title, in.Paragraphs, ch), MaxTokens: 4000}
			var lastErr error
			for attempt := 0; attempt < 2; attempt++ {
				out, _, err := c.LLM.ChatJSON(ctx, req)
				if err != nil {
					lastErr = err
					if ctx.Err() != nil {
						break
					}
					continue
				}
				var raw rawExtract
				if err := json.Unmarshal([]byte(llm.ExtractJSON(out)), &raw); err != nil {
					lastErr = fmt.Errorf("decode model json: %w", err)
					continue
				}
				cl, d := validateClaims(raw.Claims, in.Paragraphs, ch, in.Language)
				results[i] = res{claims: cl, dropped: d}
				return
			}
			results[i] = res{err: lastErr}
		}()
	}
	wg.Wait()
	var all []Claim
	dropped := 0
	var firstErr error
	ok := 0
	for _, r := range results {
		if r.err != nil {
			if firstErr == nil {
				firstErr = r.err
			}
			continue
		}
		ok++
		all = append(all, r.claims...)
		dropped += r.dropped
	}
	if ok == 0 {
		return nil, 0, fmt.Errorf("claim extraction failed: %w", firstErr)
	}
	sort.SliceStable(all, func(i, j int) bool {
		if all[i].P != all[j].P {
			return all[i].P < all[j].P
		}
		return all[i].Start < all[j].Start
	})
	seen := map[[3]int]bool{}
	out := all[:0]
	for _, cl := range all {
		k := [3]int{cl.P, cl.Start, cl.End}
		if seen[k] {
			continue
		}
		seen[k] = true
		cl.ID = "c" + strconv.Itoa(len(out)+1)
		out = append(out, cl)
	}
	return out, dropped, nil
}

// selectForCheck returns ids to check (best checkworthy facts) and reasons
// for the others.
func (c *Checker) selectForCheck(cls []Claim) (check map[string]bool, skip map[string]string) {
	check, skip = map[string]bool{}, map[string]string{}
	var facts []Claim
	for _, cl := range cls {
		switch {
		case cl.Kind == KindOpinion:
			skip[cl.ID] = KindOpinion
		case cl.Kind == KindPrediction:
			skip[cl.ID] = KindPrediction
		case cl.Checkworthy < c.Config.Limits.MinCheckworthy:
			skip[cl.ID] = "low_priority"
		default:
			facts = append(facts, cl)
		}
	}
	sort.SliceStable(facts, func(i, j int) bool { return facts[i].Checkworthy > facts[j].Checkworthy })
	for i, cl := range facts {
		if i < c.Config.Limits.MaxClaimsChecked {
			check[cl.ID] = true
		} else {
			skip[cl.ID] = "limit"
		}
	}
	return check, skip
}
