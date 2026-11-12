# Pravdoměr

Mobilní aplikace (Flutter) + backend (Go) + inference na DGX Spark. Pro sdílený článek, příspěvek, obrázek nebo video vrátí původ a pravost média, teplotu textu (emoce a manipulativní techniky), ověření tvrzení se zdroji a srovnání dvou článků. Každý výstup má škálu, jistotu, vysvětlení a klikací zdroje.

Stav: **M0 – výzkum** (bez produkčního kódu, čeká na schválení).

| | |
|---|---|
| `Prompts/00-PRAVDOMER_PLAN.md` | zadání a zásady |
| `docs/PRAVDOMER_SOURCES.md` | zdroje dat, API, licence (ověřeno 11/2026) |
| `docs/PRAVDOMER_MODELS.md` | modely pro Spark a L40S, paměťový rozpočet |
| `docs/PRAVDOMER_EVAL.md` | eval čísla a latence po milnících |
| `eval/` | eval sada Tier 1 (metadata a anotace; texty a obrázky jen lokálně) |
| `llm_prompts/` | jazykově neutrální prompty LLM |
| `bin/` | nástroje M0: sběr eval sady, benchmark LLM |

## Nástroje M0

```sh
python3 -m venv .venv && .venv/bin/pip install trafilatura==2.0.0 feedparser==6.0.11
.venv/bin/python -I bin/eval_collect_articles.py        # 3 × 50 článků z RSS
.venv/bin/python -I bin/eval_collect_real_images.py     # 100 reálných fotek z Commons
cp .env.example .env                                     # adresa LiteLLM
sparkctl exec deepfake qwen36 60 10 "pravdomer bench" -- sh -c 'set -a; . ./.env; exec .venv/bin/python -I bin/bench_llm.py'
```

Běhová data (texty článků, obrázky, výstupy modelů, logy) jsou v gitignorovaném `run/`.
