# PRAVDOMER_SOURCES.md — zdroje dat, API a licence (M0)

Stav: rešerše ke dni 12. 11. 2026, ověřuje kapitoly 5 a 16 plánu. U každého řádku je zdroj a značka ověřeno/neověřeno. Nejde o právní radu; před M7 a před veřejným leaderboardem (M6) jde vše licenční k právníkovi.

## Co se proti plánu změnilo

| Plán počítal s | Skutečnost 11/2026 | Dopad |
|---|---|---|
| Brave Search API (free) | free tier zrušen 2/2026, 5 $/1000 dotazů, ukládat SERP jen s custom plánem | ukládáme jen URL a vlastní stažený text, ne výsledky hledání; limit dotazů per uživatel nutný hned v M2 |
| Bing jako záloha | API vypnuté 8/2025 | vypadá; záloha Exa / Tavily / GDELT |
| ClaimReview jako hlavní zdroj fact-checků | Google 6/2025 přestal ClaimReview zobrazovat, dump zanikl; API běží | API používat, ale počítat s ubýváním; přímé RSS/dohody s Demagog, Manipulátoři, AFP |
| CEDMO | hlavní grant do 10/2026, pokračování nedohledáno | později, ověřit provoz |
| ČSÚ VDB | končí 2026, nově DataStat API | konektor rovnou na DataStat |
| WHO GHO OData | ohlášená deprecace | ověřit nástupce před konektorem |
| Seed registru z Konspiratori.sk, MBFC, NFNZ | Konspiratori bez licence a ve sporech; MBFC zakazuje client-facing použití; NFNZ licence nejasná | registr začne z **vlastních doložitelných faktů** (vlastník, impresum, opravy), cizí hodnocení jen jako interní signál, nikdy zobrazený; o převzetí požádat |
| Trénink teploty na SemEval, GoEmotions, CZ korpusy | většina NC / jen pro výzkum, SemEval bez redistribuce | pro komerční budoucnost: vlastní anotace + LLM labely; NC data jen na eval |
| Reddit API po MVP | Reddit ukončuje veřejné Data API (nové žádosti od 31. 10. 2026, konec 3/2027; jen sekundární zdroje) | vypadá, jen screenshot |
| X API placené | pay-per-use 0,005 $/post; oEmbed zdarma vrací text, autora a datum | oEmbed stačí už pro MVP |
| Meta jen pro výzkumníky | oEmbed od 6/2026 bez tokenu, ale jen embed HTML | MVP: oEmbed + screenshot |

## Rozhodnutí Olina (12. 11. 2026)

1. **User-Agent bota:** `DeepFakeBot/0.1 (+https://github.com/lioilsources/DeepFakes)` (žádný osobní kontakt; kontakt = issues repa).
2. **Brave rozpočet:** 5 $ kreditu/měsíc ≈ 1000 dotazů ≈ 30–50 ověřených článků stačí na pilot; strop pro veřejné spuštění rozhodnout před M7. (otevřené)
3. **Fact-checkeři:** napsat Demagog.cz, Demagog.sk a Manipulátorům o strojový feed/souhlas před M2. (otevřené)

---

Legenda: **ověřeno 2026-11-12** = ověřeno v této rešerši na uvedené URL (oficiální stránka nebo citovaný zdroj). **neověřeno** = nedohledáno, zdroje si odporují nebo jde jen o sekundární zdroj či obecně známý stav, který nebyl v této session znovu ověřen.
Doporučení: **MVP** / **později** / **vyhnout se**. Licenční sloupce: (a) uložit krátký úryvek + odkaz, (b) použití ve free veřejné appce, (c) komerční využití později. Nejde o právní radu.

---

## 1. Existující fact-checky

