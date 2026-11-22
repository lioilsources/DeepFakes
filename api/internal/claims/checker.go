package claims

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/lioilsources/DeepFakes/api/internal/extract"
	"github.com/lioilsources/DeepFakes/api/internal/search"
)

// Fetcher downloads a page.
type Fetcher interface {
	Fetch(ctx context.Context, rawURL string) (extract.Page, error)
}

// Checker runs extraction and checking for one document at a time.
type Checker struct {
	LLM       Chatter
	Model     string
	Config    Config
	Providers []search.Provider // web/encyclopedia search, in priority order
	FactCheck search.Provider   // optional fact-check database
	Fetcher   Fetcher
	Now       func() time.Time
	Log       *slog.Logger
}

// Input is the analysed document.
type Input struct {
	Title      string
	Paragraphs []string
	Language   string
	URL        string     // excluded from evidence together with its site
	Published  *time.Time // article date; claims are judged as of this date
}

// asOf is the date claims are judged at: the article date, else the run start.
func (r *run) asOf() *time.Time {
	if r.in.Published != nil {
		return r.in.Published
	}
	return &r.start
}

// page is a downloaded evidence page, shared by all claims of one run.
type page struct {
	url        string
	title      string
	host       string
	sourceType string
	published  *time.Time
	retrieved  time.Time
	factCheck  *search.FactCheck
	passages   []string
	err        error
}

type run struct {
	c       *Checker
	in      Input
	start   time.Time
	ownSite string
	fetchSe chan struct{}

	mu    sync.Mutex
	pages map[string]*pageSlot

	searches, searchErrs, fetched, evDropped, offTopic, refRejected atomic.Int64
}

type pageSlot struct {
	once sync.Once
	p    *page
}

var errNoProviders = errors.New("no search providers configured")

// Run extracts claims and checks them. onClaim is called for every claim
// first (in document order), then onVerdict once per claim as checks
// finish. Callbacks are serialised.
func (c *Checker) Run(ctx context.Context, in Input, onClaim func(Claim), onVerdict func(Verdict)) (Summary, error) {
	start := c.Now()
	sum := Summary{ByLabel: map[string]int{}, Model: c.Model, Method: c.Config.Method, Providers: c.providerNames()}
	cls, dropped, err := c.extract(ctx, in)
	if err != nil {
		return sum, err
	}
	sum.ClaimsFound, sum.QuotesDropped = len(cls), dropped
	var cbMu sync.Mutex
	for _, cl := range cls {
		onClaim(cl)
	}
	check, skip := c.selectForCheck(cls)
	r := &run{c: c, in: in, start: start, ownSite: siteOf(hostOf(in.URL)), pages: map[string]*pageSlot{},
		fetchSe: make(chan struct{}, max(1, c.Config.Limits.FetchConcurrency))}
	emit := func(v Verdict) {
		cbMu.Lock()
		defer cbMu.Unlock()
		sum.ByLabel[v.Label]++
		onVerdict(v)
	}
	for _, cl := range cls {
		if reason, ok := skip[cl.ID]; ok {
			emit(Verdict{ClaimID: cl.ID, Label: LabelNotChecked, Reason: reason, Evidence: []Evidence{}})
		}
	}
	sem := make(chan struct{}, max(1, c.Config.Limits.ClaimConcurrency))
	var wg sync.WaitGroup
	var checkErr atomic.Pointer[error]
	for _, cl := range cls {
		if !check[cl.ID] {
			continue
		}
		sum.Checked++
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				return
			}
			defer func() { <-sem }()
			v, err := r.check(ctx, cl)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				checkErr.CompareAndSwap(nil, &err)
				if c.Log != nil {
					c.Log.Warn("claim check failed", "claim", cl.ID, "err", err)
				}
				v = Verdict{ClaimID: cl.ID, Label: LabelUnverifiable, Reason: "check_failed", Evidence: []Evidence{}}
			}
			emit(v)
		}()
	}
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return sum, err
	}
	sum.Searches, sum.SearchErrors = int(r.searches.Load()), int(r.searchErrs.Load())
	sum.PagesFetched, sum.EvidenceQuotesDropped = int(r.fetched.Load()), int(r.evDropped.Load())
	sum.EvidenceOffTopic = int(r.offTopic.Load())
	sum.RefutesRejected = int(r.refRejected.Load())
	sum.LatencyMS = c.Now().Sub(start).Milliseconds()
	if p := checkErr.Load(); p != nil && sum.Checked > 0 && sum.ByLabel[LabelUnverifiable] == sum.Checked {
		// Every check failed on infrastructure: report it, the claims stand.
		return sum, fmt.Errorf("all claim checks failed: %w", *p)
	}
	return sum, nil
}

