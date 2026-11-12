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
