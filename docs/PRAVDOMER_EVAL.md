# PRAVDOMER_EVAL.md — eval čísla a latence

Každý milník sem zapíše eval čísla, verze modelů, datum a podmínky měření (takt GPU, co dalšího na stroji běželo).

## M0 — upřesněný odhad latencí

Vychází z interních měření Qwen3.6-35B-A3B NVFP4 na Sparku (řádově desítky tok/s na jeden proud, stovky souhrnně při souběhu; přesná čísla neveřejná). Měření Pravdoměru (`bin/bench_llm.py`) je zařazené ve frontě brokeru, tabulka se po něm přepíše.

| Výstup | Plán | Upřesněný odhad | Proč | Důsledek |
|---|---|---|---|---|
| Teplota textu přes LLM (fáze 1) | 1–5 s | **15–35 s** celý článek; první odstavec ~3 s | JSON per odstavec = 1 500–2 500 výstupních tokenů při rychlosti jednoho proudu | SSE po odstavcích (paralelně 4–8 požadavků po blocích odstavců), kompaktní výstup (jen nenulové emoce). Realtime 1–5 s jen s enkodérem z fáze 2 → destilaci posunout dopředu (M1b). |
| Teplota přes enkodér (fáze 2) | 1–5 s | < 1 s | XLM-R large ~50–100 odstavců/s na GPU | cíl pro produkci a leaderboard crawl |
| Titulek vs. obsah, clickbait | 1–5 s | 2–4 s | krátký výstup | realtime |
| C2PA, EXIF, cache hit | 1–3 s | < 1 s | CPU | realtime |
| Existující fact-check (Google API) | 1–3 s | 1–2 s na tvrzení | jeden HTTP dotaz | paralelně s extrakcí |
| Extrakce tvrzení | součást 30–120 s | **15–30 s** | ~15 tvrzení × ~120 tokenů | první tvrzení streamovat, jakmile je v JSON hotové |
| Ověření 5–10 tvrzení | 30–120 s | **60–180 s** | 2–3 dotazy × top 5 stránek × fetch 1–5 s, reranker, NLI přes LLM ~2–4 s na pár; LLM sdílené s dalšími uživateli | NLI předfiltrovat enkodérem (CsFEVER XLM-R), LLM jen na sporné páry; limit tvrzení per článek |
| Detektor syntetického obrázku | 3–15 s | 1–3 s | ViT ensemble na GPU < 1 s; zbytek stažení a varianty | skoro realtime |
| Reverse search původu | 5–20 s | jen vlastní index < 1 s; externí API zatím ne | viz PRAVDOMER_SOURCES, rozhodnutí 3 v MODELS | |
| Srovnání dvou článků | 1–3 min | 2–4 min | 2× extrakce + zarovnání + ověření jen rozporů | job + notifikace |
| Video (ASR + snímky + hlas) | 0,5–2× délky | 0,2–0,5× délky | Whisper na GPU výrazně rychlejší než realtime; Canary na Sparku neměřeno | job + notifikace |

**Hlavní riziko kapacity:** jeden Spark obsluhuje i jiné projekty a ComfyUI s velkým LLM nesmí běžet souběžně (broker). Pravdoměr potřebuje profil s Qwen3.6 + embedding + enkodéry trvale. To je rozhodnutí o profilu brokeru pro Olina před M1 (nový profil `pravdomer` nebo doplňky k profilu `llm`).

## M0 — benchmark LLM (čeká na okno)

Skript: `bin/bench_llm.py`, prompty `llm_prompts/temperature.md` a `llm_prompts/claims.md`, 30 článků (10 CZ, 10 SK, 10 EN) z eval sady, c=4. Měří TTFT, celkovou dobu, výstupní tok/s, platnost JSON a **podíl doslovně platných citací** (zkouška tvrdého gate z kap. 10). Výstupy jsou silver předanotace pro ruční kontrolu.

| Model | Úloha | p50 / p95 [s] | tok/s p50 | JSON OK | citace přesně | Datum |
|---|---|---|---|---|---|---|
| Qwen3.6-35B-A3B NVFP4 | teplota | – | – | – | – | – |
| Qwen3.6-35B-A3B NVFP4 | tvrzení | – | – | – | – | – |

Další na řadě (po schválení stažení): Qwen3.6-27B, Gemma 4 26B, Nemotron 3 Super (samostatné okno).

## Gate pro release (kap. 10 plánu)

| Metrika | Gate |
|---|---|
| Neplatné citace | 0 (tvrdý) |
| Teplota F1 per technika | CZ i EN zvlášť, cíl stanovit po M1 baseline |
| Verdikty: přesnost | stanovit po M2 baseline |
| Obrázky: FPR na reálných fotkách | ≤ 5 % při zvoleném prahu, hlášeno i pro JPEG-recompress a screenshot varianty |
| Kalibrace jistoty | ECE ≤ 0,1 |
