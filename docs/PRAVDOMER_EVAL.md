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

## M1 — latence teploty

`bin/m1_smoke.sh`: API lokálně (in-memory), 15 článků z eval sady (5 CZ/SK/EN) přes URL, 2 souběžně. 12. 11. 2026, **L40S sandbox**, Qwen3-30B-A3B-Instruct-2507-FP8 (vLLM, profil L), GPU současně na 100 % vytížené cizí dávkou → čísla jsou horní odhad.

| Běh | do dokumentu p50/p95 [s] | do 1. odstavce p50/p95 [s] | do souhrnu p50/p95 [s] | jazyk OK | zahozené citace |
|---|---|---|---|---|---|
| bloky 2 500 znaků × 4 paralelně | 0,2 / 0,7 | 27 / 70 | 67 / 106 | 87 % | 74 / 377 (20 %) |
| bloky 1 200 × 6, přesun citací, oprava SK (výchozí) | 0,2 / 0,4 | 22 / 35 | 37 / 50 | 100 % | 39 / 374 (10 %) |

Zjištění:
- Extrakce článku je zanedbatelná; čas je celý v LLM. Menší bloky = víc paralelních dotazů = souhrn ~2× dřív.
- Zahozené citace: model často cituje správně, ale k vedlejšímu odstavci. Citace doslova nalezená v jiném odstavci téhož bloku se přesune (pořád ověřená). Zbylých 10 % jsou parafráze nebo citace z titulku — zahazují se (tvrdý gate).
- Statistická detekce plete SK s CZ/PL; deklarovaný `lang` stránky v západoslovanské skupině má přednost.
- Plánovaných 1–5 s pro teplotu přes LLM nejde; realtime až s destilovaným enkodérem (M1b), viz M0 odhad.
- Měření na Sparku (Qwen3.6-35B-A3B) je ve frontě brokeru (job 1112-193).

## M2 — ověřování tvrzení (první smoke)

`bin/m2_smoke.sh`: API lokálně (in-memory), 9 článků z eval sady (3 CZ/SK/EN) přes URL, 2 souběžně. 20. 11. 2026.

**Podmínky běhu:**
- **Model:** **L40S sandbox, `qwen3-coder`** (Qwen3-Coder-30B-A3B), jediný model, který tam zrovna běžel. Cílový Qwen3.6 na SPARKu nebyl dostupný.
- **Hledání:** jen Wikipedie, bez klíčů pro Brave a Fact Check.
- **Ruční kontrola:** jen orientační, ne eval proti anotacím.

| Běh | tvrzení / ověřováno | do 1. verdiktu p50/p95 [s] | do souhrnu tvrzení p50/p95 [s] | neplatné citace v UI | zahozené citace (článek / zdroje) | verdikty |
|---|---|---|---|---|---|---|
| v1: první prompt | 77 / 48 | 40 / 66 | 50 / 85 | 0 | 2 / 7 | 11 převážně podl., 9 sporné, 28 nelze ověřit |
| v3: pravidlo „stejná událost“, slabé vyvrácení = nelze ověřit, kotva citace | 85 / 48 | 33 / 63 | 39 / 79 | 0 | – / 5 | 14 převážně podl., 1 sporné, 33 nelze ověřit |

**Zjištění:**
- **Mechanika drží.** Žádná neplatná citace se nedostala ven: offsety tvrzení klient kontroluje proti textu a sedí všechny. SSE průběh i souhrn fungují a ověření přidá k teplotě ~40 s.
- **Kvalita stance s `qwen3-coder` nestačí.** Z 15 verdiktů „převážně podloženo“ ve v3 je zhruba 8 v pořádku, zbytek ne:
  - Model bere jako podporu text o jiné události, třeba bombový útok v Petrohradu v roce 2017 u tvrzení o výbuchu z roku 2026.
  - Za podporu bere i jen zmínku stejné osoby nebo položku seznamu literatury.
  - Pravidla v promptu pomohla hlavně u vyvracení: počet „sporných“ klesl z 9 na 1.
- **Kotva citace nestačí.** Kontrola, že citace sdílí s tvrzením slovo nebo číslo, chytí jen hrubé případy.
- **Zdroje.** Bez Brave je jediným zdrojem Wikipedie, takže čerstvé zprávy často končí „nelze ověřit“. Všechny články Wikipedie se počítají jako jeden zdroj, a tak nejlepší dosažitelný verdikt je „převážně podloženo“.
- **Další krok:**
  - Stejný běh s cílovým modelem na SPARKu a s Brave klíčem.
  - Stance eval na CsFEVER.
  - Ruční anotace verdiktů na Tier 1.
  - Do té doby verdikty nezveřejňovat (gate kap. 10).

### M2 s cílovým modelem (Qwen3.6-35B-A3B-FP8 na L40S)

