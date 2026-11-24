// JSON examples from docs/API.md (shortened texts are replaced by real ones
// so that offsets can be checked).

const documentJson = '''
{"url": "https://example.com/clanek", "title": "Titulek článku", "author": "Jana Nováková",
 "published_at": "2026-11-12T08:00:00Z", "site": "example.com", "language": "cs",
 "paragraphs": [{"p": 1, "text": "První odstavec je klidný."}, {"p": 2, "text": "Tihle zrádci zničí naši zemi!"}]}
''';

const documentMinimalJson = '''
{"title": "Vložený text", "site": "", "language": "cs",
 "paragraphs": [{"p": 1, "text": "Jen text."}]}
''';

const paragraphJson = '''
{"p": 3, "score": 62,
 "emotions": {"anger": 0.7, "fear": 0.2, "disgust": 0.1, "sadness": 0.0, "joy": 0.0, "surprise": 0.0, "neutral": 0.2},
 "loaded_language": 0.6,
 "techniques": [{"technique": "name_calling", "quote": "zrádci", "start": 6, "end": 12, "confidence": 0.8}]}
''';

const summaryJson = '''
{"score": 48, "emotions": {"anger": 0.31, "fear": 0.0},
 "techniques": {"name_calling": 3, "fear_appeal": 1},
 "headline_clickbait": 0.4, "headline_matches_body": true,
 "paragraphs_analyzed": 12, "paragraphs_failed": 0, "quotes_dropped": 1,
 "model": "deepfake-llm", "method": "llm-v1", "latency_ms": 18400}
''';

const startJson =
    '{"id": "01JCABC", "status": "queued", "events": "/v1/analyses/01JCABC/events"}';

const errorJson = '{"error": {"code": "rate_limited", "message": "slow down"}}';

// Claims (M2). The quote is "odstavec je klidný" in paragraph 1 of
// documentJson.
const claimJson = '''
{"id": "c1", "p": 1, "quote": "odstavec je klidný", "start": 6, "end": 24,
 "claim": "Vláda schválila rozpočet se schodkem 230 miliard korun.",
 "kind": "fact", "checkworthy": 0.9, "entities": ["vláda"]}
''';

const verdictJson = '''
{"claim_id": "c1", "label": "supported", "confidence": 0.62,
 "explanation": "Zdroje [1] a [2] uvádějí schodek 230 miliard korun.",
 "support": 1.44, "refute": 0, "independent_sources": 2, "sources_considered": 4,
 "evidence": [{"url": "https://mfcr.gov.cz/rozpocet", "title": "Rozpočet 2027", "site": "mfcr.gov.cz", "source_type": "primary",
   "stance": "supports", "quote": "schodek ve výši 230 miliard Kč", "confidence": 0.9, "weight": 0.9, "cluster": 1,
   "published_at": "2026-11-12T08:00:00Z", "retrieved_at": "2026-11-20T10:00:00Z",
   "factcheck": {"publisher": "Demagog.cz", "rating": "Pravda"}}]}
''';

const claimsSummaryJson = '''
{"claims_found": 9, "checked": 6, "by_label": {"supported": 3, "unverifiable": 2, "not_checked": 3, "refuted": 1},
 "quotes_dropped": 1, "evidence_quotes_dropped": 0, "searches": 18, "search_errors": 0, "pages_fetched": 22,
 "providers": ["factcheck", "brave", "wikipedia"], "model": "deepfake-llm", "method": "claims-v1", "latency_ms": 64000}
''';

/// GET /v1/analyses/{id} after purge: texts gone, verdicts and links kept.
const purgedResultJson = '''
{"id": "01JC", "status": "done",
 "document": {"title": "T", "site": "example.com", "paragraphs": [{"p": 1, "text": ""}]},
 "paragraphs": [{"p": 1, "score": 20}], "summary": {"score": 20},
 "claims": [
   {"id": "c1", "p": 1, "quote": "", "start": 6, "end": 24, "claim": "", "kind": "fact",
    "verdict": {"label": "refuted", "confidence": 0.7,
      "evidence": [{"url": "https://demagog.cz/x", "site": "demagog.cz", "source_type": "fact_checker", "stance": "refutes", "quote": ""}]}},
   {"id": "c2", "p": 1, "quote": "", "start": 0, "end": 5, "claim": "", "kind": "opinion"}
 ],
 "claims_summary": {"claims_found": 2, "checked": 1, "by_label": {"refuted": 1}}}
''';