func (c *Checker) providerNames() []string {
	var out []string
	if c.FactCheck != nil {
		out = append(out, c.FactCheck.Name())
	}
	for _, p := range c.Providers {
		out = append(out, p.Name())
	}
	return out
}

func normURL(raw string) string {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return ""
	}
	u.Fragment, u.RawFragment = "", ""
	u.Host = strings.ToLower(u.Host)
	return u.String()
}

func (r *run) search(ctx context.Context, p search.Provider, q search.Query) []search.Hit {
	r.searches.Add(1)
	hits, err := p.Search(ctx, q)
	if err != nil {
		r.searchErrs.Add(1)
		if r.c.Log != nil {
			r.c.Log.Warn("search failed", "provider", p.Name(), "err", err)
		}
		return nil
	}
	return hits
}

// candidates runs the searches for a claim and returns ordered, unique
// hits: fact-checks first, then providers interleaved by query.
func (r *run) candidates(ctx context.Context, cl Claim) []search.Hit {
	lim := r.c.Config.Limits
	qs := cl.Queries
	if lim.QueriesPerClaim > 0 && len(qs) > lim.QueriesPerClaim {
		qs = qs[:lim.QueriesPerClaim]
	}
	type job struct {
		p search.Provider
		q search.Query
	}
	var jobs []job
	if r.c.FactCheck != nil {
		jobs = append(jobs, job{r.c.FactCheck, search.Query{Text: cl.Claim, Lang: r.in.Language, Limit: lim.HitsPerQuery}})
		for _, q := range qs {
			if q.Lang == "en" && r.in.Language != "en" {
				jobs = append(jobs, job{r.c.FactCheck, search.Query{Text: q.Q, Lang: "en", Limit: lim.HitsPerQuery}})
				break
			}
		}
	}
	for _, q := range qs {
		lang := q.Lang
		if lang == "" {
			lang = r.in.Language
		}
		for _, p := range r.c.Providers {
			jobs = append(jobs, job{p, search.Query{Text: q.Q, Lang: lang, Limit: lim.HitsPerQuery}})
		}
	}
	results := make([][]search.Hit, len(jobs))
	var wg sync.WaitGroup
	for i, j := range jobs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results[i] = r.search(ctx, j.p, j.q)
		}()
	}
	wg.Wait()
	seen := map[string]bool{}
	var out []search.Hit
	add := func(h search.Hit) {
		u := normURL(h.URL)
		if u == "" || seen[u] || (r.ownSite != "" && siteOf(hostOf(u)) == r.ownSite) {
			return
		}
		seen[u] = true
		h.URL = u
		out = append(out, h)
	}
	for i, j := range jobs {
		if j.p == r.c.FactCheck {
			for _, h := range results[i] {
				add(h)
			}
		}
	}
	for rank := 0; ; rank++ {
		more := false
		for i, j := range jobs {
			if j.p == r.c.FactCheck || rank >= len(results[i]) {
				continue
			}
			more = true
			add(results[i][rank])
		}
		if !more {
			break
		}
	}
	return out
}

