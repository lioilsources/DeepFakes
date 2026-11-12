# PRAVDOMER_PLAN.md

Handoff plán pro Claude Code (Opus). Pracovní název: **Pravdoměr**.

## 1. Cíl

Mobilní appka (Flutter) + backend (Go) + inference na DGX Spark, která pro libovolný sdílený obsah (URL článku, příspěvek, obrázek, video) vrátí:

1. **Původ a pravost média** – je obrázek/video pravděpodobně syntetické nebo upravené? S důkazy.
2. **Teplotu** – emoční náboj a manipulativní techniky textu/obrazu, s vyznačenými pasážemi.
3. **Ověření tvrzení** – která faktická tvrzení jsou podložená, sporná nebo vyvrácená, s odkazy na zdroje.
4. **Srovnání dvou článků** na stejné téma – v čem se shodují, v čem se liší, co kdo vynechal, kdo má co podložené.

Každý výstup má: verdikt na škále, míru jistoty, vysvětlení a klikací zdroje.

## 2. Zásady (neměnit bez Ol1na)

- **Žádný verdikt bez důkazu.** Každé hodnocení nese seznam evidence (URL, citovaná pasáž, datum). Když evidence chybí, výstup je „nelze ověřit", ne odhad.
- **Hodnotíme tvrzení, ne lidi.** Appka neříká „autor X lže". Říká „tvrzení T v článku A je v rozporu se zdroji S1, S2" a „článek A má 4 nepodložená tvrzení z 9". Otázku „proč" zodpovídá jen přes doložitelné signály (vlastník média, deklarovaný střet zájmů, historie oprav), nikdy spekulací o úmyslu.
- **Deepfake detekce je pravděpodobnost, ne důkaz.** Detektory mají falešné pozitivy i negativy a stárnou s každou novou generací generátorů. V UI vždy škála + důvody, nikdy binární „FAKE".
- **Teplota ≠ nepravda.** Emotivní text může být pravdivý a klidný text lživý. Dvě nezávislé osy v UI.
- **LLM nesmí vymýšlet zdroje.** Citace jen z dokumentů, které pipeline skutečně stáhla; každá citace se strojově ověří proti uloženému textu (substring/fuzzy match), jinak se zahodí.
- Bez reklam, bez trackingu, analyzovaný obsah se neukládá déle, než je nutné pro cache.

## 3. Architektura

```
Flutter app (share sheet, výsledky, srovnání)
   │  HTTPS + SSE (průběžné výsledky)
Go API (NAS, Docker Compose, Caddy, Cloudflare Tunnel → pravdomer.ol1n.com)
   ├─ Postgres (joby, výsledky, cache dle hashe obsahu, registr zdrojů)
   ├─ fronta jobů (využít AiStack job queue, pokud sedí)
   ├─ fetcher/extractor (článek → čistý text, metadata, média)
   ├─ retrieval (web search API, fact-check API, vlastní index)
   └─ workers → DGX Spark
        ├─ LLM přes LiteLLM/vLLM (extrakce tvrzení, NLI, vysvětlení)
        ├─ klasifikátory teploty/technik (malé encoder modely)
        ├─ detektory syntetických obrázků/videa (Python workers)
        └─ ASR (přepis videa/audia)
```

Stack dle zavedeného vzoru: Go + sqlc + golang-migrate, Python workers pouze pro ML modely, Flutter frontend.

## 4. Pipeline po modulech

### 4.1 Ingest
- Vstup: URL, vložený text, obrázek, video (soubor nebo odkaz).
- Článek: stáhnout, extrahovat hlavní text (readability-style), titulek, autora, datum, vydavatele, vložená média.
- Sociální sítě: MVP = URL nebo screenshot (OCR + VLM), detaily a API po MVP viz kap. 16.
- Detekce jazyka u každého vstupu (viz kap. 14).
- Hash obsahu → cache (stejný článek se neanalyzuje dvakrát).

