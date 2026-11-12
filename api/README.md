# Pravdoměr API

Go služba pro M1: URL nebo vložený text → extrakce článku → teplota per odstavec přes LLM na SPARKu → průběžné výsledky přes SSE. Smlouva API je v [`../docs/API.md`](../docs/API.md).

## Struktura

| Balíček | Co dělá |
|---|---|
| `cmd/pravdomer-api` | konfigurace z env, start serveru |
| `internal/extract` | stažení stránky (bez přístupu do LAN, limit velikosti, UA DeepFakeBot), readability, dělení na odstavce, detekce jazyka |
| `internal/temperature` | bloky odstavců → paralelní LLM dotazy → validace citací → skóre podle `config/temperature.json` |
| `internal/quote` | tvrdý gate: citace se drží, jen když je doslova v textu; offsety v UTF-16 pro appku |
| `internal/llm` | OpenAI-kompatibilní klient na LiteLLM gateway |
| `internal/service` | fronta jobů, cache podle URL/textu, SSE hub s replay, mazání textů po `CACHE_TTL` |
| `internal/httpapi` | HTTP + SSE, rate limit per zařízení |
| `internal/store` | Postgres (sqlc, migrace golang-migrate) a in-memory varianta pro testy a lokální běh |

`internal/temperature/prompt.md` je kopie `llm_prompts/temperature.md`; test hlídá, že jsou stejné.

## Lokální běh

```sh
cd api
LLM_BASE_URL=http://SPARK_HOST:8080/v1 LLM_MODEL=openclaw-default go run ./cmd/pravdomer-api
```

Bez `DATABASE_URL` běží s pamětí (data se ztratí restartem). LLM na SPARKu jen přes broker: měření M1 spouští `bin/m1_smoke.sh` přes `sparkctl exec`.

## Proměnné

| Proměnná | Výchozí | |
|---|---|---|
| `LISTEN_ADDR` | `:8096` | |
| `DATABASE_URL` | – | `postgres://…`; migrace se aplikují při startu |
| `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` | `deepfake-llm` | alias v LiteLLM, cíl modelu je konfigurace |
| `LLM_CONCURRENCY`, `LLM_BLOCK_CHARS` | 4, 2500 | paralelní dotazy na článek, velikost bloku |
| `WORKERS`, `QUEUE_SIZE` | 4, 200 | souběžné analýzy, fronta |
| `CACHE_TTL` | `168h` | potom se smaže text a citace, zůstanou metriky |
| `SUBMIT_EVERY`, `SUBMIT_BURST` | `20s`, 5 | rate limit per `X-Device-Id` |
| `TEMPERATURE_WEIGHTS` | vestavěný | cesta k vlastnímu JSON s váhami |
| `BOT_USER_AGENT` | DeepFakeBot | |

## Gate

```sh
go vet ./... && go test -race ./...
sqlc generate   # po změně queries.sql nebo migrací; generovaný kód needitovat
```

Test proti Postgresu se spustí jen s `PRAVDOMER_TEST_DSN=postgres://…` (jednorázová DB).

## Nasazení

`docker-compose.yml` (Postgres + API, bez publikovaného portu, ven přes Cloudflare Tunnel). Hodnoty v `.env` podle `.env.example`. Nasazuje Olin.