// fetch downloads and splits a page once per run.
func (r *run) fetch(ctx context.Context, h search.Hit) *page {
	r.mu.Lock()
	slot, ok := r.pages[h.URL]
	if !ok {
		slot = &pageSlot{}
		r.pages[h.URL] = slot
	}
	r.mu.Unlock()
	slot.once.Do(func() {
		p := &page{url: h.URL, title: h.Title, host: hostOf(h.URL), published: h.Published, factCheck: h.FactCheck}
		p.sourceType = r.c.Config.sourceType(p.host)
		if h.FactCheck != nil && p.sourceType == "unknown" {
			p.sourceType = "fact_checker" // listed in a ClaimReview database
		}
		slot.p = p
		select {
		case r.fetchSe <- struct{}{}:
		case <-ctx.Done():
			p.err = ctx.Err()
			return
		}
		defer func() { <-r.fetchSe }()
		fctx, cancel := context.WithTimeout(ctx, 15*time.Second)
		defer cancel()
		pg, err := r.c.Fetcher.Fetch(fctx, h.URL)
		p.retrieved = r.c.Now().UTC()
		if err != nil {
			p.err = err
			return
		}
		doc, err := extract.FromHTML(pg)
		if err != nil {
			p.err = err
			return
		}
		r.fetched.Add(1)
		if doc.Title != "" {
			p.title = doc.Title
		}
		// An encyclopedia page date is when the article was created, not when
		// its facts were written: a 2020 date on a page about a 2026 election
		// misled the stance step. Such pages get no date.
		if p.published == nil && p.sourceType != "encyclopedia" {
			p.published = doc.PublishedAt
		}
		p.passages = splitPassages(doc.Paragraphs, r.c.Config.Limits.PassageChars)
	})
	return slot.p
}

func (r *run) check(ctx context.Context, cl Claim) (Verdict, error) {
	lim := r.c.Config.Limits
	if len(r.c.Providers) == 0 && r.c.FactCheck == nil {
		return Verdict{}, errNoProviders
	}
	hits := r.candidates(ctx, cl)
	if len(hits) > lim.PagesPerClaim {
		hits = hits[:lim.PagesPerClaim]
	}
	if len(hits) == 0 {
		return Verdict{ClaimID: cl.ID, Label: LabelUnverifiable, Reason: "no_sources", Evidence: []Evidence{}}, nil
	}
	pages := make([]*page, len(hits))
	var wg sync.WaitGroup
	for i, h := range hits {
		wg.Add(1)
		go func() {
			defer wg.Done()
			pages[i] = r.fetch(ctx, h)
		}()
	}
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return Verdict{}, err
	}
	var pool []passage
	considered := 0
	for _, p := range pages {
		if p.err != nil || len(p.passages) == 0 {
			continue
		}
		considered++
		for _, t := range p.passages {
			pool = append(pool, passage{page: p, text: t})
		}
	}
	if considered == 0 {
		return Verdict{ClaimID: cl.ID, Label: LabelUnverifiable, Reason: "no_sources", Evidence: []Evidence{}}, nil
	}
	rank(cl, pool)
	best := pick(pool, lim.PassagesPerClaim, max(1, lim.PassagesPerPage))
	if len(best) == 0 {
		return Verdict{ClaimID: cl.ID, Label: LabelUnverifiable, Reason: "no_relevant_evidence",
			SourcesConsidered: considered, Evidence: []Evidence{}}, nil
	}
	js, expl, st, err := r.c.judge(ctx, cl, best, r.in.Language, r.asOf())
	if err != nil {
		return Verdict{}, err
	}
	r.evDropped.Add(int64(st.Dropped))
	r.offTopic.Add(int64(st.OffTopic))
	r.refRejected.Add(int64(st.RefutesRejected))
	v := r.c.Config.aggregate(cl, js, considered)
	if v.Label != LabelUnverifiable {
		v.Explanation = expl
	}
	return v, nil
}
