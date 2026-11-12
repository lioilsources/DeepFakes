# Eval sada Pravdoměru

Tier 1 = CZ, SK, EN (plná sada, gate pro release). Tier 2 (DE, PL, UK, RU, ES, FR) se přidá menší sadou po M1.

## Co je v repu a co ne

| V repu (`eval/`) | Mimo repo (`run/eval/`, gitignore) |
|---|---|
| seznam médií a vzorkovací vrstvy (`tier1/outlets.csv`) | plné texty článků (autorské právo) |
| metadata článků: URL, titulek, datum, SHA-256 textu (`tier1/articles.csv`) | stažené obrázky a screenshoty |
| ruční anotace (gold): tvrzení, teplota, verdikty (`tier1/gold/*.jsonl`) | výstupy modelů (silver), benchmarky |
| metadata obrázků: zdroj, licence, generátor, prompt (`tier1/images_*.csv`) | |

Text článku se dá kdykoli znovu stáhnout z URL; SHA-256 ověří, že jde o stejnou verzi. Když se článek změní nebo zmizí, anotace zůstane, ale označí se `stale`.

## Složení Tier 1

| Část | Počet | Jak vzniká | Stav |
|---|---|---|---|
| Články | 3 × 50 (CZ, SK, EN) | `bin/eval_collect_articles.py`: RSS 34 médií, vrstvy news 50 %, opinion 20 %, tabloid 15 %, listed 15 % | CZ 50, SK 36, EN 50 (12. 11.: duplicitní texty vyřazeny; Parlamentní listy přes RSS vrací rozcestník → CZ listed jen 1, Denník N část paywall upoutávek; SK dobrat jinými feedy) |
| Tvrzení | 300 (100 na jazyk) | LLM navrhne (silver, `bin/bench_llm.py`), člověk opraví a označí verdikt s důkazem | čeká na ruční anotaci |
| Teplota | 60 článků (20 na jazyk), per odstavec | LLM předanotace, člověk opraví techniky a citace | čeká na ruční anotaci |
| Obrázky reálné | 100 | `bin/eval_collect_real_images.py`: Wikimedia Commons, EXIF z fotoaparátu, rok ≥ 2023, volná licence, mimo AI kategorie | 68 / 100 (dosbírat) |
| Obrázky syntetické | 100 | `tier1/image_prompts.csv`: stejná témata jako reálné, 4 generátory na SPARKu (ComfyUI) | čeká na okno ComfyUI |
| Obrázky z nových komerčních generátorů | doplněk | výřez z veřejné sady (viz `docs/PRAVDOMER_SOURCES.md`), ne vlastní generování přes cloud | M4 |
| Screenshoty ze sítí | 50 | ručně z telefonu (X, FB, IG, TikTok, Telegram, Bluesky), viz níže | čeká na Olina |

Vrstvy `stratum` jsou jen vzorkovací koše, aby sada nebyla složená jen z jednoho typu textu. Nejsou hodnocením médií a nikde se nezobrazují. `listed` = doména je uvedená na veřejném seznamu (konspiratori.sk, NFNZ) nebo nemá dohledatelnou redakci.

Každý obrázek se v evalu testuje ve třech variantách: originál, JPEG q75 zmenšený na 1280 px (simulace sdílení přes messenger) a screenshot obrazovky. Detektory, které fungují jen na originálech, jsou v praxi k ničemu.

## Pravidla anotace

### Tvrzení (`gold/claims.jsonl`)

Jeden řádek = jedno tvrzení:

```json
{"article": "cs-012", "quote": "doslovný úsek z textu", "claim": "samostatná věta", "kind": "fact",
 "label": "supported", "confidence": "high", "evidence": [{"url": "…", "passage": "…", "retrieved": "2026-11-20"}],
 "annotator": "A1", "note": ""}
```

- `quote` musí být doslovný podřetězec textu článku (kontroluje skript).
- `kind`: `fact` (ověřitelné o minulosti/přítomnosti), `opinion`, `prediction`. Ověřují se jen `fact`.
- `label`: `supported`, `mostly_supported`, `disputed`, `refuted`, `unverifiable`. Bez aspoň jednoho `evidence` je jediný přípustný label `unverifiable`.
- Evidence: přednost primárním zdrojům (data, zákon, originální dokument), pak agentury, pak média. Pět webů přebírajících jednu zprávu ČTK = jeden zdroj.
- 10 % tvrzení anotují dva lidé nezávisle; měříme shodu (Cohenovo kappa) a rozpory řeší třetí.

### Teplota (`gold/temperature.jsonl`)

Jeden řádek = jeden odstavec: `{"article", "p", "emotions": {…0–1}, "techniques": [{"technique", "quote"}], "annotator"}`. Taxonomie technik je v `llm_prompts/temperature.md` (podmnožina SemEval-2023 Task 3). Technika se zapíše jen s doslovnou citací.

### Obrázky (`tier1/images_*.csv`)

`label` = `real` / `synthetic` / `edited`; u syntetických generátor, model, seed a prompt. Reálné fotky musí mít ověřitelný původ (EXIF + stránka na Commons), jinak se do sady nedávají.

### Screenshoty (`tier1/screenshots.csv`, 50 kusů)

Rozložení: 10 X, 10 Facebook, 8 Instagram, 8 TikTok, 6 Telegram, 4 Bluesky, 4 YouTube. Půlka CZ/SK, půlka EN. Ke každému URL původního příspěvku (je-li veřejné) a ručně přepsaný text, autor, datum a síť jako gold pro OCR + VLM. 10 screenshotů záměrně upravených (změněný text nebo datum), aby šlo měřit, jak často pipeline upozorní „původ neověřen“.

## Metriky a gate

Viz kap. 10 plánu a `docs/PRAVDOMER_EVAL.md`. Tvrdý gate: podíl neplatných citací = 0. U obrázků se hlásí AUC a hlavně míra falešně pozitivních na reálných fotkách při zvoleném prahu.
