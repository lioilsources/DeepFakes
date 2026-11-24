package httpapi

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/time/rate"

	"github.com/lioilsources/DeepFakes/api/internal/claims"
	"github.com/lioilsources/DeepFakes/api/internal/extract"
	"github.com/lioilsources/DeepFakes/api/internal/llm"
	"github.com/lioilsources/DeepFakes/api/internal/service"
	"github.com/lioilsources/DeepFakes/api/internal/store"
	"github.com/lioilsources/DeepFakes/api/internal/temperature"
)

type fakeFetcher struct{ html string }

func (f fakeFetcher) Fetch(_ context.Context, raw string) (extract.Page, error) {
	if strings.Contains(raw, "missing") {
		return extract.Page{}, fmt.Errorf("%w: HTTP 404", extract.ErrFetch)
	}
	u, _ := url.Parse(raw)
	return extract.Page{URL: u, HTML: []byte(f.html), ContentType: "text/html; charset=utf-8"}, nil
}

type fakeAnalyzer struct {
	gate chan struct{} // closed → finish
	fail error
}

func (a *fakeAnalyzer) Run(_ context.Context, in temperature.Input, on func(temperature.Paragraph)) (temperature.Summary, error) {
	if a.fail != nil {
		return temperature.Summary{}, a.fail
	}
	on(temperature.Paragraph{P: 1, Score: 70, Techniques: []temperature.Technique{{Technique: "fear_appeal", Quote: "x", Start: 0, End: 1, Confidence: 0.9}}})
	if a.gate != nil {
		<-a.gate
	}
	for i := 2; i <= len(in.Paragraphs); i++ {
		on(temperature.Paragraph{P: i, Score: 10, Techniques: []temperature.Technique{}})
	}
	return temperature.Summary{Score: 40, Method: "llm-v1", ParagraphsAnalyzed: len(in.Paragraphs)}, nil
}

const page = `<html lang="en"><head><title>Bridge opened</title></head><body><article>
<p>The town opened a new bridge on Monday after two years of construction work.</p>
<p>Critics say the budget grew by a quarter during the works and the town took a loan.</p>
</article></body></html>`

type env struct {
	srv *httptest.Server
	st  *store.Memory
	now *time.Time
}

func setup(t *testing.T, an service.Analyzer) env {
	t.Helper()
	return setupWith(t, an, nil)
}

func setupWith(t *testing.T, an service.Analyzer, cc service.ClaimChecker) env {
	t.Helper()
	now := time.Date(2026, 11, 12, 10, 0, 0, 0, time.UTC)
	var mu sync.Mutex
	n := 0
	st := store.NewMemory()
	svc := &service.Service{Store: st, Fetcher: fakeFetcher{page}, Analyzer: an, Claims: cc,
		Now:      func() time.Time { return now },
		NewID:    func() string { mu.Lock(); defer mu.Unlock(); n++; return fmt.Sprintf("A%03d", n) },
		CacheTTL: time.Hour, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	svc.Start(ctx, 2, 10)
	h := &Server{Svc: svc, Log: svc.Log, SubmitRate: rate.Every(time.Hour), SubmitBurst: 3}
	srv := httptest.NewServer(h.Handler())
	t.Cleanup(srv.Close)
	return env{srv, st, &now}
}

func post(t *testing.T, e env, body, device string) (*http.Response, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest("POST", e.srv.URL+"/v1/analyses", strings.NewReader(body))
	if device != "" {
		req.Header.Set("X-Device-Id", device)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var m map[string]any
	json.NewDecoder(resp.Body).Decode(&m)
	return resp, m
}

type sse struct {
	name string
	data string
}

func readEvents(t *testing.T, e env, id string) []sse {
	t.Helper()
	resp, err := http.Get(e.srv.URL + "/v1/analyses/" + id + "/events")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		t.Fatalf("content type %q", ct)
	}
	var out []sse
	var cur sse
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "event: "):
			cur.name = line[7:]
		case strings.HasPrefix(line, "data: "):
			cur.data = line[6:]
		case line == "" && cur.name != "":
			out = append(out, cur)
			cur = sse{}
		}
	}
	return out
}

func names(ev []sse) string {
	var n []string
	for _, e := range ev {
		n = append(n, e.name)
	}
	return strings.Join(n, ",")
}

