// Package temperature measures emotional charge and persuasion techniques
// per paragraph (plan chapter 4.2, phase 1: LLM with structured JSON).
//
// Temperature is not truthfulness: an emotional text can be true and a calm
// one false. Every technique carries a verbatim quote that is validated
// against the paragraph; unverifiable quotes are dropped.
package temperature

import (
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/lioilsources/DeepFakes/api/internal/llm"
	"github.com/lioilsources/DeepFakes/api/internal/quote"
)

//go:embed prompt.md
var systemPrompt string

// Techniques is the closed taxonomy (subset of SemEval-2023 Task 3).
var Techniques = []string{
	"name_calling", "loaded_language", "fear_appeal", "false_dilemma", "whataboutism",
	"appeal_to_authority", "straw_man", "exaggeration", "repetition", "doubt",
	"flag_waving", "slogans", "causal_oversimplification", "bandwagon", "red_herring",
}

var techniqueSet = func() map[string]bool {
	m := make(map[string]bool, len(Techniques))
	for _, t := range Techniques {
		m[t] = true
	}
	return m
}()

// Emotions are intensities 0–1.
type Emotions struct {
	Anger    float64 `json:"anger"`
	Fear     float64 `json:"fear"`
	Disgust  float64 `json:"disgust"`
	Sadness  float64 `json:"sadness"`
	Joy      float64 `json:"joy"`
	Surprise float64 `json:"surprise"`
	Neutral  float64 `json:"neutral"`
}

func (e Emotions) clamp() Emotions {
	c := func(v float64) float64 { return math.Max(0, math.Min(1, v)) }
	return Emotions{c(e.Anger), c(e.Fear), c(e.Disgust), c(e.Sadness), c(e.Joy), c(e.Surprise), c(e.Neutral)}
}

func (e Emotions) scaled(k float64) Emotions {
	return Emotions{e.Anger * k, e.Fear * k, e.Disgust * k, e.Sadness * k, e.Joy * k, e.Surprise * k, e.Neutral * k}
}

func (e Emotions) add(o Emotions) Emotions {
	return Emotions{e.Anger + o.Anger, e.Fear + o.Fear, e.Disgust + o.Disgust, e.Sadness + o.Sadness,
		e.Joy + o.Joy, e.Surprise + o.Surprise, e.Neutral + o.Neutral}
}

func (e Emotions) rounded() Emotions {
	r := func(v float64) float64 { return math.Round(v*100) / 100 }
	return Emotions{r(e.Anger), r(e.Fear), r(e.Disgust), r(e.Sadness), r(e.Joy), r(e.Surprise), r(e.Neutral)}
}

// Technique is one detected persuasion technique with a validated quote.
// Start/End are UTF-16 offsets into the paragraph text.
type Technique struct {
	Technique  string  `json:"technique"`
	Quote      string  `json:"quote"`
	Start      int     `json:"start"`
	End        int     `json:"end"`
	Confidence float64 `json:"confidence"`
}

// Paragraph is the result for one paragraph.
type Paragraph struct {
	P              int         `json:"p"`
	Score          int         `json:"score"`
	Emotions       Emotions    `json:"emotions"`
	LoadedLanguage float64     `json:"loaded_language"`
	Techniques     []Technique `json:"techniques"`
}

// Summary aggregates the document.
type Summary struct {
	Score               int            `json:"score"`
	Emotions            Emotions       `json:"emotions"`
	Techniques          map[string]int `json:"techniques"`
	HeadlineClickbait   float64        `json:"headline_clickbait"`
	HeadlineMatchesBody *bool          `json:"headline_matches_body,omitempty"`
	ParagraphsAnalyzed  int            `json:"paragraphs_analyzed"`
	ParagraphsFailed    int            `json:"paragraphs_failed"`
	QuotesDropped       int            `json:"quotes_dropped"`
	Model               string         `json:"model"`
	Method              string         `json:"method"`
	LatencyMS           int64          `json:"latency_ms"`
}

