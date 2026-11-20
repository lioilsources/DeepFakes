package claims

import (
	"math"
	"sort"
)

// aggregate turns validated stances into a verdict. Sources are grouped
// into independent clusters: one cluster per registrable domain, and
// clusters whose passages are near-duplicates (agency copy) merge. Each
// cluster contributes its strongest support and refutation, weighted by
// source type and model confidence.
func (c *Config) aggregate(cl Claim, js []judged, considered int) Verdict {
	v := Verdict{ClaimID: cl.ID, SourcesConsidered: considered, Evidence: []Evidence{}}
	if len(js) == 0 {
		v.Label, v.Reason = LabelUnverifiable, "no_relevant_evidence"
		return v
	}
	// Union-find over evidence items.
	parent := make([]int, len(js))
	for i := range parent {
		parent[i] = i
	}
	var find func(int) int
	find = func(i int) int {
		if parent[i] != i {
			parent[i] = find(parent[i])
		}
		return parent[i]
	}
	union := func(a, b int) { parent[find(a)] = find(b) }
	sh := make([]map[string]bool, len(js))
	for i, j := range js {
		sh[i] = shingles(j.p.text)
	}
	for i := range js {
		for k := i + 1; k < len(js); k++ {
			if siteOf(js[i].p.page.host) == siteOf(js[k].p.page.host) ||
				jaccard(sh[i], sh[k]) >= c.Verdict.NearDuplicateJaccard {
				union(i, k)
			}
		}
	}
	type agg struct{ sup, ref float64 }
	clusters := map[int]*agg{}
	ids := map[int]int{}
	for i, j := range js {
		root := find(i)
		if _, ok := ids[root]; !ok {
			ids[root] = len(ids) + 1
			clusters[root] = &agg{}
		}
		w := c.SourceWeights[j.p.page.sourceType] * j.confidence
		a := clusters[root]
		if j.stance == StanceSupports {
			a.sup = math.Max(a.sup, w)
		} else {
			a.ref = math.Max(a.ref, w)
		}
		pg := j.p.page
		e := Evidence{URL: pg.url, Title: pg.title, Site: pg.host, SourceType: pg.sourceType, Stance: j.stance,
			Quote: j.quote, Confidence: round2(j.confidence), Weight: round2(w), Cluster: ids[root],
			PublishedAt: pg.published, RetrievedAt: pg.retrieved}
		if pg.factCheck != nil {
			e.FactCheck = &FactCheck{Publisher: pg.factCheck.Publisher, Rating: pg.factCheck.Rating}
		}
		v.Evidence = append(v.Evidence, e)
	}
	for _, a := range clusters {
		v.Support += a.sup
		v.Refute += a.ref
	}
	v.IndependentSources = len(clusters)
	sort.SliceStable(v.Evidence, func(i, k int) bool { return v.Evidence[i].Weight > v.Evidence[k].Weight })

	s, r, t := v.Support, v.Refute, c.Verdict
	hi, lo := math.Max(s, r), math.Min(s, r)
	switch {
	case hi < t.MinRelevant:
		v.Label, v.Reason = LabelUnverifiable, "no_relevant_evidence"
	case lo >= t.MinRelevant && lo/hi >= t.DisputeRatio:
		v.Label = LabelDisputed
	case s > r && s >= t.Supported:
		v.Label = LabelSupported
	case s > r && s >= t.MostlySupported:
		v.Label = LabelMostlySupported
	case s > r:
		v.Label, v.Reason = LabelUnverifiable, "weak_evidence"
	case r >= t.Refuted:
		v.Label = LabelRefuted
	default:
		// A weak refutation alone is not enough to call a claim disputed.
		v.Label, v.Reason = LabelUnverifiable, "weak_evidence"
	}
	if v.Label != LabelUnverifiable {
		// Heuristic, not calibrated yet (calibration is an M2 eval task):
		// agreement between sides times evidence mass, capped.
		agree := hi / (s + r)
		mass := math.Min(1, hi/(t.Supported+t.Refuted))
		v.Confidence = round2(math.Max(0.05, math.Min(0.95, agree*(0.5+0.5*mass))))
	}
	v.Support, v.Refute = round2(s), round2(r)
	return v
}

func round2(f float64) float64 { return math.Round(f*100) / 100 }