| Zdroj | Stav 2026 | Přístup | Auth / kvóta / cena | Licence (a/b/c) | Doporučení | Zdroj / ověření |
|---|---|---|---|---|---|---|
| Google Fact Check Tools API (`claims:search`, `imageSearch`) | Endpoint `v1alpha1/claims:search` je stále zdokumentovaný, deprecation notice jsem nenašel. **Google ale v červnu 2025 přestal zobrazovat ClaimReview snippety ve vyhledávání** (Fact Check Explorer zůstává). Hrozí, že vydavatelé přestanou ClaimReview udržovat. | REST API | API klíč (Google Cloud). Kvóta na stránce neuvedena (neověřeno). | Google API ToS. Obsah ClaimReview patří vydavatelům fact-checků: (a) krátký úryvek + odkaz je obvyklá praxe, (b) ano, (c) dle Google API ToS, neověřeno. | **MVP** (levné, multijazyčné), ale nespoléhat jen na něj | https://developers.google.com/fact-check/tools/api · https://developers.google.com/fact-check/tools/api/reference/rest · https://www.niemanlab.org/2025/06/google-kills-the-fact-checking-snippet/ · https://www.poynter.org/ifcn/2025/google-claimreview-fact-checks-snippets-removed/ — ověřeno 2026-11-12 |
| Dump ClaimReview (Data Commons) | Stará URL `datacommons.org/factcheck/download` přesměrovává (301) na `toolbox.google.com/factcheck`, kde **žádný dump není**. Veřejný bulk dump tedy prakticky zanikl. | — | — | Data z ClaimReview Read/Write API podle Google „přispívají do dataCommons“. AVeriTeC uvádí, že Claim Search data jsou pod CC-BY-4.0 (neověřeno). | **Vyhnout se** (neexistuje); místo toho MultiClaim (viz §6) | https://www.datacommons.org/factcheck/download → https://toolbox.google.com/factcheck — ověřeno 2026-11-12 |
| Demagog.cz | Aktivní, poslední článek 10. 11. 2026. Ověřený člen EFCSN (aktualizace 1. 4. 2026). IFCN odznak byl „under renewal“. | Jen web (scrape, případně ClaimReview přes Google API). API ani export není uveden. | — | Licence na webu neuvedena (neověřeno). Polský Demagog (jiný subjekt) používá CC BY-SA / BY-NC-SA. (a) úryvek + odkaz je rozumné, (b)(c) **dohodnout se** | **MVP** přes Google API + odkaz; o feed požádat přímo | https://demagog.cz/ · https://members.efcsn.com/organization/demagog-cz · https://mail.ifcncodeofprinciples.poynter.org/profile/demagogcz — ověřeno 2026-11-12 |
| Manipulátoři.cz (+ Faktické.info) | Aktivní, článek z 12. 11. 2026. (Spolek Manipulatori.cz z.s. je v rejstříku „v likvidaci“ od 2023; web běží, nejasná právní forma.) | **RSS** `manipulatori.cz/feed/`, `fakticke.info/feed/` | zdarma | „Všechna práva vyhrazena“: (a) jen titulek, krátký úryvek a odkaz, (b) dtto, (c) dohoda | **MVP** (RSS, ukládat jen metadata + odkaz) | https://manipulatori.cz/ · https://www.podnikatel.cz/rejstrik/manipulatori-cz-z-s-07815964/ — ověřeno 2026-11-12 |
| AFP Fact Check / AFP Na pravou míru (CZ) | Česká verze se uvádí na `napravoumiru.afp.com` (doména neověřena), anglická na `factcheck.afp.com`. AFP v ČR dělá fact-checking pro Metu od 2020. | Web, ClaimReview přes Google API | — | AFP obsah je komerční (agentura): jen odkaz + titulek | **MVP** přes Google API | https://www.seznamzpravy.cz/clanek/fakta-myty-pod-lupou-rozhodnuti-ustavniho-soudu-ze-nemusite-predkladat-ockovani-je-podvrh-186771 — částečně ověřeno; doména neověřeno |
| Demagog.sk | Aktivní (12. 11. 2026), IFCN + EFCSN, signatář EU Code of Practice | Web, ClaimReview přes Google API | — | Licence neuvedena (© 2026) | **MVP** přes Google API | https://demagog.sk/ · https://disinfocode.eu/signatories/demagogsk — ověřeno 2026-11-12 |
| EDMO (fact-checking repository) | EDMO centrální činnost dostala 2,5 mil. € pokračování (březen 2026). Repozitář je webový nástroj s vyhledáváním odkazů na fact-checky. | Web. Veřejné API nenalezeno (Truly Media má REST jen pro autentizované partnery). | — | neověřeno | **Později** (dotaz na partnerství) | https://edmo.eu/edmo-news/edmo-launches-new-fact-checking-repository/ · https://ieu-monitoring.com/editorial/eu-commission-adopts-funding-of-digital-media-observatory-activities/893473/ — ověřeno 2026-11-12 |
| CEDMO | **Riziko:** hlavní EU grant (CEDMO 2.0, UK) běží jen do **října 2026** a národní granty z NPO skončily 12/2025 a 4/2026. Pokračování jsem nedohledal. Fact-check archiv je na webu. | Web `cedmohub.eu/fact-checking/archives` | — | neověřeno | **Později**; ověřit, zda projekt běží | https://wiki.ufal.ms.mff.cuni.cz/_media/user:hladka:cedmo_2.0_ufal_for_ufal_semptember_15_2025.pdf · https://cedmohub.eu/fact-checking/archives — financování ověřeno 2026-11-12, aktuální provoz neověřeno |
| IFCN signatáři | 163 aktivních ověřených + 22 v obnově (březen 2026). Seznam se načítá dynamicky, export není. | Web (JS) | — | — | **MVP** jen jako ruční seed whitelistu fact-checkerů (spolu s EFCSN) | https://ifcncodeofprinciples.poynter.org/signatories · https://disinfocode.eu/reports/demagogcz/8/text — ověřeno 2026-11-12 |

## 2. Vyhledávání důkazů

| Služba | Stav 2026 | Cena / kvóta | Ukládání výsledků | Doporučení | Zdroj / ověření |
|---|---|---|---|---|---|
| **Brave Search API** | **Free tier zrušen (únor 2026).** Teď jsou předplacené kredity: Search 5 $/1000 dotazů (50 QPS), Answers 4 $/1000 + 5 $/M tokenů. Měsíčně 5 $ kreditu zdarma (≈1000 dotazů), podle Implicatoru podmíněno veřejnou atribucí Brave. | viz vlevo | **Ukládat nebo trénovat jen s custom plánem „storage rights“ (kontaktovat sales).** Standardní plán ukládání nedovoluje. | **MVP** (jen live dotazy, neukládat SERP; ukládat jen URL, které si stáhneme sami) | https://brave.com/search/api/ · https://www.implicator.ai/brave-drops-free-search-api-tier-puts-all-developers-on-metered-billing/ — ověřeno 2026-11-12 |
| Bing Search API | **Vypnuto 11. 8. 2025**, instance zrušeny. Náhrada „Grounding with Bing“ jen v Azure AI Agents a bez přístupu k surovým výsledkům. | — | — | **Vyhnout se** | https://learn.microsoft.com/en-us/lifecycle/announcements/bing-search-api-retirement — ověřeno 2026-11-12 |
| Tavily | Funguje, **od 2026 patří Nebius** (oznámeno 10. 2. 2026). Free 1000 kreditů/měs., PAYG 0,008 $/kredit, Project 30 $/4000. | viz vlevo | ToS ohledně ukládání neověřeno | **Později** / záloha | https://www.tavily.com/pricing · https://futurumgroup.com/insights/does-nebius-acquisition-of-tavily-create-the-leading-agentic-cloud/ — ověřeno 2026-11-12 |
| Exa | Funguje. 4 $/1000 (lite/instant), 7 $ (auto/fast), 12–15 $ (deep). Free 10 $ kreditu měsíčně. | viz vlevo | Podmínky ukládání na ceníku nejsou (neověřeno) | **Později** (dobré na sémantické hledání) | https://exa.ai/pricing — ověřeno 2026-11-12 |
| Kagi Search API | **Stále closed beta** (jen Team plán na pozvání). Ceny si odporují: 2,5 ¢/dotaz vs 12 $/1000. | 19 $/měs + dotazy | neověřeno | **Vyhnout se** v MVP | https://help.kagi.com/kagi/api/search.html · https://kagi.com/api/pricing — ověřeno 2026-11-12 |
| Mojeek API | Funguje, vlastní index, cena jen na vyžádání (POA) | POA | neověřeno | **Později** (nezávislý EU-friendly index) | https://www.mojeek.com/services/search/web-search-api/ — ověřeno 2026-11-12 |
| SearXNG (self-host) | Open-source metavyhledávač (AGPL). Scrapuje Google, Bing a další, takže porušuje jejich ToS a hrozí blokace IP. | zdarma | Riziko ToS upstreamů | **Později** jen pro interní dev nebo testy | https://docs.searxng.org/ — neověřeno |
| GDELT DOC 2.0 API / GKG | Funguje bez klíče. Limit ~1 dotaz / 5 s (jinak HTTP 429), max 250 článků na dotaz, okno 3 měsíce u článkových režimů. GKG a raw soubory jdou stahovat ve 15min dávkách. | zdarma | **Volné i komerční užití a redistribuce, s citací a odkazem na gdeltproject.org** | **MVP** (objevování článků + tone/GKG jako benchmark pro „teplotu“) | https://www.gdeltproject.org/about.html · https://blog.gdeltproject.org/?p=15416 — licence ověřeno 2026-11-12, rate limit jen sekundárně (neověřeno) |
| Wikipedia / Wikimedia API | **Od 2026 globální rate limity:** neidentifikovaný klient 10 req/min, bot s User-Agentem podle policy 200/min, přihlášený 200 až 2000/min. Pro komerční velkoodběr je Wikimedia Enterprise. | zdarma | Text CC BY-SA 4.0 (atribuce + share-alike u úryvků) | **MVP** (nastavit korektní User-Agent s kontaktem, nebo použít dumpy) | https://www.mediawiki.org/wiki/Wikimedia_APIs/Rate_limits — ověřeno 2026-11-12. Licence: https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use — neověřeno |
| Wikidata | SPARQL + REST | zdarma (stejné limity) | CC0 | **MVP** (entity, fakta) | https://www.wikidata.org/wiki/Wikidata:Licensing — neověřeno |

