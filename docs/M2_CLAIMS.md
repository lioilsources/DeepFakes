# M2: ověřování tvrzení

Jak Pravdoměr ověřuje tvrzení (plán kap. 4.3). Kód je v `api/internal/claims` a `api/internal/search`, konfigurace v `api/config/claims.json`, prompty v `llm_prompts/claims.md` a `llm_prompts/stance.md`.

## Postup

Ověřování běží souběžně s teplotou. Appka dostává tvrzení i verdikty průběžně přes SSE.

1. **Extrakce.** LLM projde dokument po blocích (~6000 znaků) a vrátí tvrzení. U každého je doslovná citace, samostatná formulace, druh (fakt, názor nebo předpověď), důležitost 0–1 a 2–3 vyhledávací dotazy (aspoň jeden anglicky). Citace, která není doslova v odstavci, se zahodí a tvrzení s ní.
2. **Výběr.** Ověřují se jen fakta s `checkworthy ≥ 0.4`, nejvýš 6 na článek, od nejdůležitějších. Názory, předpovědi a zbytek dostanou `not_checked` s důvodem.
3. **Hledání.** Pořadí:
   - Google Fact Check (ClaimReview) dotazem z formulace tvrzení v jazyce dokumentu a jedním anglickým dotazem.
   - Brave a Wikipedie s dotazy z extrakce.
   - Výsledky hledání se neukládají, pracuje se jen s URL. Stránky stejného webu jako analyzovaný článek se vynechají, článek nesmí potvrzovat sám sebe.
4. **Stažení.** Nejvýš 5 stránek na tvrzení, se stejným bezpečným fetcherem jako článek: bez přístupu do LAN, s limitem velikosti a UA DeepFakeBot. Stránky sdílená tvrzení stahují jen jednou.
5. **Pasáže.**
   - Stránka se rozdělí na pasáže po ~700 znacích.
   - Pasáže se seřadí lexikálně podle shody s tvrzením (BM25, čísla mají dvojnásobnou váhu, hrubé ořezání koncovek pro češtinu a slovenštinu).
   - Vybere se nejvýš 8 pasáží, z jedné stránky nejvýš 2.
   - Přes jazyky to funguje jen díky jménům a číslům. Až poběží `deepfake-embed` a `deepfake-rerank` na SPARKu, nahradí tenhle krok.
6. **Stance.**
   - Jedno volání LLM na tvrzení se všemi pasážemi. Model u každé pasáže řekne `supports`, `refutes` nebo `irrelevant` a k první dvojici přidá doslovnou citaci z té pasáže.
   - Citace se ověří proti staženému textu. Neplatná citace znamená, že důkaz neexistuje.
   - Citace musí s tvrzením sdílet aspoň jedno číslo nebo delší slovo (kmen). Jinak jde nejspíš o větu o něčem jiném a důkaz se zahodí (`evidence_off_topic`).
   - **Datum.** Model dostane datum článku (`CLAIM_DATE`, jinak den analýzy) a datum každé stránky, u Wikipedie je to poslední úprava. Měnící se veličiny (výroba, počty, ceny, funkce) se posuzují k datu tvrzení. Starší údaj je `irrelevant`, ne `refutes`, protože číslo se mohlo prostě změnit.
   - **Kontrola vyvrácení.** Každé `refutes` projde druhým krátkým dotazem (`llm_prompts/refute.md`): jde o stejnou veličinu za stejné období, ve stejné jednotce a rozsahu a opravdu nemůže platit současně s tvrzením? Když ne, nebo když dotaz selže, důkaz se zahodí (`refutes_rejected`) a vysvětlení modelu se nezobrazí. Samotné pravidlo ve stance promptu nestačilo, model dál bral roční součet jako vyvrácení měsíčního čísla.
   - Model nesmí použít vlastní znalosti, jen pasáže. Pasáž o jiné události, době nebo osobě (i se shodnými jmény a čísly), položka seznamu literatury nebo vytržený řádek tabulky jsou `irrelevant`.