20. 11. 2026. Okno `deepfake-m2-eval-qwen36` ve frontě L40S (qctl, `bin/l40s/`). vLLM s max-model-len 16k, fp8 KV, bez obrazového vstupu. Spouští `bin/m2_l40s_eval.sh`.

**Stance na CsFEVER v2** (`original_nli/test`, CC BY-SA 3.0, `api/cmd/stance-eval`):
- Vzorek: 300 párů, po 100 na label, seed 1120.
- Prošly produkčním krokem: stejný prompt, ověření citace a kontrola kotvy.
- Jedna pasáž = evidence z CsFEVER, `irrelevant` se počítá jako NEI.

| | precision | recall | F1 |
|---|---|---|---|
| supports | 0,82 | 0,61 | 0,70 |
| refutes | 0,75 | 0,66 | 0,70 |
| irrelevant (NEI) | 0,56 | 0,77 | 0,65 |
| **accuracy / macro F1** | | | **0,68 / 0,68** |

Zjištění ke stance:
- **Opatrnost.** Model je spíš opatrný. Chyby jdou hlavně do „irrelevant“: 35 ze 60 minutých podpor a vyvrácení jde na vrub modelu.
- **Gate.** Zbylých 25 zahodil gate: 11 neplatných citací a 17 případů, kdy citace nesdílela s tvrzením kotvu. Typicky jde o transliteraci jmen, např. „Sejong“ v tvrzení a „Sedžong“ v evidenci. To je vědomá cena za tvrdý gate.
- **Falešné závěry.** U NEI párů dal model 15× „refutes“ a 8× „supports“.
- **Rychlost.** 300 párů za 77 s, tedy ~4 páry/s při 16 souběžných dotazech.

**Smoke na 9 článcích:** stejné články a stejná podmínka jako výše, tedy jen Wikipedie bez Brave.

| Běh | tvrzení / ověřováno | do 1. verdiktu p50/p95 [s] | do souhrnu tvrzení p50/p95 [s] | neplatné citace v UI | verdikty |
|---|---|---|---|---|---|
| Qwen3.6 FP8 | 67 / 50 | 22 / 34 | 31 / 48 | 0 | 10 převážně podl., 40 nelze ověřit |

Zjištění ke smoke:
- **Přesnost.** Ručně z 10 verdiktů „převážně podloženo“ sedí zhruba 8–9. S `qwen3-coder` to bylo ~8 z 15.
- **Bez falešných vyvrácení.** Žádné „sporné“ ani „vyvrácené“ bez opory.
- **Chyba, která zbyla:** citace o jiném podílu („Democrat won less than 40 %“) u tvrzení o 40 % černých voličů.
- **Rychlost.** O ~30 % rychlejší než coder model.
- **Nelze ověřit.** 80 % „nelze ověřit“ jsou čerstvé zprávy, které Wikipedie nemá. Čeká se na Brave.

**Smoke s Brave a Google Fact Check** (20. 11., okno `deepfake-m2-eval-qwen36-brave`, stejné články):

| Běh | tvrzení / ověřováno | do 1. verdiktu p50/p95 [s] | do souhrnu tvrzení p50/p95 [s] | evidence | verdikty |
|---|---|---|---|---|---|
| jen Wikipedie | 67 / 50 | 22 / 34 | 31 / 48 | 36 | 10 převážně podl., 40 nelze ověřit |
| + Brave, Fact Check | 67 / 51 | 26 / 36 | 36 / 44 | 57 | 2 podl., 12 převážně, 1 sporné, 2 vyvrácené, 34 nelze ověřit |

Zjištění:
- **Zdroje.** Evidence: 33 encyklopedie, 20 neznámé domény, 4 zpravodajství. Fact Check pro tato tvrzení nic nenašel.
- **Rozpočet Brave.** `BRAVE_DAILY_LIMIT=30` došel uprostřed běhu (76 dotazů odmítnuto). Plně by 9 článků chtělo ~106 dotazů Brave, tedy ~12 na článek. Při 30 denně to stačí na 2–3 články.
- **Podloženo a převážně podloženo:** ručně sedí ~13 ze 14. Slabé je jen „Likely Republican“ podle Cooka, kde zdroj zmiňuje jen kritiku prognóz.
- **Sporné (1):** obhajitelné.
- **Vyvrácené (2): obě chybně.** To je nejhorší směr chyby.
  - Finidr: tvrzení „3,1 milionu knih měsíčně“ proti „přes 30 milionů za rok“. Jiná jednotka času, čísla jsou ve skutečnosti v souladu.
  - Rottrová: zdroje se rozcházejí (Stuttgart 1988–1990 vs. do 1992). Mělo být sporné, poměr S/R 0,32 je těsně pod prahem 0,35. Část zdrojů jsou přepisy téže zprávy v jiném jazyce, které shingly nespojí.