func TestURLFlowAndCache(t *testing.T) {
	gate := make(chan struct{})
	e := setup(t, &fakeAnalyzer{gate: gate})
	resp, m := post(t, e, `{"url":"https://News.example/a?utm_source=x#top"}`, "dev1")
	if resp.StatusCode != http.StatusAccepted {
		t.Fatalf("status %d %v", resp.StatusCode, m)
	}
	id := m["id"].(string)

	done := make(chan []sse)
	go func() { done <- readEvents(t, e, id) }() // live subscriber
	time.Sleep(50 * time.Millisecond)
	close(gate)
	live := <-done
	if got := names(live); got != "status,document,status,paragraph,paragraph,summary,done" {
		t.Fatalf("live events %s", got)
	}
	var doc store.Document
	json.Unmarshal([]byte(live[1].data), &doc)
	if doc.Title != "Bridge opened" || len(doc.Paragraphs) != 2 || doc.Paragraphs[0].P != 1 || doc.Language != "en" {
		t.Fatalf("document %+v", doc)
	}

	// Replay from store after finish.
	if got := names(readEvents(t, e, id)); got != "document,paragraph,paragraph,summary,done" {
		t.Fatalf("replay %s", got)
	}

	// Same URL (different tracking params) → cached.
	resp, m = post(t, e, `{"url":"https://news.example/a?utm_medium=y"}`, "dev1")
	if resp.StatusCode != http.StatusOK || m["id"] != id || m["status"] != "done" {
		t.Fatalf("cache: %d %v", resp.StatusCode, m)
	}

	// GET result.
	r, err := http.Get(e.srv.URL + "/v1/analyses/" + id)
	if err != nil {
		t.Fatal(err)
	}
	var res store.Result
	json.NewDecoder(r.Body).Decode(&res)
	r.Body.Close()
	if res.Status != "done" || res.Summary == nil || res.Summary.Score != 40 || len(res.Paragraphs) != 2 {
		t.Fatalf("result %+v", res)
	}

	// Purge after TTL keeps metrics, drops text and quotes.
	if n, _ := e.st.Purge(context.Background(), e.now.Add(time.Hour), *e.now); n != 1 {
		t.Fatalf("purged %d", n)
	}
	res, _ = e.st.Get(context.Background(), id)
	if !res.Document.Purged || len(res.Document.Paragraphs) != 0 || res.Paragraphs[0].Techniques[0].Quote != "" ||
		res.Paragraphs[0].Techniques[0].Technique != "fear_appeal" {
		t.Fatalf("purge result %+v", res)
	}
}

func TestFailures(t *testing.T) {
	e := setup(t, &fakeAnalyzer{fail: fmt.Errorf("%w: %w", temperature.ErrAllFailed, llm.ErrUnavailable)})
	_, m := post(t, e, `{"url":"https://news.example/missing"}`, "d")
	ev := readEvents(t, e, m["id"].(string))
	// The live "status" event may be gone if the job finished before we subscribed.
	if !strings.HasSuffix(names(ev), "error") || !strings.Contains(ev[len(ev)-1].data, "fetch_failed") {
		t.Fatalf("fetch failure: %v", ev)
	}
	_, m = post(t, e, `{"text":"Some pasted text that is long enough to be a paragraph."}`, "d")
	ev = readEvents(t, e, m["id"].(string))
	if !strings.HasSuffix(names(ev), "error") || !strings.Contains(ev[len(ev)-1].data, "llm_unavailable") {
		t.Fatalf("llm failure: %v", ev)
	}
}