## 3. Primární data

| Zdroj | Přístup | Auth | Licence / podmínky | Doporučení | Zdroj / ověření |
|---|---|---|---|---|---|
| ČSÚ: **DataStat** (data.csu.gov.cz) | API pro data i metadata, katalog open-data API, přímé CSV a JSON. **VDB končí koncem 2026.** | bez klíče (neověřeno) | open data ČSÚ, licence neověřena | **MVP**, rovnou na DataStat API, ne na VDB | https://csu.gov.cz/produkty/datastat-postupne-nahrazuje-verejnou-databazi · https://data.csu.gov.cz/opendata/katalog — ověřeno 2026-11-12 |
| Eurostat API | Statistics API (JSON-stat 2.0), SDMX 2.1 a 3.0, Catalogue API. Aktualizace 2× denně. | bez klíče, zdarma | Volné opakované užití s atribucí (Rozhodnutí 2011/833/EU), na stránce API přímo neuvedeno | **MVP** | https://ec.europa.eu/eurostat/web/user-guides/data-browser/api-data-access/api-introduction — ověřeno 2026-11-12; licence neověřeno |
| data.gov.cz (NKOD) SPARQL | Virtuoso endpoint `data.gov.cz/sparql` běží | bez klíče | podmínky ani limity neuvedeny | **MVP** pro hledání datových sad | https://data.gov.cz/sparql — ověřeno 2026-11-12 |
| Hlídač státu API (+ MCP server) | REST API a MCP server, jen pro registrované uživatele | API token nebo OAuth po registraci | Některé datasety jsou jen pro role (novinář, admin) s **komerční licencí**. Obecné podmínky jsem nedohledal (stránka `/api` vrací 401). | **Později** (napsat jim o podmínkách; pro smlouvy použít přímo Registr smluv) | https://mcp.api.hlidacstatu.cz/doc · https://www.hlidacstatu.cz/Data — částečně ověřeno; licence neověřeno |
| PSP ČR: hlasování (open data) | ZIP s UNL formátem (oddělovač `\|`, windows-1250), denně plný stav. Hlasování 1.–10. volební období, dále tisky, stenozáznamy, interpelace. | bez auth | **Zdarma, podmínkou je uvést zdroj** (a datum zpracování) | **MVP** (výroky politiků vs. hlasování) | https://www.psp.cz/sqw/hp.sqw?k=1300 — ověřeno 2026-11-12 |
| Registr smluv | Měsíční XML dumpy `dump_YYYY_MM.xml` + `index.xml` na `data.smlouvy.gov.cz`. Aktuální měsíc se generuje denně. | bez auth | Open data (rámec opendata.gov.cz). **Obsahuje osobní údaje: kdo dataset převezme, stává se správcem dle GDPR.** | **Později** | https://smlouvy.gov.cz/stranka/otevrena-data · https://data.smlouvy.gov.cz/ — ověřeno 2026-11-12 |
| WHO GHO OData API | **WHO ohlásila deprecaci současného GHO OData API ke konci 2025** a nahrazuje ho novou OData implementací. Staré Athena/Minerva jsou vypnuté. Nástupce se uvádí jako `xmart-api-public.who.int` (jen sekundární zdroj). | bez klíče | WHO data obvykle CC BY-NC-SA 3.0 IGO, tj. **nekomerční** (neověřeno) | **Později**; před použitím ověřit endpoint | https://www.who.int/data/gho/legacy · https://who.int/data/gho/info/gho-odata-api — ověřeno 2026-11-12; nástupce a licence neověřeno |
| ECDC data | Stahovatelné datasety, dashboardy, ERVISS. API na stránce není. | — | Open data policy + copyright stránka (podmínky neověřeny) | **Později** | https://www.ecdc.europa.eu/en/data — ověřeno 2026-11-12 |

## 4. Zpravodajské agentury

| Agentura | Strojový přístup | Cena | Poznámka | Doporučení | Zdroj / ověření |
|---|---|---|---|---|---|
| ČTK | Veřejné developer API ani ceník jsem nenašel. Licence se sjednává individuálně (např. ČNB platí 45 485 Kč/měs.). ČTK aktivně vymáhá práva k fotkám. | individuálně | Pro free appku nedostupné | **Jen přes veřejné weby** (odkaz na články, které ČTK přebírají) | https://ezak.cnb.cz/document_21505/08e7e019cf808eaf0279e0a9d5b5bb2e-pisemna-zprava-zadavatele-konverze-pdf · https://www.mediaguru.cz/clanky/2025/03/pouziti-svych-fotek-ctk-hlida-ma-z-toho-i-financni-prijem/ — ověřeno 2026-11-12 |
| Reuters | Reuters Connect (REST, B2B), archiv od 1987 přes Snowflake Marketplace (licencováno). „Reuters News API“ na marketplacech jsou neoficiální wrappery. | enterprise, šestimístné dealy | Živé feedy do AI licencí nedávají | **Jen přes veřejné weby** | https://mediacopilot.ai/reuters-snowflake-marketplace-ai-licensing/ · https://pressgazette.co.uk/publishers/wires_and_agencies/thomson-reuters-boss-says-ai-licensing-deals-only-involve-archive-text/ — ověřeno 2026-11-12 (sekundární) |
| AP | AP Media API (developer.ap.org) jen pro licencované zákazníky | individuálně | — | **Jen přes veřejné weby** | https://developer.ap.org/ap-media-api — neověřeno (ceník neveřejný) |