7. **Verdikt.** Počítá ho kód, ne model:
   - **Nezávislé zdroje.** Jedna doména tvoří jeden zdroj. Pasáže s Jaccardovou podobností trojic slov ≥ 0.5 (převzatá agenturní zpráva) se slijí do jednoho zdroje.
   - **Váha zdroje.** Zdroj přispívá nejsilnější podporou a nejsilnějším vyvrácením: `váha typu × jistota modelu`.
   - **Typy zdrojů** podle domény: `fact_checker 1.0`, `primary 1.0`, `encyclopedia 0.7`, `news 0.6`, `unknown 0.5`.
     - Seznam domén je v `claims.json` a je to faktická kategorizace (úřad, statistika, fact-checker), ne hodnocení důvěryhodnosti.
     - Neznámá doména není penalizovaná jako nedůvěryhodná. Jen nemá bonus primárního zdroje.
   - **Pravidla verdiktu.** `S` je součet podpory, `R` součet vyvrácení:
     - `max(S, R) < 0.3` → `unverifiable`.
     - Obě strany ≥ 0.3 a slabší je aspoň 35 % silnější → `disputed`.
     - Jinak podle převahy: `S ≥ 1.2` → `supported`, `S ≥ 0.6` → `mostly_supported`. Slabší podpora → `unverifiable` (`weak_evidence`).
     - Když převažuje `R`: `R ≥ 0.85` → `refuted`, jinak `unverifiable` (`weak_evidence`).
     - Jeden zpravodajský zdroj tedy tvrzení podloží nejvýš „převážně“ a sám ho nevyvrátí. Jeden fact-checker nebo primární zdroj s vysokou jistotou ho vyvrátit umí. Asymetrie je záměrná: označit tvrzení za vyvrácené je silnější výrok a chce víc.
   - **Jistota** je zatím heuristika. Kalibrace na eval sadě je úkol M2 eval (cíl z kap. 10: když appka říká 80 %, má mít pravdu v ~80 %).
8. **Vysvětlení.** Model ve stejném volání napíše 1–2 věty v jazyce dokumentu jen z pasáží. U `unverifiable` se nezobrazuje.

## Zásady v kódu

- Žádný verdikt bez důkazu: bez platné citace ze staženého zdroje je výsledek vždy `unverifiable`.
- Citace z modelu (v článku i ve zdroji) projdou tvrdým gatem `internal/quote`.
- Analyzovaný článek i stažené stránky jsou v promptu jako data (`<document>`, `<passage>`). Značky uvnitř obsahu se rozbijí.
- Hodnotí se tvrzení, ne autor ani médium.
- Po `CACHE_TTL` se smažou texty tvrzení, citace a vysvětlení. Zůstanou verdikty, typy zdrojů a odkazy.

## Náklady a limity

- **Brave:** jeden dotaz na každou kombinaci dotazu a poskytovatele, tj. až 3 na tvrzení a 18 na článek. `BRAVE_DAILY_LIMIT` (výchozí 30) drží měsíční kredit zdarma. Po vyčerpání pokračuje jen Wikipedie a Fact Check.
- **Wikipedie:** bez klíče, s UA podle pravidel Wikimedia.
- **LLM:** jedno volání na blok extrakce, jedno na každé ověřované tvrzení a jedno na každé `refutes`.

## Co chybí (další kroky M2)

- **Lepší výběr pasáží:** embedding a reranker (`deepfake-embed`, `deepfake-rerank`) místo lexikálního řazení.
- **Volba enkodéru:** NLI enkodér (`ctu-aic/xlm-roberta-large-xnli-csfever`) jako rychlá druhá stance. Rozhodnout podle evalu.
- **Primární data:**
  - ČSÚ DataStat, Eurostat a PSP pro čísla a hlasování.
  - GDELT pro hledání zpravodajství.
  - RSS Manipulátoři a Faktické.info.
- **Eval:**
  - Stance na CsFEVER (CC BY-SA), viz `bin/m2_stance_eval.py`.
  - Celý řetězec na ručních tvrzeních z Tier 1 (300 tvrzení dodá ruční anotace).
  - Výsledky do `docs/PRAVDOMER_EVAL.md`.
- **Jazyk vysvětlení:** teď jazyk dokumentu, má být jazyk uživatele.
