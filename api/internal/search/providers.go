package search

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// Brave is the Brave Search web API (paid per query; live use only).
type Brave struct {
	APIKey  string
	BaseURL string // default https://api.search.brave.com/res/v1
	HTTP    *http.Client
}

func (b *Brave) Name() string { return "brave" }

func (b *Brave) Search(ctx context.Context, q Query) ([]Hit, error) {
	base := b.BaseURL
	if base == "" {
		base = "https://api.search.brave.com/res/v1"
	}
	v := url.Values{"q": {q.Text}, "count": {strconv.Itoa(max(1, min(20, q.Limit)))}, "safesearch": {"moderate"}}
	if q.Lang != "" {
		v.Set("search_lang", q.Lang)
	}
	var out struct {
		Web struct {
			Results []struct {
				URL     string `json:"url"`
				Title   string `json:"title"`
				PageAge string `json:"page_age"`
			} `json:"results"`
		} `json:"web"`
	}
	if err := getJSON(ctx, b.HTTP, base+"/web/search?"+v.Encode(), map[string]string{"X-Subscription-Token": b.APIKey}, &out); err != nil {
		return nil, fmt.Errorf("brave: %w", err)
	}
	hits := make([]Hit, 0, len(out.Web.Results))
	for _, r := range out.Web.Results {
		hits = append(hits, Hit{URL: r.URL, Title: r.Title, Provider: b.Name(), Published: parseTime(r.PageAge)})
	}
	return hits, nil
}

// Wikipedia searches one language edition (keyless; needs a descriptive
// User-Agent per Wikimedia policy).
type Wikipedia struct {
	UserAgent string
	BaseURL   string // default https://%s.wikipedia.org (with %s = lang)
	HTTP      *http.Client
}

func (w *Wikipedia) Name() string { return "wikipedia" }

func (w *Wikipedia) Search(ctx context.Context, q Query) ([]Hit, error) {
	lang := q.Lang
	if lang == "" || strings.ContainsAny(lang, "./:") {
		lang = "en"
	}
	base := w.BaseURL
	if base == "" {
		base = "https://%s.wikipedia.org"
	}
	site := fmt.Sprintf(base, lang)
	v := url.Values{"q": {q.Text}, "limit": {strconv.Itoa(max(1, min(10, q.Limit)))}}
	var out struct {
		Pages []struct {
			Key   string `json:"key"`
			Title string `json:"title"`
		} `json:"pages"`
	}
	if err := getJSON(ctx, w.HTTP, site+"/w/rest.php/v1/search/page?"+v.Encode(), map[string]string{"User-Agent": w.UserAgent}, &out); err != nil {
		return nil, fmt.Errorf("wikipedia: %w", err)
	}
	hits := make([]Hit, 0, len(out.Pages))
	for _, p := range out.Pages {
		hits = append(hits, Hit{URL: site + "/wiki/" + url.PathEscape(p.Key), Title: p.Title, Provider: w.Name()})
	}
	return hits, nil
}

// FactCheckAPI is the Google Fact Check Tools claims:search endpoint.
type FactCheckAPI struct {
	APIKey  string
	BaseURL string // default https://factchecktools.googleapis.com/v1alpha1
	HTTP    *http.Client
}

func (f *FactCheckAPI) Name() string { return "factcheck" }

func (f *FactCheckAPI) Search(ctx context.Context, q Query) ([]Hit, error) {
	base := f.BaseURL
	if base == "" {
		base = "https://factchecktools.googleapis.com/v1alpha1"
	}
	v := url.Values{"query": {q.Text}, "pageSize": {strconv.Itoa(max(1, min(10, q.Limit)))}, "key": {f.APIKey}}
	if q.Lang != "" {
		v.Set("languageCode", q.Lang)
	}
	var out struct {
		Claims []struct {
			Text        string `json:"text"`
			ClaimReview []struct {
				Publisher struct {
					Name string `json:"name"`
					Site string `json:"site"`
				} `json:"publisher"`
				URL           string `json:"url"`
				Title         string `json:"title"`
				ReviewDate    string `json:"reviewDate"`
				TextualRating string `json:"textualRating"`
			} `json:"claimReview"`
		} `json:"claims"`
	}
	if err := getJSON(ctx, f.HTTP, base+"/claims:search?"+v.Encode(), nil, &out); err != nil {
		return nil, fmt.Errorf("factcheck: %w", err)
	}
	var hits []Hit
	for _, c := range out.Claims {
		for _, r := range c.ClaimReview {
			if r.URL == "" {
				continue
			}
			pub := r.Publisher.Name
			if pub == "" {
				pub = r.Publisher.Site
			}
			hits = append(hits, Hit{URL: r.URL, Title: r.Title, Provider: f.Name(), Published: parseTime(r.ReviewDate),
				FactCheck: &FactCheck{Publisher: pub, Rating: r.TextualRating, ClaimText: c.Text}})
		}
	}
	return hits, nil
}