## 5. Registr zdrojů (seed hodnocení médií)

| Zdroj | Stav | Přístup | Licence | Doporučení | Zdroj / ověření |
|---|---|---|---|---|---|
| NFNZ **MediaRating** (dříve Rating NFNZ) + Mapa médií | Funguje, veřejná metodika, ale hodnocení je **kontroverzní** (spory s médii, kritika vazby se Seznamem). | Web | Licence pro převzetí neověřena | **Později**, jen jako jeden ze signálů a s atribucí; ideálně dohoda s NFNZ | https://www.mediaguru.cz/evropske-nastroje-pro-mereni-medii-mediarating-chce-za-hranice · https://www.mediaguru.cz/rating-nfnz — ověřeno 2026-11-12 (sekundární) |
| Konšpirátori.sk | Aktivní (~10 let), databáze SK a CZ webů, provozuje o.z. Konšpirátori.sk. **Opakované soudní spory se zařazenými weby** (napr. AC24, Konšpirátori vyhráli počtvrté). | Web (seznam), API ani export není | **Licence ani podmínky převzetí seznamu neuvedeny**, tj. pro převzetí je nutný souhlas | **Později**: jen s písemným souhlasem; jinak zobrazovat „uvedeno na Konspiratori.sk“ s odkazem | https://konspiratori.sk/ · https://sita.sk/konspiratori-sk-uspeli-na-sude-uz-po-stvrtykrat-cesky-web-ac24-ostane-na-zozname-problematickych-stranok/ — ověřeno 2026-11-12; licence neověřeno |
| Media Bias/Fact Check (MBFC) | Funguje. Data API přes RapidAPI (jen nekomerční, test, výzkum, s atribucí) nebo **přímá komerční licence** (cena na dotaz). Pokrytí CZ médií slabé (neověřeno). | RapidAPI / přímo | RapidAPI: zákaz redistribuce, client-facing komerčních produktů a velkých objemů | **Vyhnout se** v MVP (veřejná appka = „client-facing“) | https://mediabiasfactcheck.com/mbfcs-data-api/ — ověřeno 2026-11-12 |
| NewsGuard | Placená licence (B2B) | — | — | **Vyhnout se** | https://www.newsguardtech.com/ — neověřeno |
| Evropské hodnoty (BCEH): seznam dezinformačních webů | Výroční analýzy (např. 39 aktivních webů v roce 2022). Kritika za nezveřejněnou metodiku. Semantic Visions spoluautorství seznamu nepotvrzeno. Aktuální verze 2026 nenalezena. | PDF zprávy | neověřeno | **Později**, jen jako citovaný signál | https://www.mediaguru.cz/bceh-pocet-dezinformacnich-webu-i-clanku-v-cesku-loni-klesl — ověřeno 2026-11-12 (sekundární) |

## 6. Datasety pro trénink a evaluaci

