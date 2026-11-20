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

// anchors are the claim's distinctive stems: numbers and longer words.
func anchors(cl Claim) map[string]bool {
	out := map[string]bool{}
	for _, t := range stems(cl.Claim + " " + cl.Quote + " " + strings.Join(cl.Entities, " ")) {
		if isNumber(t) || len([]rune(t)) >= 4 {
			out[t] = true
		}
	}
	return out
}

// anchored reports whether the evidence quote shares at least one anchor
// with the claim. It rejects judgements where the model quotes a sentence
// about something else (a cheap guard, deliberately loose).
func anchored(q string, as map[string]bool) bool {
	for _, t := range stems(q) {
		if as[t] {
			return true
		}
	}
	return false
}

// validateStance keeps supports/refutes judgements whose quote is verbatim
// in the referenced passage (or, if misnumbered, in exactly the passage
// where it is found).
func validateStance(cl Claim, raw rawStance, ps []passage) (out []judged, dropped, offTopic int) {
	seen := map[int]bool{}
	as := anchors(cl)
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
		if !anchored(sp.Quote, as) {
			offTopic++
			continue
		}
		if seen[idx] {
			continue
		}
		seen[idx] = true
		out = append(out, judged{p: ps[idx], stance: st, quote: sp.Quote, confidence: math.Max(0, math.Min(1, j.Confidence))})
	}
	return out, dropped, offTopic
}

func (c *Checker) judge(ctx context.Context, cl Claim, ps []passage, lang string) ([]judged, string, int, int, error) {
	req := llm.Request{System: stancePrompt, User: stanceMessage(cl, ps, lang), MaxTokens: 600 + 250*len(ps)}
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		out, _, err := c.LLM.ChatJSON(ctx, req)
		if err != nil {
			lastErr = err
			if ctx.Err() != nil {
				return nil, "", 0, 0, ctx.Err()
			}
			continue
		}
		var raw rawStance
		if err := json.Unmarshal([]byte(llm.ExtractJSON(out)), &raw); err != nil {
			lastErr = fmt.Errorf("decode model json: %w", err)
			continue
		}
		js, dropped, off := validateStance(cl, raw, ps)
		expl := strings.TrimSpace(raw.Explanation)
		if len(js) == 0 {
			expl = "" // no verdict, no narrative
		}
		return js, expl, dropped, off, nil
	}
	return nil, "", 0, 0, lastErr
}

// StanceResult is one judged passage, for offline evaluation.
type StanceResult struct {
	Passage    int     `json:"passage"` // 1-based
	Stance     string  `json:"stance"`
	Quote      string  `json:"quote"`
	Confidence float64 `json:"confidence"`
}

// JudgeTexts runs the production stance step (prompt, quote gate, anchor
// check) on plain passages. Used by cmd/stance-eval.
func (c *Checker) JudgeTexts(ctx context.Context, claim, lang string, passages []string) ([]StanceResult, int, int, error) {
	pg := &page{host: "eval"}
	ps := make([]passage, len(passages))
	idx := map[string]int{}
	for i, t := range passages {
		ps[i] = passage{page: pg, text: t}
		idx[t] = i + 1
	}
	js, _, dropped, off, err := c.judge(ctx, Claim{Claim: claim}, ps, lang)
	if err != nil {
		return nil, 0, 0, err
	}
	out := make([]StanceResult, len(js))
	for i, j := range js {
		out[i] = StanceResult{Passage: idx[j.p.text], Stance: j.stance, Quote: j.quote, Confidence: j.confidence}
	}
	return out, dropped, off, nil
}
