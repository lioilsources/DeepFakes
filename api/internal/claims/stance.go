package claims

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"

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

// dateOf formats a date for the prompts; unknown dates are said so.
func dateOf(t *time.Time) string {
	if t == nil || t.IsZero() {
		return "unknown"
	}
	return t.UTC().Format("2006-01-02")
}

func stanceMessage(cl Claim, ps []passage, lang string, claimDate *time.Time) string {
	var sb strings.Builder
	if lang == "" {
		lang = "en"
	}
	fmt.Fprintf(&sb, "LANG: %s\nCLAIM_DATE: %s\n\n<claim>%s</claim>\n\n", lang, dateOf(claimDate), sanitize(cl.Claim))
	for i, p := range ps {
		fmt.Fprintf(&sb, "<passage id=\"%d\" source=\"%s\" date=\"%s\">\n%s\n</passage>\n\n",
			i+1, sanitize(p.page.host), dateOf(p.page.published), sanitize(p.text))
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

// JudgeStats counts judgements the gates removed.
type JudgeStats struct {
	Dropped         int `json:"quotes_dropped"`   // quote not found in the passage
	OffTopic        int `json:"off_topic"`        // quote shares no anchor with the claim
	RefutesRejected int `json:"refutes_rejected"` // contradiction not confirmed by the refute check
}

func (c *Checker) judge(ctx context.Context, cl Claim, ps []passage, lang string, claimDate *time.Time) ([]judged, string, JudgeStats, error) {
	req := llm.Request{System: stancePrompt, User: stanceMessage(cl, ps, lang, claimDate), MaxTokens: 600 + 250*len(ps)}
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		out, _, err := c.LLM.ChatJSON(ctx, req)
		if err != nil {
			lastErr = err
			if ctx.Err() != nil {
				return nil, "", JudgeStats{}, ctx.Err()
			}
			continue
		}
		var raw rawStance
		if err := json.Unmarshal([]byte(llm.ExtractJSON(out)), &raw); err != nil {
			lastErr = fmt.Errorf("decode model json: %w", err)
			continue
		}
		var st JudgeStats
		js, dropped, off := validateStance(cl, raw, ps)
		st.Dropped, st.OffTopic = dropped, off
		js, st.RefutesRejected, err = c.confirmRefutes(ctx, cl, js, claimDate)
		if err != nil {
			return nil, "", JudgeStats{}, err
		}
		expl := strings.TrimSpace(raw.Explanation)
		if len(js) == 0 || st.RefutesRejected > 0 {
			// No verdict, no narrative; a rejected refutation would make the
			// model's explanation contradict the evidence that is kept.
			expl = ""
		}
		return js, expl, st, nil
	}
	return nil, "", JudgeStats{}, lastErr
}

// confirmRefutes asks a focused second question for every "refutes"
// judgement: same quantity, period, unit and scope? The stance prompt alone
// lets the model treat e.g. a yearly total as refuting a monthly figure.
// Unconfirmed refutations are dropped (fail closed: a refutation is the
// stronger statement). An LLM error keeps the judgement out as well.
func (c *Checker) confirmRefutes(ctx context.Context, cl Claim, js []judged, claimDate *time.Time) ([]judged, int, error) {
	out := js[:0:0]
	rejected := 0
	for _, j := range js {
		if j.stance != StanceRefutes {
			out = append(out, j)
			continue
		}
		if c.Config.laterThanClaim(j.p.page, claimDate) {
			rejected++
			continue
		}
		ok, err := c.contradicts(ctx, cl, j, claimDate)
		if err != nil && ctx.Err() != nil {
			return nil, 0, ctx.Err()
		}
		if !ok {
			rejected++
			continue
		}
		out = append(out, j)
	}
	return out, rejected, nil
}

// laterThanClaim reports whether a page was published after the claim was
// made (plus grace). Such a page may describe later events, which do not
// refute a statement about the situation at that time. Fact-checkers (they
// come after the claim by nature) and primary sources (official denials)
// are exempt. Pages without a date are kept.
func (c Config) laterThanClaim(pg *page, claimDate *time.Time) bool {
	g := c.Verdict.LaterRefuteGraceHours
	if g < 0 || claimDate == nil || claimDate.IsZero() || pg.published == nil || pg.published.IsZero() ||
		pg.sourceType == "fact_checker" || pg.sourceType == "primary" {
		return false
	}
	return pg.published.After(claimDate.Add(time.Duration(g) * time.Hour))
}

func (c *Checker) contradicts(ctx context.Context, cl Claim, j judged, claimDate *time.Time) (bool, error) {
	user := fmt.Sprintf("CLAIM_DATE: %s\nPASSAGE_DATE: %s\n\n<claim>%s</claim>\n\n<passage>\n%s\n</passage>\n\n<quote>%s</quote>\n",
		dateOf(claimDate), dateOf(j.p.page.published), sanitize(cl.Claim), sanitize(j.p.text), sanitize(j.quote))
	out, _, err := c.LLM.ChatJSON(ctx, llm.Request{System: refutePrompt, User: user, MaxTokens: 300})
	if err != nil {
		return false, err
	}
	var r struct {
		Contradicts bool `json:"contradicts"`
	}
	if err := json.Unmarshal([]byte(llm.ExtractJSON(out)), &r); err != nil {
		return false, fmt.Errorf("decode refute json: %w", err)
	}
	return r.Contradicts, nil
}

// StanceResult is one judged passage, for offline evaluation.
type StanceResult struct {
	Passage    int     `json:"passage"` // 1-based
	Stance     string  `json:"stance"`
	Quote      string  `json:"quote"`
	Confidence float64 `json:"confidence"`
}

// JudgeTexts runs the production stance step (prompt, quote gate, anchor
// check, refute check) on plain passages. Used by cmd/stance-eval.
func (c *Checker) JudgeTexts(ctx context.Context, claim, lang string, passages []string) ([]StanceResult, JudgeStats, error) {
	pg := &page{host: "eval"}
	ps := make([]passage, len(passages))
	idx := map[string]int{}
	for i, t := range passages {
		ps[i] = passage{page: pg, text: t}
		idx[t] = i + 1
	}
	js, _, st, err := c.judge(ctx, Claim{Claim: claim}, ps, lang, nil)
	if err != nil {
		return nil, JudgeStats{}, err
	}
	out := make([]StanceResult, len(js))
	for i, j := range js {
		out[i] = StanceResult{Passage: idx[j.p.text], Stance: j.stance, Quote: j.quote, Confidence: j.confidence}
	}
	return out, st, nil
}