func TestValidationAndRateLimit(t *testing.T) {
	e := setup(t, &fakeAnalyzer{})
	cases := []struct {
		body, device string
		status       int
	}{
		{`{"url":"https://x.example/a"}`, "", 400},
		{`{}`, "v1", 400},
		{`{"url":"ftp://x/a"}`, "v2", 400},
		{`{"url":"https://x.example","text":"t"}`, "v3", 400},
		{`not json`, "v4", 400},
		{`{"text":"` + strings.Repeat("a", service.MaxTextBytes+1) + `"}`, "big", 413},
	}
	for _, c := range cases {
		if resp, m := post(t, e, c.body, c.device); resp.StatusCode != c.status {
			t.Errorf("%.40s → %d %v, want %d", c.body, resp.StatusCode, m, c.status)
		}
	}
	for i := range 3 {
		if resp, _ := post(t, e, fmt.Sprintf(`{"text":"text number %d is here"}`, i), "rl"); resp.StatusCode != 202 {
			t.Fatalf("burst %d: %d", i, resp.StatusCode)
		}
	}
	resp, _ := post(t, e, `{"text":"one more"}`, "rl")
	if resp.StatusCode != 429 || resp.Header.Get("Retry-After") == "" {
		t.Fatalf("rate limit: %d", resp.StatusCode)
	}
	if r, _ := http.Get(e.srv.URL + "/v1/analyses/nope/events"); r.StatusCode != 404 {
		t.Fatalf("unknown id: %d", r.StatusCode)
	}
}

type fakeClaims struct{ fail error }

func (f fakeClaims) Run(_ context.Context, in claims.Input, onClaim func(claims.Claim), onVerdict func(claims.Verdict)) (claims.Summary, error) {
	sum := claims.Summary{Method: "claims-v1", ByLabel: map[string]int{}}
	if f.fail != nil {
		return sum, f.fail
	}
	onClaim(claims.Claim{ID: "c1", P: 1, Quote: "opened a new bridge", Claim: "The town opened a bridge.", Kind: claims.KindFact})
	onClaim(claims.Claim{ID: "c2", P: 2, Quote: "the town took a loan", Claim: "The town took a loan.", Kind: claims.KindFact})
	onVerdict(claims.Verdict{ClaimID: "c2", Label: claims.LabelUnverifiable, Reason: "no_sources", Evidence: []claims.Evidence{}})
	onVerdict(claims.Verdict{ClaimID: "c1", Label: claims.LabelSupported, Confidence: 0.7,
		Evidence: []claims.Evidence{{URL: "https://gov.example/x", Stance: claims.StanceSupports, Quote: "bridge opened"}}})
	if in.Language != "en" || in.URL == "" {
		return sum, fmt.Errorf("bad input %+v", in)
	}
	sum.ClaimsFound, sum.Checked = 2, 2
	return sum, nil
}

func TestClaimsFlow(t *testing.T) {
	e := setupWith(t, &fakeAnalyzer{}, fakeClaims{})
	_, m := post(t, e, `{"url":"https://news.example/c"}`, "d")
	id := m["id"].(string)
	ev := readEvents(t, e, id)
	n := names(ev)
	for _, want := range []string{"claim", "verdict", "claims_summary"} {
		if !strings.Contains(n, want) {
			t.Fatalf("missing %s in %s", want, n)
		}
	}
	if !strings.HasSuffix(n, "summary,claims_summary,done") {
		t.Fatalf("live %s", n)
	}
	if got := names(readEvents(t, e, id)); got != "document,paragraph,paragraph,claim,claim,verdict,verdict,summary,claims_summary,done" {
		t.Fatalf("replay %s", got)
	}
	r, _ := http.Get(e.srv.URL + "/v1/analyses/" + id)
	var raw map[string]any
	json.NewDecoder(r.Body).Decode(&raw)
	r.Body.Close()
	cs := raw["claims"].([]any)
	c1 := cs[0].(map[string]any)
	if len(cs) != 2 || c1["id"] != "c1" || c1["claim"] != "The town opened a bridge." || c1["verdict"].(map[string]any)["label"] != "supported" {
		t.Fatalf("claims json %v", cs)
	}
	if raw["claims_summary"].(map[string]any)["claims_found"].(float64) != 2 {
		t.Fatalf("claims summary %v", raw["claims_summary"])
	}
}

func TestClaimsFailureDoesNotFailAnalysis(t *testing.T) {
	e := setupWith(t, &fakeAnalyzer{}, fakeClaims{fail: fmt.Errorf("extract: %w", llm.ErrUnavailable)})
	_, m := post(t, e, `{"url":"https://news.example/d"}`, "d")
	ev := readEvents(t, e, m["id"].(string))
	if !strings.HasSuffix(names(ev), "claims_summary,done") || !strings.Contains(ev[len(ev)-2].data, `"error":"llm_unavailable"`) {
		t.Fatalf("%v", ev)
	}
}
