package claims

import (
	"math"
	"net/url"
	"sort"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// passage is a slice of a downloaded source page.
type passage struct {
	page  *page
	text  string
	score float64
}

// tokens lowercases, strips diacritics and splits into words; numbers are
// kept whole (with inner separators removed: "1 250" and "1,250" stay apart
// from words but "1250" matches "1 250" only if written so).
func tokens(s string) []string {
	s = norm.NFD.String(strings.ToLower(s))
	var out []string
	var b strings.Builder
	flush := func() {
		if b.Len() > 0 {
			out = append(out, b.String())
			b.Reset()
		}
	}
	for _, r := range s {
		switch {
		case unicode.Is(unicode.Mn, r):
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			b.WriteRune(r)
		default:
			flush()
		}
	}
	flush()
	return out
}

func isNumber(t string) bool {
	for _, r := range t {
		if !unicode.IsDigit(r) {
			return false
		}
	}
	return t != ""
}

// stem is a crude prefix stemmer for inflected languages (cs, sk, pl):
// "rozpočet", "rozpočtu" → "rozpo". Good enough for lexical ranking.
func stem(t string) string {
	if isNumber(t) {
		return t
	}
	r := []rune(t)
	if len(r) > 5 {
		return string(r[:5])
	}
	return t
}

func stems(s string) []string {
	ts := tokens(s)
	for i, t := range ts {
		ts[i] = stem(t)
	}
	return ts
}

// keep decides whether a token carries meaning for lexical ranking.
func keep(t string) bool { return isNumber(t) || len([]rune(t)) >= 3 }

// splitPassages merges consecutive paragraphs up to limit characters; a
// longer paragraph becomes its own passage.
func splitPassages(paragraphs []string, limit int) []string {
	var out []string
	var cur strings.Builder
	for _, p := range paragraphs {
		if cur.Len() > 0 && cur.Len()+len(p)+1 > limit {
			out = append(out, cur.String())
			cur.Reset()
		}
		if cur.Len() > 0 {
			cur.WriteByte('\n')
		}
		cur.WriteString(p)
	}
	if cur.Len() > 0 {
		out = append(out, cur.String())
	}
	return out
}

// rank scores passages against the claim with a BM25-like overlap of
// claim terms (numbers count double), IDF taken over the candidate pool.
// Cross-lingual matching relies on names and numbers; an embedding
// reranker can replace this later behind the same function.
func rank(cl Claim, ps []passage) {
	terms := map[string]float64{}
	for _, t := range stems(cl.Claim + " " + cl.Quote + " " + strings.Join(cl.Entities, " ")) {
		if !keep(t) {
			continue
		}
		w := 1.0
		if isNumber(t) {
			w = 2
		}
		terms[t] = math.Max(terms[t], w)
	}
	df := map[string]int{}
	tfs := make([]map[string]int, len(ps))
	lens := make([]int, len(ps))
	total := 0
	for i, p := range ps {
		tf := map[string]int{}
		toks := stems(p.text)
		for _, t := range toks {
			if _, ok := terms[t]; ok {
				tf[t]++
			}
		}
		for t := range tf {
			df[t]++
		}
		tfs[i], lens[i] = tf, len(toks)
		total += len(toks)
	}
	if len(ps) == 0 {
		return
	}
	avg := math.Max(1, float64(total)/float64(len(ps)))
	n := float64(len(ps))
	const k1, b = 1.2, 0.75
	for i := range ps {
		s := 0.0
		for t, f := range tfs[i] {
			idf := math.Log(1 + (n-float64(df[t])+0.5)/(float64(df[t])+0.5))
			tf := float64(f)
			s += terms[t] * idf * tf * (k1 + 1) / (tf + k1*(1-b+b*float64(lens[i])/avg))
		}
		ps[i].score = s
	}
}

// pick returns the best passages, at most perPage from one page and only
// passages with some overlap.
func pick(ps []passage, total, perPage int) []passage {
	sort.SliceStable(ps, func(i, j int) bool { return ps[i].score > ps[j].score })
	used := map[*page]int{}
	var out []passage
	for _, p := range ps {
		if len(out) >= total {
			break
		}
		if p.score <= 0 || used[p.page] >= perPage {
			continue
		}
		used[p.page]++
		out = append(out, p)
	}
	return out
}

// hostOf returns the lowercase host without "www.".
func hostOf(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	return strings.TrimPrefix(strings.ToLower(u.Hostname()), "www.")
}

var twoLevelSuffixes = map[string]bool{"co.uk": true, "org.uk": true, "ac.uk": true, "gov.uk": true, "com.au": true, "co.jp": true}

// siteOf approximates the registrable domain (no public suffix list).
func siteOf(host string) string {
	parts := strings.Split(host, ".")
	if len(parts) <= 2 {
		return host
	}
	last2 := strings.Join(parts[len(parts)-2:], ".")
	if twoLevelSuffixes[last2] && len(parts) >= 3 {
		return strings.Join(parts[len(parts)-3:], ".")
	}
	return last2
}

// sourceType maps a host to a type via the most specific configured suffix.
func (c *Config) sourceType(host string) string {
	for h := host; h != ""; {
		if t, ok := c.DomainTypes[h]; ok {
			return t
		}
		i := strings.IndexByte(h, '.')
		if i < 0 {
			break
		}
		h = h[i+1:]
	}
	return "unknown"
}

func shingles(s string) map[string]bool {
	ts := tokens(s)
	out := map[string]bool{}
	for i := 0; i+3 <= len(ts); i++ {
		out[strings.Join(ts[i:i+3], " ")] = true
	}
	if len(ts) < 3 && len(ts) > 0 {
		out[strings.Join(ts, " ")] = true
	}
	return out
}

func jaccard(a, b map[string]bool) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	inter := 0
	for k := range a {
		if b[k] {
			inter++
		}
	}
	return float64(inter) / float64(len(a)+len(b)-inter)
}
