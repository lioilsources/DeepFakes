package claims

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/lioilsources/DeepFakes/api/config"
	"github.com/lioilsources/DeepFakes/api/internal/extract"
	"github.com/lioilsources/DeepFakes/api/internal/llm"
	"github.com/lioilsources/DeepFakes/api/internal/search"
)

var fixedNow = time.Date(2026, 11, 20, 10, 0, 0, 0, time.UTC)

func cfg(t *testing.T) Config {
	t.Helper()
	c, err := ParseConfig(config.ClaimsJSON)
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestPromptsInSync(t *testing.T) {
	for _, f := range []struct{ name, embedded string }{{"claims.md", extractPrompt}, {"stance.md", stancePrompt}} {
		b, err := os.ReadFile("../../../llm_prompts/" + f.name)
		if err != nil {
			t.Fatal(err)
		}
		if string(b) != f.embedded {
			t.Errorf("internal/claims/%s differs from llm_prompts/%s; copy it", f.name, f.name)
		}
	}
}

func TestParseConfigRejects(t *testing.T) {
	bad := strings.Replace(string(config.ClaimsJSON), `"demagog.cz": "fact_checker"`, `"demagog.cz": "nonsense"`, 1)
	if _, err := ParseConfig([]byte(bad)); err == nil {
		t.Fatal("want error for unknown source type")
	}
}

// fakeLLM answers by prompt: extraction or stance.
type fakeLLM struct {
	mu       sync.Mutex
	extract  string
	stance   func(user string) string
	failAll  bool
	stanceNo int
}

func (f *fakeLLM) ChatJSON(_ context.Context, r llm.Request) (string, llm.Usage, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.failAll {
		return "", llm.Usage{}, llm.ErrUnavailable
	}
	if r.System == extractPrompt {
		return f.extract, llm.Usage{}, nil
	}
	f.stanceNo++
	return f.stance(r.User), llm.Usage{}, nil
}

type fakeProvider struct {
	name string
	hits map[string][]search.Hit // by query text
	err  error
}

func (p *fakeProvider) Name() string { return p.name }
func (p *fakeProvider) Search(_ context.Context, q search.Query) ([]search.Hit, error) {
	if p.err != nil {
		return nil, p.err
	}
	return p.hits[q.Text], nil
}

type fakeFetcher map[string]string // url → html body

func (f fakeFetcher) Fetch(_ context.Context, raw string) (extract.Page, error) {
	body, ok := f[raw]
	if !ok {
		return extract.Page{}, fmt.Errorf("%w: HTTP 404", extract.ErrFetch)
	}
	u, _ := url.Parse(raw)
	return extract.Page{URL: u, HTML: []byte(body), ContentType: "text/html; charset=utf-8"}, nil
}

func article(title string, ps ...string) string {
	var sb strings.Builder
	sb.WriteString("<html><head><title>" + title + "</title></head><body><article><h1>" + title + "</h1>")
	for _, p := range ps {
		sb.WriteString("<p>" + p + "</p>")
	}
	sb.WriteString("</article></body></html>")
	return sb.String()
}

var doc = []string{
	"Vláda ve středu schválila rozpočet se schodkem 230 miliard korun, oznámil ministr financí.",
	"Podle opozice je to katastrofa, která zemi zničí.",
	"Příští rok inflace klesne pod dvě procenta, odhaduje centrální banka.",
}

const extractJSON = `{"language":"cs","claims":[
 {"p":1,"quote":"Vláda ve středu schválila rozpočet se schodkem 230 miliard korun","claim":"Vláda schválila rozpočet se schodkem 230 miliard korun.","kind":"fact","checkworthy":0.9,"entities":["vláda"],
  "search_queries":[{"q":"rozpočet schodek 230 miliard","lang":"cs"},{"q":"Czech budget deficit 230 billion","lang":"en"}]},
 {"p":2,"quote":"je to katastrofa, která zemi zničí","claim":"Rozpočet zemi zničí.","kind":"opinion","checkworthy":0.2},
 {"p":3,"quote":"inflace klesne pod dvě procenta","claim":"Inflace příští rok klesne pod 2 %.","kind":"prediction","checkworthy":0.6},
 {"p":1,"quote":"tohle v textu není","claim":"Vymyšlené tvrzení.","kind":"fact","checkworthy":0.9}
]}`

func newChecker(t *testing.T, l *fakeLLM, prov search.Provider, fc search.Provider, f fakeFetcher) *Checker {
	t.Helper()
	c := &Checker{LLM: l, Model: "m", Config: cfg(t), Fetcher: f, Now: func() time.Time { return fixedNow }}
	if prov != nil {
		c.Providers = []search.Provider{prov}
	}
	if fc != nil {
		c.FactCheck = fc
	}
	return c
}

func collect(t *testing.T, c *Checker, in Input) ([]Claim, map[string]Verdict, Summary, error) {
	t.Helper()
	var cls []Claim
	vs := map[string]Verdict{}
	sum, err := c.Run(context.Background(), in, func(cl Claim) { cls = append(cls, cl) }, func(v Verdict) {
		if _, dup := vs[v.ClaimID]; dup {
			t.Errorf("verdict for %s twice", v.ClaimID)
		}
		vs[v.ClaimID] = v
	})
	return cls, vs, sum, err
}

func TestRunSupportedAndQuoteGates(t *testing.T) {
	pages := fakeFetcher{
		"https://irozhlas.cz/a": article("Rozpočet schválen",
			"Vláda ve středu schválila státní rozpočet na příští rok se schodkem 230 miliard korun.",
			"Další text o počasí, který s rozpočtem nesouvisí vůbec nijak a je tu jen jako výplň."),
		"https://www.mfcr.gov.cz/x": article("Tisková zpráva MF",
			"Ministerstvo financí: návrh rozpočtu počítá se schodkem 230 miliard korun a vláda jej schválila."),
		"https://example.com/own": article("Vlastní článek", "Vláda schválila rozpočet se schodkem 230 miliard korun dnes."),
	}
	prov := &fakeProvider{name: "web", hits: map[string][]search.Hit{
		"rozpočet schodek 230 miliard":     {{URL: "https://irozhlas.cz/a#x"}, {URL: "https://example.com/own"}, {URL: "https://dead.cz/404"}},
		"Czech budget deficit 230 billion": {{URL: "https://www.mfcr.gov.cz/x"}, {URL: "https://irozhlas.cz/a"}},
	}}
	l := &fakeLLM{extract: extractJSON, stance: func(user string) string {
		// Passage ids depend on ranking; quote from the text to stay valid,
		// plus one invented quote that must be dropped.
		var js []string
		for i := 1; i <= 8; i++ {
			if !strings.Contains(user, fmt.Sprintf(`<passage id="%d"`, i)) {
				break
			}
			js = append(js, fmt.Sprintf(`{"id":%d,"stance":"supports","quote":"schodkem 230 miliard korun","confidence":0.9}`, i))
		}
		js = append(js, `{"id":1,"stance":"refutes","quote":"Rozpočet byl zamítnut.","confidence":0.9}`)
		return `{"judgements":[` + strings.Join(js, ",") + `],"explanation":"Zdroje [1] a [2] uvádějí schodek 230 miliard."}`
	}}
	c := newChecker(t, l, prov, nil, pages)
	cls, vs, sum, err := collect(t, c, Input{Title: "T", Paragraphs: doc, Language: "cs", URL: "https://example.com/clanek"})
	if err != nil {
		t.Fatal(err)
	}
	if len(cls) != 3 || sum.QuotesDropped != 1 {
		t.Fatalf("claims=%d dropped=%d", len(cls), sum.QuotesDropped)
	}
	for _, cl := range cls {
		if got := []rune(doc[cl.P-1]); string(got) == "" || !strings.Contains(doc[cl.P-1], cl.Quote) {
			t.Errorf("quote not in paragraph: %+v", cl)
		}
	}
	if v := vs["c2"]; v.Label != LabelNotChecked || v.Reason != KindOpinion {
		t.Errorf("opinion: %+v", v)
	}
	if v := vs["c3"]; v.Label != LabelNotChecked || v.Reason != KindPrediction {
		t.Errorf("prediction: %+v", v)
	}
	v := vs["c1"]
	if v.Label != LabelSupported || v.IndependentSources != 2 || v.Explanation == "" {
		t.Fatalf("verdict: %+v", v)
	}
	for _, e := range v.Evidence {
		if strings.Contains(e.URL, "example.com") || strings.Contains(e.URL, "#") {
			t.Errorf("own site or fragment in evidence: %s", e.URL)
		}
		if e.Stance != StanceSupports || e.Quote != "schodkem 230 miliard korun" {
			t.Errorf("evidence: %+v", e)
		}
	}
	if sum.EvidenceQuotesDropped != 1 || sum.Checked != 1 || sum.ByLabel[LabelSupported] != 1 || sum.ByLabel[LabelNotChecked] != 2 {
		t.Errorf("summary: %+v", sum)
	}
	types := map[string]string{}
	for _, e := range v.Evidence {
		types[e.Site] = e.SourceType
	}
	if types["mfcr.gov.cz"] != "primary" || types["irozhlas.cz"] != "news" {
		t.Errorf("source types: %v", types)
	}
}

func TestRunUnverifiableWithoutSources(t *testing.T) {
	l := &fakeLLM{extract: extractJSON, stance: func(string) string { return `{}` }}
	c := newChecker(t, l, &fakeProvider{name: "web"}, nil, fakeFetcher{})
	_, vs, _, err := collect(t, c, Input{Paragraphs: doc, Language: "cs"})
	if err != nil {
		t.Fatal(err)
	}
	if v := vs["c1"]; v.Label != LabelUnverifiable || v.Reason != "no_sources" || v.Explanation != "" {
		t.Fatalf("%+v", v)
	}
	if l.stanceNo != 0 {
		t.Error("stance model called without evidence")
	}
}

func TestRunIrrelevantEvidenceIsUnverifiable(t *testing.T) {
	pages := fakeFetcher{"https://irozhlas.cz/a": article("A", "Vláda ve středu schválila rozpočet se schodkem 230 miliard korun.")}
	prov := &fakeProvider{name: "web", hits: map[string][]search.Hit{"rozpočet schodek 230 miliard": {{URL: "https://irozhlas.cz/a"}}}}
	l := &fakeLLM{extract: extractJSON, stance: func(string) string {
		return `{"judgements":[{"id":1,"stance":"irrelevant"}],"explanation":"Model si něco vymyslel."}`
	}}
	_, vs, _, err := collect(t, newChecker(t, l, prov, nil, pages), Input{Paragraphs: doc, Language: "cs"})
	if err != nil {
		t.Fatal(err)
	}
	if v := vs["c1"]; v.Label != LabelUnverifiable || v.Explanation != "" || len(v.Evidence) != 0 {
		t.Fatalf("%+v", v)
	}
}

func TestFactCheckFirstAndTyped(t *testing.T) {
	pages := fakeFetcher{"https://demagog.cz/vyrok/1": article("Výrok", "Výrok je nepravdivý: schodek rozpočtu nebyl 230 miliard korun, ale 280 miliard korun.")}
	fc := &fakeProvider{name: "factcheck", hits: map[string][]search.Hit{
		"Vláda schválila rozpočet se schodkem 230 miliard korun.": {{URL: "https://demagog.cz/vyrok/1", FactCheck: &search.FactCheck{Publisher: "Demagog.cz", Rating: "Nepravda"}}},
	}}
	l := &fakeLLM{extract: extractJSON, stance: func(string) string {
		return `{"judgements":[{"id":1,"stance":"refutes","quote":"schodek rozpočtu nebyl 230 miliard korun, ale 280 miliard korun","confidence":1}],"explanation":"[1] uvádí 280 miliard."}`
	}}
	_, vs, sum, err := collect(t, newChecker(t, l, &fakeProvider{name: "web"}, fc, pages), Input{Paragraphs: doc, Language: "cs"})
	if err != nil {
		t.Fatal(err)
	}
	v := vs["c1"]
	if v.Label != LabelRefuted || len(v.Evidence) != 1 || v.Evidence[0].SourceType != "fact_checker" || v.Evidence[0].FactCheck.Rating != "Nepravda" {
		t.Fatalf("%+v", v)
	}
	if sum.Providers[0] != "factcheck" {
		t.Errorf("providers %v", sum.Providers)
	}
}

func TestRunExtractionFailure(t *testing.T) {
	c := newChecker(t, &fakeLLM{failAll: true}, &fakeProvider{name: "web"}, nil, fakeFetcher{})
	if _, _, _, err := collect(t, c, Input{Paragraphs: doc, Language: "cs"}); !errors.Is(err, llm.ErrUnavailable) {
		t.Fatalf("want llm unavailable, got %v", err)
	}
}

func judgedOf(c Config, host, text, stance string, conf float64) judged {
	p := &page{url: "https://" + host + "/x", host: host, sourceType: c.sourceType(host)}
	return judged{p: passage{page: p, text: text}, stance: stance, quote: text, confidence: conf}
}

func TestAggregate(t *testing.T) {
	c := cfg(t)
	cl := Claim{ID: "c1"}
	cases := []struct {
		name string
		js   []judged
		want string
		srcs int
	}{
		{"nothing", nil, LabelUnverifiable, 0},
		{"one news", []judged{judgedOf(c, "irozhlas.cz", "a b c d", StanceSupports, 0.9)}, LabelUnverifiable, 1},
		{"news+primary", []judged{
			judgedOf(c, "irozhlas.cz", "alpha beta gamma delta", StanceSupports, 0.9),
			judgedOf(c, "czso.cz", "one two three four", StanceSupports, 0.9)}, LabelSupported, 2},
		{"agency copies are one source", []judged{
			judgedOf(c, "novinky.cz", "vláda dnes schválila rozpočet se schodkem 230 miliard korun", StanceSupports, 1),
			judgedOf(c, "idnes.cz", "vláda dnes schválila rozpočet se schodkem 230 miliard korun", StanceSupports, 1),
			judgedOf(c, "aktualne.cz", "vláda dnes schválila rozpočet se schodkem 230 miliard korun", StanceSupports, 1)}, LabelMostlySupported, 1},
		{"same domain is one source", []judged{
			judgedOf(c, "a.irozhlas.cz", "x y z w", StanceSupports, 1),
			judgedOf(c, "b.irozhlas.cz", "p q r s", StanceSupports, 1)}, LabelMostlySupported, 1},
		{"fact-checker refutes", []judged{judgedOf(c, "demagog.cz", "nepravda", StanceRefutes, 0.9)}, LabelRefuted, 1},
		{"one news refutation is weak", []judged{judgedOf(c, "irozhlas.cz", "jinak", StanceRefutes, 0.95)}, LabelUnverifiable, 1},
		{"both sides", []judged{
			judgedOf(c, "czso.cz", "one two three four", StanceSupports, 0.9),
			judgedOf(c, "demagog.cz", "five six seven eight", StanceRefutes, 0.9)}, LabelDisputed, 2},
	}
	for _, tc := range cases {
		v := c.aggregate(cl, tc.js, len(tc.js))
		if v.Label != tc.want || v.IndependentSources != tc.srcs {
			t.Errorf("%s: label=%s sources=%d (s=%.2f r=%.2f)", tc.name, v.Label, v.IndependentSources, v.Support, v.Refute)
		}
		if v.Label == LabelUnverifiable && v.Confidence != 0 {
			t.Errorf("%s: unverifiable with confidence %.2f", tc.name, v.Confidence)
		}
	}
}

func TestRankPrefersNumbersAndNames(t *testing.T) {
	cl := Claim{Claim: "Schodek rozpočtu je 230 miliard korun", Entities: []string{"Stanjura"}}
	pg := &page{}
	ps := []passage{
		{page: pg, text: "Počasí bude zítra slunečné a teplé."},
		{page: pg, text: "Ministr Stanjura uvedl schodek 230 miliard."},
		{page: pg, text: "Rozpočet se projednává."},
	}
	rank(cl, ps)
	best := pick(ps, 2, 5)
	if len(best) != 2 || !strings.Contains(best[0].text, "Stanjura") {
		t.Fatalf("%+v", best)
	}
}

func TestSourceTypeAndSite(t *testing.T) {
	c := cfg(t)
	for host, want := range map[string]string{"mfcr.gov.cz": "primary", "cs.wikipedia.org": "encyclopedia", "ec.europa.eu": "primary", "blog.example.org": "unknown"} {
		if got := c.sourceType(host); got != want {
			t.Errorf("%s: %s want %s", host, got, want)
		}
	}
	if siteOf("news.bbc.co.uk") != "bbc.co.uk" || siteOf("a.b.irozhlas.cz") != "irozhlas.cz" {
		t.Error("siteOf")
	}
}

func TestAnchoredRejectsOffTopicQuotes(t *testing.T) {
	cl := Claim{Claim: "Pracovník z Indie zarobí v Nitre viac", Entities: []string{"Nitra", "Tata Motors"}}
	as := anchors(cl)
	if anchored("Jednotné roľnícke družstvo Pata dosiahlo obrovský rast.", as) {
		t.Error("off-topic quote accepted")
	}
	if !anchored("JLR opened a new plant in Nitra, Slovakia.", as) {
		t.Error("cross-lingual quote with the same name rejected")
	}
}
