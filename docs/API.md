# API Pravdoměru (M1)

Základ: `https://<host>/v1`. JSON v UTF-8. Každý požadavek nese hlavičku `X-Device-Id` (náhodné UUID, které si appka vygeneruje při prvním spuštění a uloží). Slouží jen pro rate limit, nic jiného se k němu neukládá.

## Založit analýzu

`POST /v1/analyses`

```json
{"url": "https://example.com/clanek"}
```
nebo vložený text:
```json
{"text": "Celý text…", "title": "volitelný titulek"}
```

Odpověď `202 Accepted` (nová analýza) nebo `200 OK` (výsledek z cache):

```json
{"id": "01JC…", "status": "queued", "events": "/v1/analyses/01JC…/events"}
```

Chyby (`4xx/5xx`) mají tvar `{"error": {"code": "…", "message": "…"}}`. Kódy:

| HTTP | code | Kdy |
|---|---|---|
| 400 | `bad_request` | chybí url i text, oboje zároveň, neplatné URL |
| 413 | `too_large` | text nad limit |
| 429 | `rate_limited` | moc požadavků ze zařízení; hlavička `Retry-After` v sekundách |
| 422 | `fetch_failed` | stránku nejde stáhnout (jen u synchronní validace URL) |

## Průběh (SSE)

`GET /v1/analyses/{id}/events` → `text/event-stream`. Po připojení server pošle všechny dosavadní události znovu (replay), takže appka se může kdykoli připojit nebo znovu připojit. Proud končí událostí `done` nebo `error`.

| event | data |
|---|---|
| `status` | `{"status": "fetching" \| "analyzing"}` |
| `document` | dokument, viz níže |
| `paragraph` | výsledek jednoho odstavce, viz níže; chodí v libovolném pořadí |
| `summary` | souhrn celého dokumentu |
| `error` | `{"code": "fetch_failed" \| "extract_failed" \| "llm_unavailable" \| "internal", "message": "…"}` |
| `done` | `{}` |

### `document`

```json
{"url": "https://…", "title": "…", "author": "…", "published_at": "2026-11-12T08:00:00Z",
 "site": "example.com", "language": "cs",
 "paragraphs": [{"p": 1, "text": "…"}, {"p": 2, "text": "…"}]}
```

`author`, `published_at` a `url` můžou chybět. `p` číslujeme od 1.

### `paragraph`

```json
{"p": 3, "score": 62,
 "emotions": {"anger": 0.7, "fear": 0.2, "disgust": 0.1, "sadness": 0.0, "joy": 0.0, "surprise": 0.0, "neutral": 0.2},
 "loaded_language": 0.6,
 "techniques": [{"technique": "name_calling", "quote": "…", "start": 12, "end": 31, "confidence": 0.8}]}
```

- `score` 0–100 (celé číslo).
- `start`/`end` jsou offsety v **UTF-16 kódových jednotkách** do `text` odstavce (přímo použitelné v Dartu `String.substring`). Citace je vždy ověřená proti textu; neověřitelné citace server zahodí, takže `quote == text.substring(start, end)` platí vždy.
- Hodnoty `technique`: `name_calling, loaded_language, fear_appeal, false_dilemma, whataboutism, appeal_to_authority, straw_man, exaggeration, repetition, doubt, flag_waving, slogans, causal_oversimplification, bandwagon, red_herring`. Appka je překládá přes ARB; neznámou hodnotu zobrazí syrově.

### `summary`

```json
{"score": 48, "emotions": {"anger": 0.31, "…": 0.0},
 "techniques": {"name_calling": 3, "fear_appeal": 1},
 "headline_clickbait": 0.4, "headline_matches_body": true,
 "paragraphs_analyzed": 12, "paragraphs_failed": 0, "quotes_dropped": 1,
 "model": "deepfake-llm", "method": "llm-v1", "latency_ms": 18400}
```

`score` je naměřená teplota textu, ne pravdivost. Váhy výpočtu jsou v `api/config/temperature.json`.

## Hotový výsledek

`GET /v1/analyses/{id}` → `{"id", "status": "queued|running|done|failed", "document", "paragraphs": [...], "summary", "error"}`. Stejné objekty jako v SSE.

## Ostatní

- `GET /healthz` → `200 ok`.
- Analyzovaný text se maže po `CACHE_TTL` (výchozí 7 dní), zůstávají jen metriky.