| Dataset | Obsah / jazyky | Přístup | Licence | Komerčně? | Zdroj / ověření |
|---|---|---|---|---|---|
| SemEval-2020 Task 11 (PTC) | Propagandistické techniky, EN | registrace na PTC | HF uvádí „unknown“ | ne / neověřeno | https://huggingface.co/datasets/SemEvalWorkshop/sem_eval_2020_task_11 — ověřeno 2026-11-12 |
| SemEval-2023 Task 3 | 23 persvazivních technik, EN, FR, DE, IT, **PL, RU** (+ ES, EL, KA jen test). **Bez češtiny.** | registrace, ruční schválení, passcode | **Jen vědecký výzkum v kontextu tasku, zákaz redistribuce** | **ne** | https://propaganda.math.unipd.it/semeval2023task3/ — ověřeno 2026-11-12 |
| SemEval-2024 Task 4 | Persvaze v memech, EN (10k) + BG, MK, AR (test) | registrace | neověřeno (pravděpodobně podobné jako 2023) | neověřeno | https://aclanthology.org/2024.semeval-1.275 — ověřeno 2026-11-12, licence neověřeno |
| GoEmotions | 27 emocí, EN Reddit | GitHub, HF | HF karta: Apache 2.0 (TFDS: „no known license“) | pravděpodobně ano (neověřeno) | https://huggingface.co/datasets/google-research-datasets/go_emotions — ověřeno 2026-11-12 |
| CZ sentiment (ČSFD, Facebook, Mall.cz; Habernal a kol. 2013, ZČU) | CZ sentiment | volně ke stažení | **CC BY-NC-SA** (4.0 dle ZČU, 3.0 dle jiných) | **ne** | https://corpora.kiv.zcu.cz/sentiment/ — ověřeno 2026-11-12 |
| FEVER | EN claim verification nad Wikipedií | volně | Wikipedia (CC BY-SA 3.0), metadata HF si odporují | s podmínkami SA | https://huggingface.co/datasets/fever/fever — ověřeno 2026-11-12 |
| **CsFEVER / CsFEVERv2** (CTU AIC) | CZ FEVER | HF `ctu-aic/csfever`, `csfever_v2` | **CC BY-SA 3.0** | ano (s atribucí a SA) | https://huggingface.co/datasets/ctu-aic/csfever_v2 · https://arxiv.org/abs/2201.11115 — ověřeno 2026-11-12 |
| **CTKFacts** (CTU AIC) | CZ claimy nad korpusem ČTK | HF `ctu-aic/ctkfacts`, `ctkfacts_nli` | CC BY-SA 3.0 na kartě, ale **korpus ČTK má omezenou licenci** (proto zveřejnili NLI verze) | ověřit u NLI verze | https://huggingface.co/datasets/ctu-aic/ctkfacts — ověřeno 2026-11-12; NLI licence neověřeno |
| AVeriTeC (2024) + shared task 2025 (FEVER @ ACL 2025) | Reálné claimy s evidencí, test 2025 = 1000 instancí. Vyhrál CTU AIC. | GitHub, HF | **CC BY-NC 4.0** | **ne** | https://arxiv.org/pdf/2410.23850 · https://preview.aclanthology.org/landing_page/2025.fever-1.pdf — ověřeno 2026-11-12 |
| **MultiClaim v1/v2** (KInIT) | v2: 435k fact-checků, 89k postů, 105k párů, desítky jazyků (vč. CS a SK) | **Zenodo, restricted, na žádost** | **Jen výzkum**, atribuce k původním URL fact-checků | **ne** | https://zenodo.org/records/15413169 · https://zenodo.org/record/7737983 — ověřeno 2026-11-12 |
| MultiClaimNet | Clustery claimů, 78 jazyků | Zenodo, restricted | výzkum | ne | https://zenodo.org/records/15100352 — ověřeno 2026-11-12 |
| CEDMO datasety | — | — | nenalezeno | — | neověřeno |
| FaceForensics++ | Videa s manipulací tváří | formulář / podepsaný ToS | **Jen nekomerční výzkum a vzdělávání** | **ne** | https://kaldir.vc.in.tum.de/faceforensics_tos.pdf — ověřeno 2026-11-12 |
| DFDC (Meta) | Deepfake videa | žádost + DFDC ToS | nekomerční výzkum (jen sekundární zdroj) | ne (neověřeno) | https://ai.meta.com/datasets/dfdc/ — neověřeno |
| GenImage | AI obrázky (8 generátorů) | GitHub | **CC BY-NC-SA 4.0** + další podmínky | **ne** | https://github.com/GenImage-Dataset/GenImage — ověřeno 2026-11-12 (přes mirror) |
| Chameleon (AIDE) | Obrázky, které prošly lidským „Turing testem“ | e-mail autorům | **Jen akademický výzkum, zákaz komerce** (sekundární) | ne | https://arxiv.org/abs/2406.19435 — neověřeno (licence ze sekundárního zdroje) |
| WildFake | AI obrázky „in the wild“ | ohlášeno vydání | licence nenalezena | ? | https://arxiv.org/abs/2402.11843 — neověřeno |
| Community Forensics (OwensLab) | 2,7M obrázků z 4800+ generátorů | HF | CC BY-4.0 „for research purposes only“. Eval split CC BY-NC-SA 4.0. Obrázky nesou licence generátorů (většinou OpenRAIL-M). | spíš ne | https://huggingface.co/datasets/OwensLab/CommunityForensics — ověřeno 2026-11-12 |
| OpenFake (2025) | ~4M obrázků (3M reálných, 963k syntetických) | HF | HF pole: **CC BY-NC 4.0** (karta jinde uvádí BY-SA nebo BY-NC-SA). Proprietární generátory mají non-compete. | **ne** | https://huggingface.co/datasets/ComplexDataLab/OpenFake — ověřeno 2026-11-12 |
| Deepfake-Eval-2024 (TrueMedia) | In-the-wild video, audio, obrázky z roku 2024 | HF gated (instituční e-mail), **otevřené od května 2027** | CC BY-SA 4.0 | ano s SA (odpovědnost na uživateli) | https://arxiv.org/abs/2503.02857 — ověřeno 2026-11-12 |

## 7. Crawling a TDM (fakta, ne právní rada)

| Téma | Fakta | Zdroj / ověření |
|---|---|---|
| DSM směrnice čl. 3 / čl. 4 | Čl. 3: TDM pro výzkumné organizace (nelze vyloučit). Čl. 4: obecná TDM výjimka pro kohokoli, ale nositel práv si ji může vyhradit „strojově čitelným způsobem“ (u online obsahu). Pravděpodobně se týká i nekomerčního projektu, který není výzkumnou organizací. | https://eur-lex.europa.eu/eli/dir/2019/790/oj — neověřeno (text směrnice znám, nefetchnut) |
| Kneschke v. LAION | OLG Hamburg (5 U 104/24, 10. 12. 2025): výhrada v běžném jazyce v ToS nebyla prokázána jako strojově čitelná pro rok 2021; rozhoduje technologie v době užití. **BGH (I ZR 281/25) ohlásil rozhodnutí na 17. 12. 2026**, termín jen ze sekundárního zdroje. | https://cm.twobirds.com/en/insights/2025/germany/higher-regional-court-hamburg-confirms-ai-training-was-permitted-(kneschke-v,-d-,-laion) · https://www.photoworkout.com/?p=223770 — ověřeno 2026-11-12 (BGH datum neověřeno) |
| TDMRep (W3C CG) | `tdm-reservation: 1` přes `/.well-known/tdmrep.json`, HTTP hlavičku (preferovaná) nebo `<meta>`. Volitelně `tdm-policy`. Final CG Report 10. 5. 2024, **není W3C standard**. | https://www.w3.org/community/reports/tdmrep/CG-FINAL-tdmrep-20240510/ — ověřeno 2026-11-12 |
| IETF AIPREF | Slovník (`draft-ietf-aipref-vocab`, -06 až -08 v roce 2026) + pravidlo `Content-Usage` v robots.txt a HTTP hlavičce (attach draft, stav nejasný). ai.txt je jen individuální draft. | https://www.ietf.org/archive/id/draft-ietf-aipref-vocab-06.html · https://datatracker.ietf.org/doc/draft-ietf-aipref-attach/ — ověřeno 2026-11-12 (stav attach neověřeno) |
| CZ právo vydavatelů tisku (čl. 15 DSM) | Novela AZ 429/2022 Sb. (účinná 1. 1. 2023) zavedla právo vydavatele tiskových publikací (**§ 87b**). Podle sekundárního zdroje se nevztahuje na jednotlivá slova, **velmi krátké úryvky** a hypertextové odkazy. Cílí na poskytovatele služeb informační společnosti. MK vydává sazebník SLPV na 2026. | https://www.epravo.cz/top/zakony/sbirka-zakonu/sb/2022/429 · https://www.lupa.cz/clanky/co-je-velmi-kratky-uryvek-novela-autorskeho-zakona-s-novymi-pravy-pro-vydavatele-je-ve-snemovne/ · https://www.mk.gov.cz/doc/cms_library/sazebnik-slpv-na-rok-2026-21373.doc — ověřeno 2026-11-12 (přesné znění § 87b neověřeno) |
| Praktický důsledek pro denní crawl (fakta) | Respektovat robots.txt, TDMRep hlavičky a meta a AIPREF `Content-Usage`. Ukládat jen metriky, velmi krátké citace a odkaz. Identifikovat se User-Agentem s kontaktem (Wikimedia to už vyžaduje kvůli limitům). | viz řádky výše |

