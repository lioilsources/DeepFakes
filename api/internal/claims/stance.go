package claims

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"

	"github.com/lioilsources/DeepFakes/api/internal/llm"
	"github.com/lioilsources/DeepFakes/api/internal/quote"
)

type rawJudgement struct {
	ID         flexInt `json:"id"`
	Stance     string  `json:"stance"`
	Quote      string  `json:"quote"`
	Confidence float64 `json:"confidence"`
}

type rawStance struct {
	Judgements  []rawJudgement `json:"judgements"`
	Explanation string         `json:"explanation"`
}

func stanceMessage(cl Claim, ps []passage, lang string) string {
	var sb strings.Builder
	if lang == "" {
		lang = "en"
	}
	fmt.Fprintf(&sb, "LANG: %s\n\n<claim>%s</claim>\n\n", lang, sanitize(cl.Claim))
	for i, p := range ps {
		fmt.Fprintf(&sb, "<passage id=\"%d\" source=\"%s\">\n%s\n</passage>\n\n", i+1, sanitize(p.page.host), sanitize(p.text))
	}
	return sb.String()
}

// judged is a validated stance of one passage.
type judged struct {
	p          passage
	stance     string
	quote      string
	confidence float64
}

// validateStance keeps supports/refutes judgements whose quote is verbatim
// in the referenced passage (or, if misnumbered, in exactly the passage
// where it is found).
func validateStance(raw rawStance, ps []passage) (out []judged, dropped int) {
	seen := map[int]bool{}
	for _, j := range raw.Judgements {
		st := strings.ToLower(strings.TrimSpace(j.Stance))
		if st != StanceSupports && st != StanceRefutes {
			continue
		}
		idx := int(j.ID) - 1
		var sp quote.Span
		ok := false
		if idx >= 0 && idx < len(ps) {
			sp, ok = quote.Find(ps[idx].text, j.Quote, 0)
		}
		for k := 0; !ok && k < len(ps); k++ {
			if k != idx {
				if sp, ok = quote.Find(ps[k].text, j.Quote, 0); ok {
					idx = k
				}
			}
		}
		if !ok || strings.TrimSpace(j.Quote) == "" {
			dropped++
			continue
		}
		if seen[idx] {
			continue
		}
		seen[idx] = true
		out = append(out, judged{p: ps[idx], stance: st, quote: sp.Quote, confidence: math.Max(0, math.Min(1, j.Confidence))})
	}
	return out, dropped
}

func (c *Checker) judge(ctx context.Context, cl Claim, ps []passage, lang string) ([]judged, string, int, error) {
	req := llm.Request{System: stancePrompt, User: stanceMessage(cl, ps, lang), MaxTokens: 600 + 250*len(ps)}
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		out, _, err := c.LLM.ChatJSON(ctx, req)
		if err != nil {
			lastErr = err
			if ctx.Err() != nil {
				return nil, "", 0, ctx.Err()
			}
			continue
		}
		var raw rawStance
		if err := json.Unmarshal([]byte(llm.ExtractJSON(out)), &raw); err != nil {
			lastErr = fmt.Errorf("decode model json: %w", err)
			continue
		}
		js, dropped := validateStance(raw, ps)
		expl := strings.TrimSpace(raw.Explanation)
		if len(js) == 0 {
			expl = "" // no verdict, no narrative
		}
		return js, expl, dropped, nil
	}
	return nil, "", 0, lastErr
}