### 4.2 Teplota (emoce + manipulace)
Výstup per věta/odstavec i za celý dokument:
- **Emoce:** hněv, strach, znechucení, smutek, radost, překvapení, neutrální + intenzita 0–1.
- **Nabitý jazyk:** podíl hodnotících/expresivních výrazů, clickbait titulku, vykřičníky/kapitálky.
- **Manipulativní techniky** (taxonomie ze SemEval propaganda/persuasion tasks): nálepkování, strašení, falešné dilema, whataboutism, odvolání na autoritu, slamák, zveličování, opakování…
- **Skóre teploty 0–100** = vážená kombinace; váhy v konfiguraci, ne v kódu.
- Obrázky: VLM popíše emoční rámování (výraz, kompozice, text v obrázku).
- Implementace: fáze 1 LLM se strukturovaným JSON výstupem + citovanou pasáží; fáze 2 destilace do malého vícejazyčného encoderu (rychlost). Čeština je priorita – ověřit kvalitu na CZ datech.

### 4.3 Ověření tvrzení
1. **Extrakce tvrzení:** LLM vytáhne ověřitelná faktická tvrzení (kdo, co, kdy, kolik); oddělí názory a predikce (ty se neověřují, jen označí).
2. **Fact-check lookup:** hledat existující ověření (ClaimReview databáze, CZ/SK fact-checkeři).
3. **Retrieval:** pro každé tvrzení 2–3 vyhledávací dotazy, stáhnout top výsledky, upřednostnit primární zdroje.
4. **Stance/NLI:** pro každý pár tvrzení–pasáž: podporuje / vyvrací / neřeší.
5. **Agregace:** váženo důvěryhodností a nezávislostí zdrojů (5 webů přebírajících jednu agenturní zprávu = 1 zdroj).
6. **Verdikt:** podloženo / převážně podloženo / sporné / vyvráceno / nelze ověřit + jistota + citace.

### 4.4 Srovnání dvou článků
- Extrahovat tvrzení z obou, zarovnat (embedding + NLI) do: shoda / rozpor / jen v A / jen v B.
- U rozporů spustit 4.3 a ukázat, kdo má oporu ve zdrojích.
- Rozdíly rámování: teplota A vs. B, výběr citovaných osob, co kdo vynechal, titulek vs. obsah.
- Výstup: tabulka tvrzení vedle sebe + shrnutí „A: 7/9 podloženo, teplota 34; B: 3/8 podloženo, teplota 78".

### 4.5 Média (deepfake / syntetika)
Vrstvy od nejlevnější a nejspolehlivější po nejdražší:
1. **Provenance:** C2PA/Content Credentials manifest, EXIF/metadata, známé vodoznaky (pokud existuje veřejný detektor).
2. **Původ:** reverse image search + perceptuální hash (pHash) – kde a kdy se obrázek poprvé objevil, zda není vytržený z jiného kontextu (nejčastější typ dezinformace, častější než skutečný deepfake).
3. **Forenzika obrázku:** ensemble detektorů AI generování, analýza chyb komprese (ELA), nekonzistence šumu.
4. **Video:** vzorkování snímků + detektor per snímek, časová konzistence obličeje, synchronizace rtů se zvukem, detekce syntetického hlasu; ASR přepis → pipeline 4.2/4.3.
5. **VLM vysvětlení:** lidsky čitelné důvody (světlo, ruce, text v pozadí) – jen jako doplněk, ne jako hlavní signál.
- Výstup: škála „pravděpodobně autentické … pravděpodobně syntetické" + seznam signálů + upozornění na limity.

## 5. Zdroje dat

| Účel | Zdroj | Poznámka |
|---|---|---|
| Existující fact-checky | Google Fact Check Tools API (ClaimReview), Demagog.cz, Manipulátoři.cz, AFP Na pravou míru, EDMO/CEDMO | ověřit licence a možnost strojového přístupu |
| Vyhledávání evidence | web search API (Brave/jiné), GDELT (zpravodajské pokrytí), Wikipedia/Wikidata | cache výsledků |
| Primární data | ČSÚ, Eurostat, data.gov.cz, Hlídač státu, PSP hlasování, Registr smluv, WHO/ECDC | konektory po jednom |
| Agentury | ČTK, Reuters, AP | zjistit licenční podmínky; jinak jen přes veřejné weby |
| Registr zdrojů | vlastní tabulka: doména → typ, vlastník, transparentnost, historie oprav; seed z veřejných hodnocení (Nadační fond nezávislé žurnalistiky, Konspiratori.sk, MBFC) | viz 6 |
| Trénink/eval teploty | SemEval propaganda/persuasion datasety, GoEmotions, CZ sentimentové korpusy | CZ data doanotovat |
| Trénink/eval deepfake | veřejné benchmarky (FaceForensics++, DFDC, novější GenImage-typ sady) + vlastní čerstvá sada z aktuálních generátorů (Ol1nův ComfyUI stack) | detektory rychle stárnou → pravidelný re-eval |
| Eval fact-checku | FEVER, AVeriTeC, CsFEVER (česká verze) | |