// Weights configure the score; loaded from config/temperature.json.
type Weights struct {
	Method    string `json:"method"`
	Paragraph struct {
		Emotion        float64 `json:"emotion"`
		LoadedLanguage float64 `json:"loaded_language"`
		Techniques     float64 `json:"techniques"`
	} `json:"paragraph"`
	Emotions   map[string]float64 `json:"emotions"`
	Techniques map[string]float64 `json:"techniques"`
	Document   struct {
		Paragraphs        float64 `json:"paragraphs"`
		HeadlineClickbait float64 `json:"headline_clickbait"`
	} `json:"document"`
	MinTechniqueConfidence float64 `json:"min_technique_confidence"`
}

// ParseWeights decodes and sanity-checks a weights file.
func ParseWeights(b []byte) (Weights, error) {
	var w Weights
	if err := json.Unmarshal(b, &w); err != nil {
		return w, fmt.Errorf("weights: %w", err)
	}
	p := w.Paragraph
	if s := p.Emotion + p.LoadedLanguage + p.Techniques; math.Abs(s-1) > 1e-6 {
		return w, fmt.Errorf("weights: paragraph weights sum to %.3f, want 1", s)
	}
	if s := w.Document.Paragraphs + w.Document.HeadlineClickbait; math.Abs(s-1) > 1e-6 {
		return w, fmt.Errorf("weights: document weights sum to %.3f, want 1", s)
	}
	if w.Method == "" {
		return w, errors.New("weights: method missing")
	}
	return w, nil
}

func (w Weights) techWeight(t string) float64 {
	if v, ok := w.Techniques[t]; ok {
		return v
	}
	return w.Techniques["default"]
}

func (w Weights) paragraphScore(p Paragraph) int {
	e := p.Emotions
	emo := 0.0
	for k, v := range map[string]float64{"anger": e.Anger, "fear": e.Fear, "disgust": e.Disgust,
		"sadness": e.Sadness, "joy": e.Joy, "surprise": e.Surprise} {
		emo = math.Max(emo, v*w.Emotions[k])
	}
	keep := 1.0
	for _, t := range p.Techniques {
		keep *= 1 - math.Min(1, w.techWeight(t.Technique)*t.Confidence)
	}
	s := w.Paragraph.Emotion*emo + w.Paragraph.LoadedLanguage*p.LoadedLanguage + w.Paragraph.Techniques*(1-keep)
	return int(math.Round(100 * math.Max(0, math.Min(1, s))))
}

// Chatter is the LLM dependency.
type Chatter interface {
	ChatJSON(ctx context.Context, r llm.Request) (string, llm.Usage, error)
}

// Analyzer runs the LLM over blocks of paragraphs in parallel.
type Analyzer struct {
	LLM         Chatter
	Model       string // reported in Summary
	Weights     Weights
	Concurrency int // parallel LLM requests per document
	BlockChars  int // max characters per request
	Now         func() time.Time
	Log         *slog.Logger
}

// Input is the document to analyse.
type Input struct {
	Title      string
	Paragraphs []string
}

type block struct {
	first int // index into paragraphs
	n     int
}

func (a *Analyzer) blocks(ps []string) []block {
	limit := a.BlockChars
	if limit <= 0 {
		limit = 2500
	}
	var out []block
	cur := block{}
	size := 0
	for i, p := range ps {
		if cur.n > 0 && size+len(p) > limit {
			out = append(out, cur)
			cur, size = block{first: i}, 0
		}
		cur.n++
		size += len(p)
	}
	if cur.n > 0 {
		out = append(out, cur)
	}
	return out
}

func sanitize(s string) string {
	r := strings.NewReplacer("<document>", "< document>", "</document>", "< /document>")
	return r.Replace(s)
}

