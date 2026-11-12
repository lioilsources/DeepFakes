// Package extract turns a web page or pasted text into a clean document
// split into paragraphs.
package extract

import (
	"bytes"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	readability "codeberg.org/readeck/go-readability/v2"
	"github.com/abadojack/whatlanggo"
	"golang.org/x/net/html"
	"golang.org/x/net/html/atom"
	"golang.org/x/net/html/charset"

	"github.com/lioilsources/DeepFakes/api/internal/quote"
)

// ErrNoContent means no readable article text was found.
var ErrNoContent = errors.New("no readable content")

// Limits keep one analysis bounded in LLM cost.
const (
	MaxParagraphs   = 80
	MaxChars        = 40000
	MinParagraphLen = 25 // runes; shorter blocks are captions, buttons, bylines
)

// Document is the extracted article.
type Document struct {
	URL         string     `json:"url,omitempty"`
	Title       string     `json:"title"`
	Author      string     `json:"author,omitempty"`
	PublishedAt *time.Time `json:"published_at,omitempty"`
	Site        string     `json:"site,omitempty"`
	Language    string     `json:"language"`
	Paragraphs  []string   `json:"-"`
	Truncated   bool       `json:"truncated,omitempty"`
}

// FromHTML extracts the main article from an HTML page.
func FromHTML(p Page) (Document, error) {
	r, err := charset.NewReader(bytes.NewReader(p.HTML), p.ContentType)
	if err != nil {
		r = bytes.NewReader(p.HTML)
	}
	root, err := html.Parse(r)
	if err != nil {
		return Document{}, fmt.Errorf("parse html: %w", err)
	}
	art, err := readability.FromDocument(root, p.URL)
	if err != nil {
		return Document{}, fmt.Errorf("%w: %v", ErrNoContent, err)
	}
	doc := Document{
		URL:    p.URL.String(),
		Title:  quote.Normalize(art.Title()),
		Author: quote.Normalize(art.Byline()),
		Site:   siteOf(p.URL, art.SiteName()),
	}
	if t, err := art.PublishedTime(); err == nil && !t.IsZero() {
		t = t.UTC()
		doc.PublishedAt = &t
	}
	if art.Node != nil {
		doc.Paragraphs = blocks(art.Node)
	}
	if len(doc.Paragraphs) == 0 {
		var buf bytes.Buffer
		if err := art.RenderText(&buf); err == nil {
			doc.Paragraphs = splitText(buf.String())
		}
	}
	doc.Paragraphs = dropTitle(doc.Paragraphs, doc.Title)
	if len(doc.Paragraphs) == 0 {
		return Document{}, ErrNoContent
	}
	doc.limit()
	doc.Language = detectLang(doc, art.Language())
	return doc, nil
}

// FromText builds a document from pasted text. Paragraphs are separated by
// blank lines; text without blank lines is split on single newlines.
func FromText(text, title string) (Document, error) {
	doc := Document{Title: quote.Normalize(title), Paragraphs: splitText(text)}
	if len(doc.Paragraphs) == 0 {
		return Document{}, ErrNoContent
	}
	doc.limit()
	doc.Language = detectLang(doc, "")
	return doc, nil
}

func siteOf(u *url.URL, name string) string {
	if u != nil && u.Hostname() != "" {
		return strings.TrimPrefix(strings.ToLower(u.Hostname()), "www.")
	}
	return quote.Normalize(name)
}

func (d *Document) limit() {
	total := 0
	for i, p := range d.Paragraphs {
		total += len(p)
		if i >= MaxParagraphs || total > MaxChars {
			d.Paragraphs = d.Paragraphs[:i]
			d.Truncated = true
			return
		}
	}
}

var blockAtoms = map[atom.Atom]bool{
	atom.P: true, atom.H1: true, atom.H2: true, atom.H3: true, atom.H4: true, atom.H5: true, atom.H6: true,
	atom.Li: true, atom.Blockquote: true, atom.Pre: true, atom.Dd: true, atom.Dt: true, atom.Figcaption: false,
}

// blocks collects text of leaf-most block elements in document order.
func blocks(n *html.Node) []string {
	var out []string
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if n.Type == html.ElementNode {
			switch n.DataAtom {
			case atom.Script, atom.Style, atom.Noscript, atom.Figure, atom.Figcaption, atom.Nav, atom.Aside, atom.Button, atom.Form:
				return
			}
			if blockAtoms[n.DataAtom] && !hasBlockChild(n) {
				if t := quote.Normalize(textOf(n)); utf8.RuneCountInString(t) >= MinParagraphLen {
					out = append(out, t)
				}
				return
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return dedupe(out)
}

func hasBlockChild(n *html.Node) bool {
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		if c.Type == html.ElementNode && (blockAtoms[c.DataAtom] || hasBlockChild(c)) {
			return true
		}
	}
	return false
}

func textOf(n *html.Node) string {
	var b strings.Builder
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		switch n.Type {
		case html.TextNode:
			b.WriteString(n.Data)
		case html.ElementNode:
			switch n.DataAtom {
			case atom.Script, atom.Style:
				return
			case atom.Br:
				b.WriteByte(' ')
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(n)
	return b.String()
}

func splitText(text string) []string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	parts := strings.Split(text, "\n\n")
	if len(parts) == 1 {
		parts = strings.Split(text, "\n")
	}
	var out []string
	for _, p := range parts {
		if t := quote.Normalize(p); t != "" {
			out = append(out, t)
		}
	}
	return dedupe(out)
}

func dedupe(in []string) []string {
	seen := make(map[string]bool, len(in))
	out := in[:0]
	for _, p := range in {
		if seen[p] {
			continue
		}
		seen[p] = true
		out = append(out, p)
	}
	return out
}

func dropTitle(ps []string, title string) []string {
	if len(ps) > 0 && title != "" && ps[0] == title {
		return ps[1:]
	}
	return ps
}

// detectLang prefers a statistical guess over the page's lang attribute
// (CMS templates often declare a wrong one), but falls back to it on short
// or ambiguous text.
func detectLang(d Document, declared string) string {
	sample := d.Title + "\n" + strings.Join(d.Paragraphs, "\n")
	if len(sample) > 4000 {
		sample = sample[:4000]
	}
	info := whatlanggo.Detect(sample)
	code := info.Lang.Iso6391()
	declared = strings.ToLower(strings.SplitN(strings.SplitN(declared, "-", 2)[0], "_", 2)[0])
	if code == "" || (!info.IsReliable() && declared != "") {
		if declared != "" {
			return declared
		}
		return "und"
	}
	return code
}