- **Další krok:** stance prompt musí brát jiný časový úsek nebo jednotku jako „irrelevant“, ne „refutes“. Shlukování přepisů napříč jazyky přijde s embeddingy.
- **Stance CsFEVER (opakování):** accuracy 0,68, macro F1 0,685, stejné jako minule.

**Pravidlo o období a jednotce ve stance promptu** (22. 11., okno `deepfake-m2-eval-qwen36-stance2`): nepomohlo.
- Smoke: 2 podl., 11 převážně, 1 sporné, 2 vyvrácené, 32 nelze ověřit. Obě vyvrácení zůstala.
- Finidr teď model „vyvrací“ dokonce ročním číslem z roku 2020.
- CsFEVER: accuracy 0,683, macro F1 0,689, precision refutes 0,79. V mezích šumu.
- Proto vznikla samostatná kontrola vyvrácení (`llm_prompts/refute.md`, viz `docs/M2_CLAIMS.md`).

**S kontrolou vyvrácení** (22. 11., okno `deepfake-m2-eval-qwen36-refute`):

| Běh | verdikty (smoke) | CsFEVER acc / macro F1 | refutes P / R | NEI → refutes |
|---|---|---|---|---|
| Brave, původní prompt | 2 podl., 12 převážně, 1 sporné, 2 vyvrácené, 34 nelze ověřit | 0,68 / 0,685 | 0,76 / 0,67 | 16 |
| + pravidlo v promptu | 2 / 11 / 1 / 2 / 32 | 0,683 / 0,689 | 0,79 / 0,64 | 16 |
| + kontrola vyvrácení | 2 / 12 / 2 / 1 / 29 | 0,683 / 0,687 | 0,82 / 0,59 | 9 |

- **CsFEVER.** Kontrola zahodila 13 vyvrácení. Falešných vyvrácení u NEI ubylo ze 16 na 9, za cenu 5 bodů recallu refutes. Tuhle výměnu chceme.
- **Rottrová.** Teď „sporné“, což odpovídá rozcházejícím se zdrojům.
- **Finidr, měsíční náklad.** Pořád „vyvráceno“, ale z jiného důvodu: starší zdroje uvádějí 16–24 milionů ročně, tedy méně než 3,1 milionu měsíčně. Model převedl jednotky, proti zadání. Skutečný problém je **stáří dat**: starší čísla o rostoucí firmě nejsou vyvrácení. Další krok je dát do stance datum zdroje a článku, aby starší údaj šel do „irrelevant“.
- **Finidr, 500miliontá kniha.** „Sporné“: Wikipedie uvádí červen 2026, web tiskárny 19. 6. 2025. Zdroje se opravdu rozcházejí.
- **Latence.** Do souhrnu tvrzení p50 44 s, předtím 39 s. Navíc je jedno volání na každé „refutes“.

**S datem článku a zdroje** (22. 11., okno `deepfake-m2-eval-qwen36-dates`):
- **Verdikty (smoke):** 3 podl., 12 převážně, 2 sporné, 0 vyvrácených, 36 nelze ověřit. Extrakce našla 77 tvrzení místo 64, extrakce mezi běhy kolísá.
- **CsFEVER:** accuracy 0,697, macro F1 0,702, refutes P 0,85 / R 0,64. Nejlepší z dosavadních běhů. CsFEVER data nemá, zlepšení jde nejspíš na vrub pravidlu „nepřevádět jednotky“ v kontrole vyvrácení.
- **Finidr, měsíční náklad:** teď „nelze ověřit“ (`weak_evidence`), správně.
- **Finidr, 500miliontá kniha:** „podloženo“. Jestli je to správně, záleží na zdroji: web tiskárny uvádí 2025, Wikipedie 2026.
- **Nová chyba:** „sporné“ u tvrzení, že Mississippi neposlalo černého senátora od Rekonstrukce. Citace ho ve skutečnosti podporuje. Stránka Wikipedie měla datum 2022 (den založení článku), přestože popisuje volby 2026.
- **Oprava:** encyklopedie datum nedostanou.
- **Latence:** do souhrnu tvrzení p50 49 s / p95 68 s. Bylo víc tvrzení a sdílená GPU, podmínky nejsou stejné.

## Gate pro release (kap. 10 plánu)

| Metrika | Gate |
|---|---|
| Neplatné citace | 0 (tvrdý) |
| Teplota F1 per technika | CZ i EN zvlášť, cíl stanovit po M1 baseline |
| Verdikty: přesnost | stanovit po M2 baseline |
| Obrázky: FPR na reálných fotkách | ≤ 5 % při zvoleném prahu, hlášeno i pro JPEG-recompress a screenshot varianty |
| Kalibrace jistoty | ECE ≤ 0,1 |