func userMessage(title string, ps []string, b block) string {
	var sb strings.Builder
	sb.WriteString("<document>\n")
	if title != "" {
		sb.WriteString("HEADLINE: " + sanitize(title) + "\n\n")
	}
	for i := b.first; i < b.first+b.n; i++ {
		fmt.Fprintf(&sb, "[p%d] %s\n\n", i+1, sanitize(ps[i]))
	}
	sb.WriteString("</document>")
	return sb.String()
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
		return err
	}
	*f = flexInt(n)
	return nil
}

type rawTechnique struct {
	Technique  string  `json:"technique"`
	Quote      string  `json:"quote"`
	Confidence float64 `json:"confidence"`
}

type rawResponse struct {
	HeadlineClickbait   float64 `json:"headline_clickbait"`
	HeadlineMatchesBody *bool   `json:"headline_matches_body"`
	Paragraphs          []struct {
		P              flexInt        `json:"p"`
		Emotions       Emotions       `json:"emotions"`
		LoadedLanguage float64        `json:"loaded_language"`
		Techniques     []rawTechnique `json:"techniques"`
	} `json:"paragraphs"`
}

type blockResult struct {
	paragraphs []Paragraph
	dropped    int
	clickbait  float64
	matches    *bool
}

// validate turns a raw model answer into results, dropping anything that
// does not belong to the block or cannot be quoted verbatim. A quote that
// is verbatim in a different paragraph of the same block is moved there
// (models often misnumber paragraphs); it is still a validated quote.
func (a *Analyzer) validate(raw rawResponse, ps []string, b block) blockResult {
	res := blockResult{clickbait: math.Max(0, math.Min(1, raw.HeadlineClickbait)), matches: raw.HeadlineMatchesBody}
	byIdx := map[int]*Paragraph{}
	var order []int
	type pending struct {
		idx int
		t   rawTechnique
	}
	var techs []pending
	for _, rp := range raw.Paragraphs {
		idx := int(rp.P) - 1
		if idx < b.first || idx >= b.first+b.n || byIdx[idx] != nil {
			continue
		}
		byIdx[idx] = &Paragraph{P: idx + 1, Emotions: rp.Emotions.clamp(), Techniques: []Technique{},
			LoadedLanguage: math.Max(0, math.Min(1, rp.LoadedLanguage))}
		order = append(order, idx)
		for _, t := range rp.Techniques {
			techs = append(techs, pending{idx, t})
		}
	}
	spans := map[[3]int]bool{}
	for _, pt := range techs {
		t := pt.t
		name := strings.ToLower(strings.TrimSpace(t.Technique))
		if name == "" || name == "none" {
			continue
		}
		if !techniqueSet[name] || t.Confidence < a.Weights.MinTechniqueConfidence {
			res.dropped++
			a.debugDrop("technique", pt.idx+1, name, t.Quote)
			continue
		}
		target := pt.idx
		sp, ok := quote.Find(ps[target], t.Quote, 0)
		for j := b.first; !ok && j < b.first+b.n; j++ {
			if j != pt.idx && byIdx[j] != nil {
				if sp, ok = quote.Find(ps[j], t.Quote, 0); ok {
					target = j
				}
			}
		}
		if !ok {
			res.dropped++
			a.debugDrop("quote", pt.idx+1, name, t.Quote)
			continue
		}
		key := [3]int{target, sp.Start16, sp.End16}
		if spans[key] {
			continue
		}
		spans[key] = true
		p := byIdx[target]
		p.Techniques = append(p.Techniques, Technique{Technique: name, Quote: sp.Quote,
			Start: sp.Start16, End: sp.End16, Confidence: math.Min(1, t.Confidence)})
	}
	for _, idx := range order {
		p := byIdx[idx]
		sort.Slice(p.Techniques, func(i, j int) bool { return p.Techniques[i].Start < p.Techniques[j].Start })
		p.Score = a.Weights.paragraphScore(*p)
		res.paragraphs = append(res.paragraphs, *p)
	}
	return res
}