---

### Shrnutí doporučení pro MVP
- **Fact-checky:** Google Fact Check API (s vědomím rizika po konci ClaimReview snippetů) + RSS Manipulátoři a Faktické.info + odkazy na Demagog.cz, Demagog.sk a AFP. Whitelist podle IFCN a EFCSN.
- **Důkazy:** Brave (jen live, neukládat SERP), GDELT (volná licence), Wikipedia a Wikidata (User-Agent!), Exa nebo Tavily jako záloha.
- **Primární data:** DataStat ČSÚ (ne VDB), Eurostat, PSP open data, NKOD SPARQL.
- **Eval:** CsFEVER a CTKFacts (CC BY-SA). Většina propaganda a deepfake datasetů je **jen výzkumná nebo NC**, takže pro pozdější komerci je nepoužívat k tréninku produkčních modelů.

---

### Příloha: Čtení veřejných příspěvků ze sociálních sítí — desk research (stav k 2026-11-12)

Kontext: bezplatná, zatím nekomerční mobilní aplikace na ověřování faktů. Po MVP chce z URL, které uživatel sdílí, načíst text, autora, čas, média a kontext vlákna, a to přes oficiální API.

Legenda:
- **ověřeno 2026-11-12**: oficiální dokumentace přečtena dnes, nebo endpoint dnes otestován přes `curl`.
- **částečně**: jen sekundární zdroje, nebo oficiální stránka nešla načíst.
- **neověřeno**: vychází z dřívějších znalostí, dnes nekontrolováno.

### Souhrnná tabulka

| Platforma | Čtení 1 příspěvku podle URL/ID | Autentizace | Cena / kvóta | Média | oEmbed bez auth | Priorita po MVP |
|---|---|---|---|---|---|---|
| **Bluesky** | ano, `getPostThread` (celé vlákno) | žádná (public AppView) | zdarma, rate limit | ano (CDN odkazy) | n/a, API je veřejné | **1** |
| **Mastodon** | ano, `/api/v1/statuses/:id` + `/context` | žádná u veřejných (záleží na instanci) | zdarma, limit dle instance | ano (URL příloh) | ano (`/api/oembed`) | **2** |
| **YouTube** | ano, `videos.list` (1 unit) | API klíč | 10 000 units/den zdarma | metadata a náhled ano, video ne; titulky jen vlastník | **ano**, ověřeno | **3** |
| **X/Twitter** | ano, `GET /2/tweets/:id` | app token (Bearer) | pay-per-use 0,005 USD/post, strop 3 mil./měs. | URL médií ano | **ano**, vrací text, autora a datum | **4** (oEmbed hned, API placené) |
| **Telegram** | veřejný kanál: náhled `t.me/s/<kanál>`, `t.me/<kanál>/<id>?embed=1`; MTProto | Bot API: bot musí být členem; MTProto: uživatelský účet + `api_id` | zdarma | MTProto ano; Bot API do 20 MB | widget, ne oEmbed | **5** |
| **Facebook / Instagram** | jen oEmbed (embed HTML); Graph API cizí posty nečte | od 15. 6. 2026 bez tokenu | zdarma, limity neuvedeny | ne (jen embed) | **ano**, ověřeno | **6** (jen embed + screenshot) |
| **Threads** | `profile_posts`, keyword search; podle URL jen oEmbed | OAuth uživatele + App Review | zdarma, limity | u schválených ano | **ano** (tokenless) | 7 |
| **TikTok** | oEmbed jen s HTML přehrávače; Research API není pro nás | Research API: akademici / neziskovky po schválení | — | ne | ano, ale bez titulku a autora | 8 |
| **Reddit** | dnes OAuth `/api/info`, **veřejné Data API končí v březnu 2027** | OAuth | nové žádosti se od 31. 10. 2026 nepřijímají | — | neověřeno | **nestavět** |
| **LinkedIn** | ne (jen vlastní/partnerský obsah) | partner programy | — | — | embed jen ručně | **ne** |
| **EU DSA čl. 40** | jen pro prověřené výzkumníky (vetted researchers) | DSC vetting | — | — | — | **nepoužitelné** pro aplikaci |

Doporučené pořadí po MVP:
1. Bluesky
2. Mastodon
3. YouTube (metadata)
4. X: nejdřív oEmbed zdarma, placené API až při potřebě médií a vláken
5. Telegram (veřejné kanály)
6. Meta oEmbed s fallbackem na screenshot

Ostatní platformy pokryje **jen screenshot**.

---

### Poznámky k platformám

### X / Twitter — ověřeno 2026-11-12
- **Cena:** od 6. 2. 2026 je výchozí model **pay-per-use** s kredity v Developer Console, bez předplatného a bez minima. Ceny:
  - čtení postu **0,005 USD** za vrácený post
  - čtení uživatele **0,010 USD**
  - **Strop je 3 mil. přečtených postů za měsíc**, nad ním Enterprise.
- **Deduplikace:** stejný resource se ve 24h okně (UTC) účtuje jen jednou. Dokumentace to označuje za „soft guarantee“.
- **Free tier** pro nové vývojáře zanikl. Osud starých tarifů Basic/Pro se ve zdrojích liší (částečně).
- **Autentizace:** pro čtení veřejného postu stačí app-only Bearer token. Média, autor, `created_at` a `conversation_id` jdou přes `expansions`.
- **oEmbed bez autentizace funguje** (`publish.x.com/oembed?url=…`, dnes otestováno). Vrací `author_name` a HTML blockquote s **plným textem a datem**. Pro MVP zdarma tedy stačí na text, autora a datum, ne na média a vlákno.
- **ToS:** Developer Agreement od 6/2025 zakazuje použít obsah X k tréninku nebo fine-tuningu foundation modelů. Platí povinnost respektovat smazání (compliance). Ukládej jen ID a případné cache maž.
- Stránku s policy (developer.x.com) se dnes načíst nepodařilo (HTTP 402).
- Zdroje:
  - https://docs.x.com/x-api/getting-started/pricing
  - https://opentermsarchive.org/en/memos/x-replaces-its-dollar200-entry-level-api-plan-with-a-pay-per-use-model/
  - https://techcrunch.com/2025/06/05/x-changes-its-terms-to-bar-training-of-ai-models-using-its-content

