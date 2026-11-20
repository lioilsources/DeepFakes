// Command stance-eval measures the claim stance step on CsFEVER-style NLI
// data (jsonl with claim, evidence, label 0=SUPPORTS 1=REFUTES 2=NEI).
// It uses the production prompt and gates; results go to run/bench.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/lioilsources/DeepFakes/api/config"
	"github.com/lioilsources/DeepFakes/api/internal/claims"
	"github.com/lioilsources/DeepFakes/api/internal/llm"
)

type item struct {
	Claim    string `json:"claim"`
	Evidence string `json:"evidence"`
	ID       int    `json:"id"`
	Label    int    `json:"label"`
}

var gold = []string{"supports", "refutes", "irrelevant"}

type row struct {
	ID        int                   `json:"id"`
	Gold      string                `json:"gold"`
	Pred      string                `json:"pred"`
	Conf      float64               `json:"confidence"`
	Dropped   int                   `json:"quotes_dropped"`
	OffTopic  int                   `json:"off_topic"`
	Error     string                `json:"error,omitempty"`
	LatencyMS int64                 `json:"latency_ms"`
	Results   []claims.StanceResult `json:"results,omitempty"`
}

func main() {
	in := flag.String("in", "run/data/csfever/test.jsonl", "input jsonl")
	out := flag.String("out", "run/bench", "output dir")
	perLabel := flag.Int("per-label", 100, "items sampled per gold label")
	conc := flag.Int("concurrency", 8, "parallel requests")
	maxChars := flag.Int("max-chars", 2500, "evidence truncation")
	seed := flag.Uint64("seed", 1120, "sampling seed")
	flag.Parse()
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	if err := run(log, *in, *out, *perLabel, *conc, *maxChars, *seed); err != nil {
		log.Error("stance-eval", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger, in, out string, perLabel, conc, maxChars int, seed uint64) error {
	f, err := os.Open(in)
	if err != nil {
		return fmt.Errorf("open input: %w", err)
	}
	defer f.Close()
	byLabel := map[int][]item{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 16<<20)
	for sc.Scan() {
		var it item
		if err := json.Unmarshal(sc.Bytes(), &it); err != nil {
			return fmt.Errorf("decode: %w", err)
		}
		if it.Label >= 0 && it.Label < 3 {
			byLabel[it.Label] = append(byLabel[it.Label], it)
		}
	}
	if err := sc.Err(); err != nil {
		return fmt.Errorf("read: %w", err)
	}
	rng := rand.New(rand.NewPCG(seed, 0))
	var items []item
	for l := 0; l < 3; l++ {
		xs := byLabel[l]
		rng.Shuffle(len(xs), func(i, j int) { xs[i], xs[j] = xs[j], xs[i] })
		items = append(items, xs[:min(perLabel, len(xs))]...)
	}
	cfg, err := claims.ParseConfig(config.ClaimsJSON)
	if err != nil {
		return err
	}
	model := os.Getenv("LLM_MODEL")
	client := &llm.Client{BaseURL: os.Getenv("LLM_BASE_URL"), APIKey: os.Getenv("LLM_API_KEY"), Model: model,
		HTTP: &http.Client{Timeout: 3 * time.Minute}}
	ch := &claims.Checker{LLM: client, Model: model, Config: cfg, Now: time.Now, Log: log}

	rows := make([]row, len(items))
	sem := make(chan struct{}, max(1, conc))
	var wg sync.WaitGroup
	ctx := context.Background()
	start := time.Now()
	for i, it := range items {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			ev := []rune(it.Evidence)
			if len(ev) > maxChars {
				ev = ev[:maxChars]
			}
			t0 := time.Now()
			res, dropped, off, err := ch.JudgeTexts(ctx, it.Claim, "cs", []string{string(ev)})
			r := row{ID: it.ID, Gold: gold[it.Label], Pred: "irrelevant", Dropped: dropped, OffTopic: off,
				LatencyMS: time.Since(t0).Milliseconds(), Results: res}
			if err != nil {
				r.Error, r.Pred = err.Error(), "error"
			} else if len(res) > 0 {
				r.Pred, r.Conf = res[0].Stance, res[0].Confidence
			}
			rows[i] = r
		}()
	}
	wg.Wait()

	if err := os.MkdirAll(out, 0o755); err != nil {
		return fmt.Errorf("mkdir: %w", err)
	}
	jf, err := os.Create(filepath.Join(out, "m2_stance.jsonl"))
	if err != nil {
		return fmt.Errorf("create: %w", err)
	}
	enc := json.NewEncoder(jf)
	for _, r := range rows {
		enc.Encode(r) //nolint:errcheck
	}
	jf.Close()

	conf := map[string]map[string]int{}
	correct, errs, dropped, off := 0, 0, 0, 0
	for _, r := range rows {
		if conf[r.Gold] == nil {
			conf[r.Gold] = map[string]int{}
		}
		conf[r.Gold][r.Pred]++
		if r.Gold == r.Pred {
			correct++
		}
		if r.Error != "" {
			errs++
		}
		dropped += r.Dropped
		off += r.OffTopic
	}
	per := map[string]map[string]float64{}
	macro := 0.0
	for _, g := range gold {
		tp := conf[g][g]
		fp, fn := 0, 0
		for _, o := range gold {
			if o != g {
				fp += conf[o][g]
			}
		}
		for p, n := range conf[g] {
			if p != g {
				fn += n
			}
		}
		prec := ratio(tp, tp+fp)
		rec := ratio(tp, tp+fn)
		f1 := 0.0
		if prec+rec > 0 {
			f1 = 2 * prec * rec / (prec + rec)
		}
		per[g] = map[string]float64{"precision": round(prec), "recall": round(rec), "f1": round(f1)}
		macro += f1 / 3
	}
	sum := map[string]any{"model": model, "n": len(rows), "accuracy": round(ratio(correct, len(rows))),
		"macro_f1": round(macro), "per_label": per, "confusion": conf, "errors": errs,
		"quotes_dropped": dropped, "off_topic": off, "wall_s": int(time.Since(start).Seconds())}
	b, _ := json.MarshalIndent(sum, "", " ")
	if err := os.WriteFile(filepath.Join(out, "m2_stance_summary.json"), b, 0o644); err != nil {
		return fmt.Errorf("write summary: %w", err)
	}
	fmt.Fprintln(os.Stderr, string(b))
	fmt.Printf("{\"items\":{\"ok\":%d,\"failed\":%d}}\n", len(rows)-errs, errs)
	return nil
}

func ratio(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return float64(a) / float64(b)
}

func round(f float64) float64 { return float64(int(f*1000+0.5)) / 1000 }