**Krok 0 pro Opus:** u všech jmenovaných API, datasetů a modelů ověřit aktuální stav, dostupnost a licenci – seznam vychází z obecné znalosti a mohl zastarat.

## 6. Klasifikace zdrojů

Nepoužívat jedno číslo „důvěryhodnost". Každý zdroj má profil:
- **Typ:** primární (data, zákon, originální dokument) / agentura / zpravodajské médium / názorové médium / blog / sociální síť / fact-checker / stát / PR.
- **Transparentnost:** známý vlastník, redakce, kontakty, opravy.
- **Historie:** podíl tvrzení ověřených vs. vyvrácených v naší DB (roste s používáním).
- **Průměrná teplota** zdroje z analyzovaných článků.
- **Nezávislost:** kdo od koho přebírá (shluky přes pHash textu / agenturní zdroj).
- **Střety zájmů:** jen doložené (vlastnictví, financování) s odkazem.

Váha zdroje při agregaci = funkce (typ, transparentnost, historie); vzorec v konfiguraci a viditelný uživateli („proč tomuhle zdroji věříme víc").

## 7. Latence – co jde hned a co ne

| Výstup | Očekávání | Režim |
|---|---|---|
| Teplota textu, technika, titulek vs. obsah | 1–5 s | realtime |
| C2PA/metadata, cache hit, existující fact-check | 1–3 s | realtime |
| Detekce syntetického obrázku | 3–15 s | skoro realtime |
| Reverse search původu obrázku | 5–20 s | průběžně |
| Ověření tvrzení (retrieval + NLI, 5–10 tvrzení) | 30–120 s | průběžně přes SSE, tvrzení naskakují postupně |
| Srovnání dvou článků | 1–3 min | job + notifikace |
| Video (ASR + snímky + audio) | cca 0,5–2× délka videa | job + push notifikace |

UX: výsledek se skládá postupně – nejdřív teplota a metadata, pak tvrzení jedno po druhém, nakonec média. Čísla jsou odhad; změřit na Sparku v M1 a tabulku aktualizovat.

## 8. Datový model (minimum)

- `analyses` (id, content_hash, type, status, created_at)
- `documents` (id, url, publisher_id, title, author, published_at, text)
- `claims` (id, document_id, text, span_start, span_end, kind: fact|opinion|prediction)
- `evidence` (id, claim_id, source_url, publisher_id, passage, stance, retrieved_at)
- `verdicts` (claim_id, label, confidence, explanation)
- `temperature` (document_id, span, emotions jsonb, techniques jsonb, score)
- `media_checks` (id, analysis_id, media_hash, signals jsonb, score)
- `publishers` (id, domain, type, owner, transparency, stats jsonb)
- `comparisons` (id, doc_a, doc_b, alignment jsonb)

## 9. Milníky

- **M0 – Výzkum (bez kódu):** ověřit zdroje a licence z kap. 5 a API sítí z kap. 16, vybrat vícejazyčné modely běžící na Sparku (ARM64, GB10) i L40S a změřit je (kap. 15), sepsat `PRAVDOMER_MODELS.md` a `PRAVDOMER_SOURCES.md`. Sestavit eval sadu Tier 1: po 50 článcích CZ/SK/EN, 300 ručně označených tvrzení, 200 obrázků (půl reálné, půl generované), 50 screenshotů ze sítí.
- **M1 – Teplota (text):** ingest URL → teplota per odstavec se zvýrazněním. Go API + SSE, jednoduchá Flutter obrazovka, share sheet. Změřit latenci.
- **M2 – Tvrzení + evidence:** extrakce, fact-check lookup, retrieval, NLI, verdikty s citacemi; strojová kontrola citací. Eval proti sadě z M0.
- **M3 – Srovnání dvou článků.**
- **M4 – Obrázky:** provenance, reverse search, detektor ensemble; eval včetně čerstvých generátorů.
- **M5 – Video/audio:** ASR, snímky, hlas; jobový režim + notifikace.
- **M6 – Registr zdrojů + profil vydavatele v UI + crawl a veřejný leaderboard (nejdřív jen teplota, viz 17).**
- **M7 – Store (zdarma, bez IAP):** texty, právní upozornění, feedback tlačítko „tohle je špatně".
- **Po MVP:** monetizace, konektory na API sociálních sítí, rozšíření Tier 2 jazyků.

Každý milník končí: testy, eval čísla zapsaná do `PRAVDOMER_EVAL.md`, krátké demo.

## 10. Metriky kvality

- Teplota: shoda s ruční anotací (F1 per technika), zvlášť CZ a EN.
- Tvrzení: přesnost verdiktů; **podíl neplatných citací musí být 0** (hard gate).
- Média: AUC + míra falešných pozitiv na reálných fotkách (cíl: nízké FP důležitější než vysoký recall – falešné obvinění z fake je horší chyba).
- Kalibrace jistoty (když appka říká 80 %, má mít pravdu v ~80 %).

## 11. Rizika

- **Falešná jistota uživatele** – zmírnit škálami, limity v UI, „nelze ověřit" jako plnohodnotný výsledek.
- **Právní:** označení konkrétního média/autora za lháře = riziko žaloby; proto zásada „tvrzení, ne lidi" a vždy citace. Autorská práva: ukládat jen krátké pasáže + odkaz. Před M7 konzultace s právníkem.
- **Stárnutí detektorů** – měsíční re-eval na nových generátorech; v UI datum poslední kalibrace.
- **Podjatost registru zdrojů** – transparentní vzorec, možnost uživatele váhy vidět.
- **Prompt injection** z analyzovaných stránek – obsah vždy jako data, nikdy jako instrukce; izolovat retrieval od generování verdiktu.
- **Náklady na search API** – cache, limity per uživatel.
- **Čeština** – méně dat i hotových modelů; počítat s vlastní anotací.

## 12. Rozhodnutí Ol1na (12. 11. 2026)

1. **Jazyky: všechny.** Pipeline je jazykově agnostická od začátku (viz 14).
2. **Inference: pilot na Spark + L40S**, žádné cloudové LLM (viz 15).
3. **Monetizace: MVP zdarma**, řešit až po MVP. Ol1n Pass zatím ne. Jen technické limity proti zneužití (rate limit per zařízení).
4. **Vstupy: URL + screenshoty.** Konektory na API sociálních sítí až po MVP (viz 16).
5. **Veřejný leaderboard médií: ano** (viz 17).

6. **Schváleno (12. 11. 2026):** jazykové tiery dle kap. 14, L40S jen jako dočasný sandbox (kap. 15), leaderboard z vlastního crawlu, nejdřív jen teplota (kap. 17), minimální vzorek 30 článků za 90 dní na médium.

### Zbývající otevřená otázka
- Právní konzultace před zveřejněním leaderboardu – kdo a kdy? Blokuje jen veřejné spuštění v M6, ne vývoj.

## 14. Vícejazyčnost

- Detekce jazyka při ingestu; jazyk je atribut dokumentu, tvrzení i evidence.
- Modely volit vícejazyčné (LLM, embeddingy, NLI, ASR, OCR). Žádné prompty ani pravidla napevno v češtině – slovníky nabitého jazyka per jazyk nebo přes model.
- **Cross-lingual retrieval:** tvrzení se pro hledání přeloží do EN + jazyka originálu + jazyka země, které se týká; evidence se hodnotí v originále, vysvětlení se generuje v jazyce uživatele.
- Fact-check lookup přes ClaimReview funguje mezinárodně; lokální fact-checkery přidávat per země do registru zdrojů.
- **Kvalita nebude všude stejná.** Eval tiery: Tier 1 = CZ, SK, EN (plná eval sada, gate pro release); Tier 2 = DE, PL, UK, RU, ES, FR (menší sada); ostatní best-effort. V UI u Tier 3 jazyků štítek „nižší spolehlivost pro tento jazyk".
- Registr zdrojů: startovat CZ/SK + velká mezinárodní média; neznámá doména = profil „neznámý zdroj", ne nízké skóre.
- UI appky: CZ + EN v MVP, lokalizace přes ARB.

## 15. Inference: Spark + L40S

- Veškeré volání modelů přes LiteLLM gateway; cíl (Spark / L40S) je konfigurace, ne kód. Workers musí běžet na ARM64 (Spark) i x86_64 (L40S) – kontejnery pro obě architektury.
- **Spark (128 GB unified):** velký LLM pro extrakci/NLI/vysvětlení, embeddingy, trvalý provoz pilotu.
- **L40S (48 GB VRAM, cloud sandbox, časově omezený):** benchmark latencí a propustnosti, dávkové úlohy (video, crawl pro leaderboard), trénink/destilace klasifikátoru teploty.
- V M0 změřit na obou: tokeny/s LLM, čas detektoru na obrázek, ASR realtime faktor. Výsledek do `PRAVDOMER_MODELS.md` + doporučení, co kde poběží po skončení sandboxu.
- Protože L40S je dočasný, nic v produkční cestě na něm nesmí být závislé – pilot musí přežít jen na Sparku.

## 16. Sociální sítě

MVP: uživatel sdílí URL nebo screenshot.
- **URL příspěvku:** fetcher zkusí veřejnou stránku / oEmbed; většina sítí ale vyžaduje přihlášení nebo blokuje boty. Při neúspěchu appka požádá o screenshot.
- **Screenshot:** OCR + VLM vytáhne text, autora, datum, síť a vložený obrázek; obrázek jde do média pipeline (4.5), text do 4.2/4.3. Pozor: screenshot lze zfalšovat – označit jako „obsah dle screenshotu, původ neověřen".
- **Po MVP – oficiální API** (dává originální text, autora, čas, média v plné kvalitě, vlákno a kontext, které screenshot nemá). Stav a ceny ověřit v M0: X API (placené), YouTube Data API (zdarma s kvótami, titulky + metadata), Bluesky a Mastodon (otevřené), Telegram veřejné kanály, Meta/TikTok (přístup hlavně pro výzkumníky). Začít těmi otevřenými a YouTube.
- Žádný scraping obcházející přihlášení nebo podmínky služeb.

## 17. Veřejný leaderboard médií

- Web `pravdomer.ol1n.com/media` + obrazovka v appce. Per médium: průměrná teplota, rozložení emocí, nejčastější manipulativní techniky, podíl podložených tvrzení, trend v čase, počet analyzovaných článků.
- **Zdroj dat = vlastní pravidelný crawl**, ne uživatelské analýzy (ty jsou výběrově zkreslené – lidé posílají hlavně podezřelé články, a jsou soukromé). Denně N článků z titulní strany / RSS každého sledovaného média, stejná metoda pro všechny.
- Pravidla férovosti: minimální vzorek pro zobrazení, intervaly spolehlivosti místo jednoho čísla, oddělit zpravodajství od komentářů (názorový text má legitimně vyšší teplotu), srovnávat v rámci kategorie (deník vs. deník, bulvár vs. bulvár).
- Každé číslo proklikatelné na konkrétní články a pasáže, ze kterých vzniklo. Veřejná stránka metodiky + verze modelu + datum.
- Formulace: „naměřená teplota", „podíl tvrzení s dohledanou oporou" – ne „lháři", „dezinformační web".
- Kanál pro námitky médií + proces opravy; log změn metodiky.
- Teplota může být veřejná dřív než pravdivostní metriky – je levnější, robustnější a právně méně riziková. Podíl podložených tvrzení zveřejnit až po dosažení eval gate z kap. 10.
- Crawl respektuje robots.txt a ukládá jen metriky + krátké citace + odkaz.

## 13. První úkol pro Opus

Proveď M0: ověř kapitolu 5 proti aktuálnímu stavu, navrhni konkrétní modely pro Spark, vytvoř eval sadu a vrať se s `PRAVDOMER_MODELS.md`, `PRAVDOMER_SOURCES.md` a upřesněným odhadem latencí. Kód piš až po schválení M0.