### YouTube Data API v3 — ověřeno 2026-11-12
- **Kvóty:** `videos.list` stojí 1 unit a vezme až 50 ID. Výchozí kvóta je 10 000 units/den, reset o půlnoci pacifického času. Navýšení se žádá přes audit formulář.
- **Autentizace:** stačí API klíč.
- **Titulky:** `captions.download` stojí 200 units a vyžaduje OAuth (`youtube.force-ssl`). Uživatel navíc **musí mít práva editovat video**, takže titulky cizích videí oficiálně stáhnout nejdou. `captions.list` (50 units) vrátí jen seznam stop.
- **Neoficiální `timedtext` a „transcript“ knihovny** jsou mimo API a v rozporu s YouTube API Services ToS. Nepoužívat.
- **Média:** video soubor API nedává (stahování zakazuje ToS). Náhledy (`thumbnails`) dostupné jsou.
- **oEmbed bez autentizace funguje** (title, author_name, thumbnail; otestováno).
- **ToS (neověřeno dnes):** YouTube API Services Developer Policies omezují dobu uložení dat API (obnova nebo smazání po 30 dnech).
- Zdroje:
  - https://developers.google.com/youtube/v3/determine_quota_cost
  - https://developers.google.com/youtube/v3/docs/captions/download
  - https://developers.google.com/youtube/terms/developer-policies (neověřeno)

### Bluesky (AT Protocol) — ověřeno 2026-11-12
- **Čtení:** `https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread?uri=at://…` funguje **bez autentizace**, dnes vrátil HTTP 200 s autorem, textem, `createdAt` a vláknem.
- **Převod URL na AT URI:** z `bsky.app/profile/<handle>/post/<rkey>` se handle převede na DID přes `com.atproto.identity.resolveHandle`.
- **Média:** obrázky a video jsou na `cdn.bsky.app` / `video.bsky.app` (odkazy v `embed`). Lze je stáhnout.
- **Jetstream** je zjednodušený JSON firehose přes WebSocket. Pro dotazy podle URL ho nepotřebujeme, hodí se jen pro monitoring.
- **ToS:** obsah je veřejný protokol. Respektovat labely a smazání. Rate limity AppView jsou velkorysé, přesná čísla dnes nedohledána (částečně).
- Zdroje:
  - https://docs.bsky.app/ (přesměrováno na https://bsky.network/docs/…)
  - https://endpoints.bsky.app/

### Mastodon — ověřeno 2026-11-12
- **Čtení:** `GET /api/v1/statuses/:id` je pro veřejné statusy veřejné, bez tokenu (od 2.7.0).
- **Vlákno:** `/context` bez autentizace vrací max. 40 předků a 60 potomků, hloubku 20 (od 4.0).
- **Instance v „authorized-fetch“ módu** vrací 401. Pak je potřeba OAuth token uživatele, nebo načtení přes domovskou instanci uživatele (`/api/v2/search?resolve=true`).
- **Média:** `media_attachments` s URL ke stažení.
- **oEmbed:** `/api/oembed?url=` (neověřeno dnes).
- **ToS:** každá instance má vlastní pravidla. Respektovat `noindex` a smazání.
- Zdroj: https://docs.joinmastodon.org/methods/statuses/

### Telegram — ověřeno 2026-11-12 (Bot API a t.me/s), MTProto neověřeno
- **Bot API:** bot dostává jen zprávy z kanálů, **kde je členem**. Cizí veřejný kanál podle URL nepřečte. `getFile` stáhne max. 20 MB.
- **Veřejný náhled `t.me/s/<kanál>`** funguje bez přihlášení (HTTP 200). Telegram ho sám veřejně poskytuje, embed widget je `t.me/<kanál>/<id>?embed=1`. Text, čas a náhledy médií z něj jdou číst.
  - Není to formální API, je to HTML. Je to šedá zóna, ale nejde o obcházení přihlášení.
  - Doporučení: parsovat jen jeden konkrétní post na žádost uživatele, žádný hromadný crawl.
- **MTProto / TDLib:** plný přístup k veřejným kanálům včetně médií. Potřebuje `api_id` a **přihlášený uživatelský účet** (telefonní číslo) na serveru.
  - Telegram API ToS hromadnou automatizaci uživatelských účtů omezuje.
  - Rozumné jen jako serverová služba s jedním účtem a nízkou zátěží (neověřeno).
- Zdroje:
  - https://core.telegram.org/bots/faq
  - https://core.telegram.org/api/terms (neověřeno)

### Meta: Facebook / Instagram — ověřeno 2026-11-12
- **Od 15. 6. 2026 jsou oEmbed endpointy bez tokenu a bez App Review.** Týká se Instagram oEmbed, Facebook oEmbed Post a Video a Threads oEmbed.
  - Dnes otestováno: `graph.facebook.com/v23.0/oembed_post` vrátil embed HTML bez tokenu.
  - Starší stránky features-reference ještě uvádějí App Review a business verification, jsou zastaralé.
- **Data:** oEmbed vrací **jen embed HTML** a provider info, žádný strukturovaný text, autora ani média. Meta píše, že „no personal data is shared“.
- **Graph API** cizí veřejné posty nečte. Výjimka je Page Public Content Access, vyžaduje App Review a business verifikaci (neověřeno).
- **Meta Content Library + API:** kontrolované prostředí pro výzkumníky, schvaluje ICPSR nebo CASD. Výpočty v Secure Research Environment jsou zdarma. Je pro akademické a neziskové výzkumné instituce, ne pro produkční aplikaci.
- Zdroje:
  - https://developers.facebook.com/blog/post/2026/06/15/tokenless-access-to-meta-oembed-apis/
  - https://developers.facebook.com/docs/features-reference/meta-oembed-read
  - https://developers.facebook.com/docs/content-library-and-api/

