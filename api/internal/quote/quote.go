// Package quote validates model-produced quotes against the source text.
//
// This is the hard gate from the plan (chapter 10): a quote is kept only when
// it occurs in the stored text. Matching tolerates whitespace runs and
// typographic quote/dash variants, nothing else; the returned quote is always
// the exact original substring.
package quote

import (
	"strings"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"

	"golang.org/x/text/unicode/norm"
)

// Span is a validated quote position inside the source text.
type Span struct {
	Quote string // exact substring of the source
	Start int    // byte offset in source
	End   int    // byte offset in source (exclusive)
	// UTF-16 code unit offsets, for clients (Dart/JS strings).
	Start16 int
	End16   int
}

// Normalize returns NFC text with whitespace runs collapsed to a single
// space and trimmed. Use it on source paragraphs at ingest.
func Normalize(s string) string {
	s = norm.NFC.String(s)
	var b strings.Builder
	b.Grow(len(s))
	space := false
	for _, r := range s {
		if unicode.IsSpace(r) {
			space = true
			continue
		}
		if space && b.Len() > 0 {
			b.WriteByte(' ')
		}
		space = false
		b.WriteRune(r)
	}
	return b.String()
}

func fold(r rune) rune {
	switch r {
	case '‘', '’', '‚', '‛', '′', '`', '´':
		return '\''
	case '“', '”', '„', '‟', '«', '»', '″':
		return '"'
	case '‐', '‑', '‒', '–', '—', '―', '−':
		return '-'
	}
	if unicode.IsSpace(r) {
		return ' '
	}
	return r
}

// folded builds the matching form of s and, for each rune of the folded
// form, the byte offset of the corresponding rune in s.
func folded(s string) ([]rune, []int) {
	rs := make([]rune, 0, len(s))
	offs := make([]int, 0, len(s))
	prevSpace := true // drops leading whitespace
	for i, r := range s {
		f := fold(r)
		if f == ' ' {
			if prevSpace {
				continue
			}
			prevSpace = true
		} else {
			prevSpace = false
		}
		rs = append(rs, f)
		offs = append(offs, i)
	}
	// Trailing space would never match a trimmed quote; keep it harmless.
	return rs, offs
}

// Find locates q in src. It returns ok=false when q is empty or absent.
// When q occurs more than once, the first occurrence at or after hint
// (a byte offset) wins, otherwise the first occurrence.
func Find(src, q string, hint int) (Span, bool) {
	q = strings.TrimSpace(norm.NFC.String(q))
	if sp, ok := find(src, q, hint); ok {
		return sp, true
	}
	// Models often wrap the quote in quotation marks that are not part of it.
	stripped := strings.TrimSpace(strings.Trim(q, "\"'\u201C\u201D\u201E\u00AB\u00BB"))
	if stripped == q {
		return Span{}, false
	}
	return find(src, stripped, hint)
}

func find(src, q string, hint int) (Span, bool) {
	if q == "" {
		return Span{}, false
	}
	srcR, offs := folded(src)
	qR, _ := folded(q)
	for len(qR) > 0 && qR[len(qR)-1] == ' ' {
		qR = qR[:len(qR)-1]
	}
	if len(qR) == 0 || len(qR) > len(srcR) {
		return Span{}, false
	}
	first := -1
	for i := 0; i+len(qR) <= len(srcR); i++ {
		if !equalAt(srcR, qR, i) {
			continue
		}
		if offs[i] >= hint {
			first = i
			break
		}
		if first < 0 {
			first = i
		}
	}
	if first < 0 {
		return Span{}, false
	}
	last := first + len(qR) - 1
	start := offs[first]
	_, size := utf8.DecodeRuneInString(src[offs[last]:])
	end := offs[last] + size
	return Span{
		Quote:   src[start:end],
		Start:   start,
		End:     end,
		Start16: utf16Len(src[:start]),
		End16:   utf16Len(src[:end]),
	}, true
}

func equalAt(src, q []rune, i int) bool {
	for j, r := range q {
		if src[i+j] != r {
			return false
		}
	}
	return true
}

func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		n += utf16.RuneLen(r)
	}
	return n
}