func (a *Analyzer) debugDrop(reason string, p int, technique, q string) {
	if a.Log != nil {
		a.Log.Debug("dropped technique", "reason", reason, "p", p, "technique", technique, "quote", q)
	}
}

func (a *Analyzer) runBlock(ctx context.Context, in Input, b block) (blockResult, error) {
	req := llm.Request{System: systemPrompt, User: userMessage(in.Title, in.Paragraphs, b),
		MaxTokens: min(4096, 400+350*b.n)}
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		out, _, err := a.LLM.ChatJSON(ctx, req)
		if err != nil {
			lastErr = err
			if ctx.Err() != nil {
				return blockResult{}, ctx.Err()
			}
			continue
		}
		var raw rawResponse
		if err := json.Unmarshal([]byte(llm.ExtractJSON(out)), &raw); err != nil {
			lastErr = fmt.Errorf("decode model json: %w", err)
			continue
		}
		return a.validate(raw, in.Paragraphs, b), nil
	}
	return blockResult{}, lastErr
}

// ErrAllFailed means no paragraph could be analysed.
var ErrAllFailed = errors.New("temperature: all blocks failed")

// Run analyses the document. onParagraph is called (from multiple
// goroutines, serialised by the analyzer) as soon as each block finishes.
func (a *Analyzer) Run(ctx context.Context, in Input, onParagraph func(Paragraph)) (Summary, error) {
	start := a.Now()
	blocks := a.blocks(in.Paragraphs)
	conc := max(1, a.Concurrency)
	sem := make(chan struct{}, conc)
	var (
		mu      sync.Mutex
		wg      sync.WaitGroup
		results = make([]blockResult, len(blocks))
		errs    = make([]error, len(blocks))
	)
	for i, b := range blocks {
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				errs[i] = ctx.Err()
				return
			}
			defer func() { <-sem }()
			r, err := a.runBlock(ctx, in, b)
			if err != nil {
				errs[i] = err
				if a.Log != nil {
					a.Log.Warn("temperature block failed", "first", b.first+1, "n", b.n, "err", err)
				}
				return
			}
			results[i] = r
			mu.Lock()
			defer mu.Unlock()
			for _, p := range r.paragraphs {
				onParagraph(p)
			}
		}()
	}
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return Summary{}, err
	}

	sum := Summary{Techniques: map[string]int{}, Model: a.Model, Method: a.Weights.Method}
	var all []Paragraph
	var firstErr error
	for i, r := range results {
		if errs[i] != nil {
			if firstErr == nil {
				firstErr = errs[i]
			}
		}
		if i == 0 {
			sum.HeadlineClickbait, sum.HeadlineMatchesBody = r.clickbait, r.matches
		}
		sum.QuotesDropped += r.dropped
		all = append(all, r.paragraphs...)
	}
	if len(all) == 0 {
		if firstErr == nil {
			firstErr = errors.New("model returned no paragraphs")
		}
		return Summary{}, fmt.Errorf("%w: %w", ErrAllFailed, firstErr)
	}
	sum.ParagraphsAnalyzed = len(all)
	sum.ParagraphsFailed = len(in.Paragraphs) - len(all)

	var total, wsum float64
	var emo Emotions
	for _, p := range all {
		w := float64(len(in.Paragraphs[p.P-1]))
		total += w
		wsum += w * float64(p.Score)
		emo = emo.add(p.Emotions.scaled(w))
		for _, t := range p.Techniques {
			sum.Techniques[t.Technique]++
		}
	}
	sum.Emotions = emo.scaled(1 / total).rounded()
	if in.Title == "" {
		sum.HeadlineClickbait = 0
	}
	docScore := a.Weights.Document.Paragraphs*(wsum/total) + a.Weights.Document.HeadlineClickbait*100*sum.HeadlineClickbait
	if in.Title == "" {
		docScore = wsum / total
	}
	sum.Score = int(math.Round(math.Max(0, math.Min(100, docScore))))
	sum.LatencyMS = a.Now().Sub(start).Milliseconds()
	return sum, nil
}