### Threads API — částečně ověřeno 2026-11-12
- **Přístup:** `threads_basic` + `threads_profile_discovery` dávají `GET /profile_lookup` a `GET /profile_posts?username=`. `threads_keyword_search` dává hledání ve veřejných postech.
- **Bez App Review (advanced access)** jen vlastní posty a testeři.
- **Post podle URL** přímo nejde. Řešení je oEmbed (tokenless), nebo dohledání přes `profile_posts`.
- **Limity** se ve zdrojích liší (např. 2 200 dotazů / 24 h u search).
- Zdroje:
  - https://developers.facebook.com/docs/threads/threads-profiles
  - https://developers.facebook.com/docs/threads/keyword-search
  - https://developers.facebook.com/docs/threads/changelog

### TikTok — ověřeno 2026-11-12 (oEmbed), Research API částečně
- **oEmbed:** `tiktok.com/oembed?url=` funguje bez autentizace, ale dnes vrací **jen** `html` (iframe přehrávače) a rozměry. Pole `title`, `author_name` ani `thumbnail_url` už nevrací. Stránka „Embed Videos“ hlásí brzké ukončení ve prospěch Embed Player.
- **Display API** vrací jen videa přihlášeného uživatele. Pro cizí obsah k ničemu.
- **Research API** je jen pro neziskový akademický nebo nezávislý výzkum (v EU též DSA-vetted), se schválením projektu. Kvóta zhruba 1 000 požadavků/den. Komerční použití vyloučeno, aplikace nesplní.
- Zdroje:
  - https://developers.tiktok.com/doc/embed-videos/
  - https://developers.tiktok.com/docs/en/research-api-faq

### Reddit — částečně ověřeno 2026-11-12 (jen sekundární zdroje, oficiální wiki vrátila 403)
- **Konec veřejného Data API:** oznámeno 30. 9. 2026 v r/redditdev a r/modnews. Harmonogram:
  - od **31. 10. 2026** se nepřijímají nové žádosti o veřejné API (fakticky od 11/2025, Responsible Builder Policy)
  - 13. 11. 2026 končí RSS
  - od 12. 1. 2027 se odpojují neregistrované aplikace
  - **v březnu 2027** veřejný přístup končí
- **Náhrada** je Devvit (aplikace uvnitř Redditu) nebo smluvní a komerční licence.
- Free tier (100 QPM přes OAuth, nekomerčně) je pro novou aplikaci prakticky nedostupný.
- **Doporučení:** nestavět, jen screenshot.
- Zdroje:
  - https://ppc.land/reddit-to-halt-public-data-api-access-in-march-2027-as-14-000-apps-register/
  - https://www.techrepublic.com/article/news-reddit-rss-public-api-shutdown/
  - https://decrypt.co/379892/reddit-killing-rss-feeds-and-public-api-access-to-fight-ai-scrapers

### LinkedIn — neověřeno
- Žádné veřejné API pro čtení cizích postů. Posts a Community Management API jsou jen pro vlastní stránky a schválené partnery.
- Scraping výslovně zakazuje User Agreement (soudní spory, hiQ).
- **Doporučení:** jen screenshot.
- Zdroj: https://learn.microsoft.com/linkedin/ (neověřeno)

### EU DSA čl. 40 — ověřeno 2026-11-12
- **Právní rámec:** delegované nařízení (EU) **2025/2050** přijato 2. 7. 2025, publikováno v OJ 9. 10. 2025, účinné od 29. 10. 2025.
- **DSA Data Access Portal** běží od 28.–29. 10. 2025.
- **Stav:** v květnu 2026 bylo podáno zhruba 50 žádostí o data a byly v posuzování. Kulatý stůl Komise a DSC s VLOP se konal 19. 5. 2026.
- **Čl. 40(4)** (neveřejná data) jen pro **prověřené výzkumníky** přidružené k výzkumné organizaci. Prověřuje je národní DSC (v ČR ČTÚ). Podmínkou je výzkum systémových rizik v EU, nekomerční účel a bezplatné zveřejnění výsledků.
- **Čl. 40(12)** (veřejná data) delegovaný akt neupravuje. Platformy ho řeší vlastními nástroji (Meta Content Library, TikTok Research API).
- **Závěr:** běžná aplikace to využít nemůže. Leda přes spolupráci s akademickým partnerem na konkrétní výzkumný projekt, ne pro produkční provoz.
- Zdroje:
  - https://eur-lex.europa.eu/eli/reg_del/2025/2050/oj/eng
  - https://digital-strategy.ec.europa.eu/en/news/commission-adopts-delegated-act-data-access-under-digital-services-act
  - https://digital-strategy.ec.europa.eu/en/news/commission-holds-roundtable-data-access-vetted-researchers
  - https://algorithmic-transparency.ec.europa.eu/news/faqs-dsa-data-access-researchers-2025-07-03_en
  - https://dsa-observatory.eu/2026/03/12/if-at-first-you-dont-succeed-reflections-on-a-rejected-art-40-dsa-data-access-request/

---

### Screenshot jako fallback

- **Uživatel pořizuje screenshot sám** a nahraje ho do aplikace: ToS platforem tím aplikace neporušuje. Platformy zakazují automatizovaný sběr, ne uživatelovo sdílení toho, co vidí (neověřeno, žádný konflikt nenalezen).
- **Pozor na:**
  - autorská práva a GDPR u ukládání: screenshoty mažte po analýze, neukládejte bez důvodu, osobní údaje třetích osob minimalizujte
  - zobrazování výsledků veřejně: citace a odkaz místo republikace celé fotky
- **Server nesmí screenshot sám generovat** headless prohlížečem za přihlášením. To už je scraping.

### Obecné pravidlo

- **Žádný scraping, který obchází přihlášení, CAPTCHA, rate limity nebo ToS:** žádné sdílené cookies, falešné účty, rotace proxy ani neoficiální interní API (např. YouTube `timedtext`, interní GraphQL X a Instagramu, `?__a=1`).
- **Povolené zdroje:**
  - oficiální API a oEmbed
  - veřejně poskytované náhledy (Telegram `t.me/s`), a to jen jednotlivě na žádost uživatele
  - obsah, který dodá sám uživatel (text, screenshot)
- **Respektovat smazání obsahu:** cache s TTL, mazání po notifikaci nebo při dalším dotazu.
- **Zákaz tréninku modelů** na datech z API (X výslovně, Meta a YouTube obdobně).
