# PRAVDOMER_MODELS.md — modely pro Spark a L40S (M0)

Stav: návrh k schválení, rešerše ke dni 12. 11. 2026. Čísla jsou z model cards; vlastní měření jsou v privátním benchmarku a sem se dostanou až po schválení. Vlastní měření pro Pravdoměr: `docs/PRAVDOMER_EVAL.md`.

## Rozhodnutí Olina (12. 11. 2026)

1. **Nekomerční detektory:** v MVP (zdarma) je použít smíme; před monetizací natrénovat vlastní na vlastních datech (ComfyUI generátory + reálné fotky) a NC modely vyřadit. Evidence licencí každého použitého modelu v tabulkách níže.
2. **Stahování modelů na SPARK:** schváleno pro pilotní sestavu (embedding, reranker, NLI enkodér, Canary, detektory; ~60 GB).
3. **Reverse image search:** zatím jen vlastní index (PDQ + embedding), žádné externí API.
4. **Profil brokeru:** nový profil `deepfake` (návrh v `docs/SPARK_PROFILE.md`).

## Pasti SPARKu, které platí pro všechny modely níže

Z provozních zkušeností (AiStack a sandbox):
- `--kv-cache-dtype fp8` na GB10 kazí tokeny, nepoužívat. FULL CUDA grafy kazí výstup u hybridních MoE/Mamba (Nemotron), pouštět `cudagraph_mode: PIECEWISE`.
- Reasoning Qwen3.x vypínat přes `chat_template_kwargs.enable_thinking: false`, ne `/no_think`.
- Guided JSON: schéma musí být validní JSON Schema a každé pole s `maxItems`, jinak smyčky. `json_schema` na každém dotazu propustnost výrazně snižuje; rychlejší je `json_object` + validace a opakování jen u nevalidních.
- Obrázky do vLLM posílat base64, ne URL.
- ComfyUI a velký LLM nikdy souběžně; Pravdoměr proto nesmí počítat s generováním obrázků a LLM ve stejném okně.

## Doporučení v jedné tabulce

| Role | Primární | Kde | Licence |
|---|---|---|---|
| LLM (extrakce, NLI, vysvětlení) | Qwen3.6-35B-A3B NVFP4 (už běží, profil `llm`) | Spark | Apache 2.0 |
| LLM soudce / labeler pro destilaci | Qwen3.6-27B NVFP4 | Spark (střídat), dávky na L40S | Apache 2.0 |
| Embedding + reranker | Qwen3-Embedding-4B + Qwen3-Reranker-0.6B | Spark, vLLM pooling | Apache 2.0 |
| NLI enkodér | ctu-aic/xlm-roberta-large-xnli-csfever | Spark, PyTorch | ověřit |
| Teplota (fáze 1) | LLM s citací pasáže | Spark | — |
| Teplota (fáze 2) | destilace do XLM-R large / mmBERT | trénink L40S, inference Spark | MIT |
| Jazyk | lingua-go (+ GlotLID pro CS/SK) | Go API, CPU | Apache 2.0 |
| OCR screenshotů | Qwen3-VL-8B (zkusit i samotný Qwen3.6) | Spark | Apache 2.0 |
| ASR | Canary-1B-v2 (Whisper-turbo jako fallback, už běží) | Spark | CC BY 4.0 |
| AI obrázky | ensemble podle rozhodnutí 1 | Spark | viz výše |
| Proveniance | c2patool/c2pa-rs, VideoSeal/AudioSeal | Go API + worker | MIT |
| Hash | PDQ + vlastní index | Go API | BSD |
| Extrakce článku | go-trafilatura, fallback go-readability | Go API | Apache 2.0 |

---

Desk research ke dni 2026-11-12. Žádné cloudové LLM. Produkce běží na DGX Spark (GB10, aarch64, sm_121, 128 GB unified). L40S slouží jen jako sandbox.

**Legenda:**
- **ověřeno 2026-11-12**: fakt jsem dnes ověřil v model cardu nebo v primárním zdroji.
- **neověřeno**: fakt pochází z paměti nebo ze sekundárního zdroje a před nasazením je potřeba ho zkontrolovat.
- **Komerční použití:** ✅ dovoleno, ⚠️ s podmínkami, ❌ jen nekomerční nebo výzkumné použití.
- **ARM64:** 🟢 bez známých problémů, 🟡 vyžaduje vlastní build nebo náhradu, 🔴 známý problém.

**Obecné pasti na ARM64/GB10 (sm_121):**
- `onnxruntime-gpu` nemá oficiální wheel pro aarch64 + CUDA 13. Existují jen komunitní buildy s `CMAKE_CUDA_ARCHITECTURES=121`. INT8 ONNX nemá kernely pro sm_121, takže je potřeba používat FP32/FP16. Pozor také na to, že PyPI balíček `onnxruntime` tiše přepíše GPU build. Zdroje: [HF wheel](https://huggingface.co/WeilJimmer/onnxruntime-gpu-aarch64-cuda13-sm121), [NVIDIA fórum](https://forums.developer.nvidia.com/t/onnx-runtime-gpu-inference-on-dgx-spark-gx10-build-guide-and-prebuilt-binaries/366157), [dev.to](https://dev.to/albatross1382/getting-onnx-runtime-cuda-working-on-nvidia-blackwell-gx10dgx-spark-ngb). Ověřeno 2026-11-12.
- Pravidlo: všechno, co jde, servírovat přes **vLLM** (LLM, VLM, embedding, reranker) nebo přes čistý PyTorch. ONNX a TensorRT cesty jsou na Sparku riziko.
- `decord` nemá aarch64 wheel. Místo něj použít PyAV nebo torchcodec, případně ffmpeg pipe. `dlib` s CUDA vyžaduje build ze zdrojů. `insightface` je závislý na onnxruntime. `mediapipe` pro linux-aarch64 jsem neověřoval. Všechno neověřeno.
- PaddlePaddle GPU na aarch64 + CUDA 13 je problematický (neověřeno). PaddleOCR-VL je proto lepší pouštět přes vLLM.

---

## 1. Hlavní LLM: extrakce tvrzení, stance/NLI, vysvětlení, JSON

| Role | Model | Parametry / kvantizace na Spark | Licence | CZ/SK evidence | ARM64 | Propustnost | Zdroj |
|---|---|---|---|---|---|---|---|
| **Primární** | **Qwen3.6-35B-A3B** (duben 2026, multimodální MoE, 262K ctx) | 35B/3B aktivních. NVFP4 ≈ 22 GB vah. | Apache 2.0 ✅ | Slovenský benchmark (100 MCQ, 2026): rodina Qwen3.5 vede mezi open modely. Qwen3.5-27B má 88, 35B-A3B 82 (s reasoningem) nebo 77. Qwen3.5+ deklaruje 201 jazyků. Přímé české číslo pro 3.6 chybí. | 🟢 už běží | měřeno interně (neveřejné) | [HF](https://huggingface.co/Qwen/Qwen3.6-35B-A3B), [NGC](https://catalog.ngc.nvidia.com/orgs/nim/qwen/models/qwen3.6-35b-a3b/-), [SK bench](https://github.com/jakubjulis/thesis-llm-benchmark). Ověřeno 2026-11-12. |
| Alt. „přesnost“ | **Qwen3.6-27B** dense (22. 4. 2026) | 27B. NVFP4 ≈ 17 GB, FP8 ≈ 28 GB. | Apache 2.0 ✅ | Předchůdce Qwen3.5-27B má 88/100 na SK benchmarku, nejlepší open výsledek. | 🟢 (NVFP4 od unsloth) | Odhad 12–18 tok/s single, protože dense model naráží na limit paměťové propustnosti 273 GB/s (neověřeno) | [HF](https://huggingface.co/Qwen/Qwen3.6-27B), [zpráva](https://rits.shanghai.nyu.edu/ai/qwen3-6-27b-a-dense-27b-model-that-beats-a-397b-moe-on-coding). Ověřeno 2026-11-12. |
| Alt. „velký“ | **Nemotron 3 Super 120B-A12B NVFP4** (11. 3. 2026) | 120B/12B aktivních. NVFP4 ≈ 70 GB. Model card uvádí jako minimum „1× DGX Spark“. | NVIDIA Open Model License ⚠️ (komerčně OK, vlastní podmínky) | SK benchmark 75 (s reasoningem) nebo 72. Instrukční jazyky jsou jen EN/FR/DE/IT/JA/ES/ZH, čeština chybí. | 🟢 | Neznámá, odhad 15–25 tok/s (neověřeno) | [HF](https://huggingface.co/nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4). Ověřeno 2026-11-12. |
| Další kandidáti | Gemma 4 26B-A4B / 31B (2. 4. 2026) | MoE se 3.8B aktivních, nebo 31B dense | **Apache 2.0** ✅ (nově) | SK 74/70 | 🟢 (gemma profil existuje) | – | [model card](https://ai.google.dev/gemma/docs/core/model_card_4), [blog](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/). Ověřeno. |
| | Mistral Small 4 119B-A6.5B (16. 3. 2026) | NVFP4 ≈ 65 GB | Apache 2.0 ✅ | SK 73 s reasoningem, ale jen 50 bez něj | 🟢 (neověřeno) | – | [Mistral](https://mistral.ai/en/news/mistral-small-4/). Ověřeno. |
| | EuroLLM-22B (prosinec 2025) | 22B dense | Apache 2.0 ✅ (neověřeno) | Trénovaný na všech 24 jazycích EU. Silný v překladu, v reasoningu slabší. CS/SK čísla nejsou rozepsaná. | 🟢 | – | [tech report](https://arxiv.org/abs/2602.05879). Ověřeno. |
| Nedoporučuji | Llama 4 | – | Llama 4 Community License: omezení multimodálních práv pro subjekty z EU ⚠️ (neověřeno) | – | – | – | – |
| Nedoporučuji | gpt-oss-120b/20b | – | Apache 2.0 ✅ | Slabší v CZ/SK stylu (neověřeno) | 🟢 | – | Vhodný jen jako druhý soudce pro cross-check. |

**Doporučení:**
- Qwen3.6-35B-A3B použít jako pracovního koně. U něj zapnout structured output přes vLLM guided JSON (`response_format` / xgrammar).
- Qwen3.6-27B, případně Nemotron 3 Super, použít jako „soudce“ pro obtížné případy a pro generování labelů pro destilaci.
- Je potřeba vlastní **CZ/SK eval**: BenCzechMark má leaderboard ([Space](https://huggingface.co/spaces/CZLC/BenCzechMark), [paper TACL 2025](https://aclanthology.org/2025.tacl-1.50.pdf)), ale současná čísla pro Qwen3.6 a Gemma 4 jsem nenašel. Alternativa: MiniCzechBenchmark (NeurIPS 2025).

---

## 2. Embeddingy a reranker

| Role | Model | Velikost | Licence | Multilingual evidence | ARM64 | Zdroj |
|---|---|---|---|---|---|---|
| **Primární embedding** | **Qwen3-Embedding-4B** (8B pro offline reindex) | 4B, BF16 ≈ 8 GB. Matryoshka dimenze, instrukce v dotazu. | Apache 2.0 ✅ | MMTEB-multilingual: 0.6B má 64.34, 8B patřil při vydání v červnu 2025 na první místo (neověřeno pro 2026) | 🟢 vLLM pooling | [HF](https://huggingface.co/Qwen/Qwen3-Embedding-4B) (neověřeno dnes) |
| Alt. | **BGE-M3** | 568M | MIT ✅ | Dense, sparse i ColBERT v jednom modelu. Dobrý hybrid pro češtinu. | 🟢 (PyTorch) | [HF](https://huggingface.co/BAAI/bge-m3) (neověřeno) |
| Alt. | multilingual-e5-large-instruct | 560M | MIT ✅ | Stabilní baseline | 🟢 | [HF](https://huggingface.co/intfloat/multilingual-e5-large-instruct) |
| Vyřadit | jina-embeddings-v3/v4/v5 | – | **CC BY-NC 4.0** ❌ | v5-small má 67.0 MMTEB (tvrzení výrobce) | – | [Jina](https://jina.ai/news/jina-embeddings-v5-text-distilling-4b-quality-into-sub-1b-multilingual-embeddings). Ověřeno. |
| Vyřadit | EmbeddingGemma 2 (říjen 2026) | 744M | Gemma terms (neověřeno) | 61.36 MMTEB, tedy méně než Qwen3-Emb-0.6B (sekundární zdroj) | – | [souhrn](https://fourweekmba.com/ai-google-paper-embeddinggemma-2-trails-qwen-on-text-not-code/) |
| **Primární reranker** | **Qwen3-Reranker-4B** (0.6B pro online) | 4B / 0.6B | Apache 2.0 ✅ | Stejná rodina jako embedding | 🟢 vLLM score API | [HF](https://huggingface.co/Qwen/Qwen3-Reranker-4B) (neověřeno) |
| Alt. | bge-reranker-v2-m3 | 568M | Apache 2.0 ✅ | Osvědčený v CZ RAG | 🟢 | [HF](https://huggingface.co/BAAI/bge-reranker-v2-m3) |
| Vyřadit | jina-reranker-v2/v3 | – | CC BY-NC ❌ | – | – | – |

Benchmark: české retrieval sady jsou DaReCzech ([studie](https://arxiv.org/abs/2411.12921)) a vlastní páry tvrzení↔článek. Veřejné CZ-MTEB srovnání Qwen3-Emb a BGE-M3 jsem nenašel.

---

## 3. Malý NLI/stance enkodér (rychlá párová klasifikace)

| Role | Model | Velikost | Licence | CZ evidence | ARM64 | Zdroj |
|---|---|---|---|---|---|---|
| **Primární** | **ctu-aic/xlm-roberta-large-xnli-csfever** | 560M | Zkontrolovat v kartě. Sesterský model ctkfacts_nli má CC BY-SA 4.0 ✅⚠️ | Dotrénovaný na CsFEVER-NLI, tedy české fact-checking páry | 🟢 | [HF](https://huggingface.co/ctu-aic/xlm-roberta-large-xnli-csfever), [paper](https://arxiv.org/abs/2201.11115). Ověřeno 2026-11-12. |
| Alt. | ctu-aic/xlm-roberta-large-xnli-ctkfacts_nli | 560M | CC BY-SA 4.0 ✅ | CTKFacts (ČTK) | 🟢 | [HF](https://huggingface.co/ctu-aic/xlm-roberta-large-xnli-ctkfacts_nli). Ověřeno. |
| Alt. (rychlý) | MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7 | 280M | MIT ✅ | 100 jazyků XNLI. Pozor na nestabilitu mDeBERTa ve FP16, je potřeba BF16. | 🟢 | [HF](https://huggingface.co/MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7) (neověřeno) |

Plán: LLM (oddíl 1) olabeluje páry tvrzení↔důkaz v CS/SK. Pak destilovat do XLM-R-large nebo mmBERT-base (viz oddíl 4).

---

## 4. Emoce a manipulativní/propagandistické techniky

| Role | Model | Licence | Jazyky / evidence | Zdroj |
|---|---|---|---|---|
| **Persuasion, primární** | **kinit/semeval2023-task3-persuasion-techniques** (XLM-R large, 23 technik, multi-label) | Zkontrolovat ⚠️ (neověřeno) | 1. místo v 6 z 9 jazyků SemEval-2023 T3. Mezi jazyky je PL a RU, čeština ne. Slabý na řídkých třídách. | [paper](https://arxiv.org/abs/2304.11924), [HF](https://huggingface.co/kinit/semeval2023-task3-persuasion-techniques). Ověřeno. |
| Persuasion, data | Slavic NLP 2025 shared task (BG/PL/HR/SL/RU, taxonomie SemEval-23 + 2 techniky) | Dle datasetu | Vhodné pro fine-tune na slovanských jazycích | [úloha](https://bsnlp.cs.helsinki.fi/shared-task.html) (neověřeno URL) |
| Persuasion, alt. | LLM zero-shot (Qwen3.6) s definicemi technik a destilace | ✅ | Pro češtinu jediná reálná cesta | – |
| **Emoce, primární** | **MORES-horizon/MORESPulse** (XLM-R large, 6 tříd) | Gated, licence ⚠️ | Trénovaný mj. na **CS, SK**, PL, DE, FR, HU, EN | [HF](https://huggingface.co/MORES-horizon/MORESPulse). Ověřeno 2026-11-12. |
| Emoce, alt. | tabularisai/multilingual-emotion-classification (23 jazyků, 11 tříd, syntetická data, duben 2026) | Zkontrolovat | Pokrytí češtiny jsem neověřil | [paper](https://arxiv.org/abs/2604.12633) |
| Emoce, alt. | MilaNLProc/xlm-emo-t | Zkontrolovat | 19 jazyků (neověřeno) | – |

**Báze pro pozdější destilaci:**

| Enkodér | Licence | CZ/SK | Poznámka |
|---|---|---|---|
| **XLM-R large** | MIT ✅ | ✅ | Nejbezpečnější volba |
| **mmBERT-base/small** (JHU, 2025) | MIT ✅ | ✅ (1833 jazyků) | ModernBERT architektura, 8K kontext, rychlý. [HF](https://huggingface.co/jhu-clsp/mmBERT-base). Ověřeno. |
| mDeBERTa-v3-base | MIT ✅ | ✅ | FP16 problémy |
| RobeCzech (ufal) | **CC BY-NC-SA 4.0 ❌** (neověřeno) | Jen CS | Pro komerční produkci nevhodný |
| Seznam small-e-czech / RetroMAE | Zkontrolovat | Jen CS | Malé a rychlé |
| EuroBERT | Apache 2.0 ✅ | **❌, nepokrývá CS ani SK** (15 jazyků) | Vyřadit. [HF](https://huggingface.co/EuroBERT/EuroBERT-610m). Ověřeno. |

---

## 5. Identifikace jazyka (CPU)

| Volba | Licence | Poznámka |
|---|---|---|
| **lingua / lingua-go** (pemistahl) | Apache 2.0 ✅ | Nativní Go knihovna, pokrývá všech 9 cílových jazyků. Nejpřesnější na krátkých textech, ale pomalejší a paměťově náročnější. |
| GlotLID v3 (fastText) | Apache 2.0 ✅ | Přes 2000 labelů, dobře rozpozná i UK vs. RU. Python sidecar. [HF](https://huggingface.co/cis-lmu/glotlid) |
| fastText lid.176 | CC BY-SA 3.0 ⚠️ | Rychlý. CS/SK na krátkých textech plete. |

Doporučení: lingua-go v Go backendu. Pro rozlišení CS/SK nad 200 znaků přidat fastText/GlotLID jako druhý hlas. Vše neověřeno dnes, jde o známé licence.

---

## 6. Detekce AI-generovaných obrázků a forenzika

**Stav 2026:** zero-shot studie 16 open detektorů na 2.6M obrázků z 291 generátorů ukázala, že nejlepší má průměrnou accuracy jen 75–78 %, nejhorší 37.5 % a univerzální vítěz neexistuje. Flux Dev má průměrnou accuracy detektorů 21 %, Firefly v4 a Midjourney v7 18–30 % a Nano-Banana 44.6 % ([arXiv 2602.07814](https://arxiv.org/html/2602.07814), ověřeno 2026-11-12). Podle Deepfake-Eval-2024 klesá AUC open detektorů na reálných datech zhruba o 45 % pro obrázky ([arXiv 2503.02857](https://arxiv.org/abs/2503.02857)). Výstupem proto musí být **skóre a vysvětlení, ne verdikt**.

| Role | Model | Licence | Generalizace / FPR | ARM64 | Zdroj |
|---|---|---|---|---|---|
| **Primární** | **Community Forensics** (Park & Owens, CVPR 2025, trénováno na 4803 generátorech) | Data jen nekomerční ❌. Licenci vah zkontrolovat. | Nejlepší průměr 0.780 v zero-shot studii | 🟢 PyTorch ViT | [paper](https://arxiv.org/abs/2411.04125), [eval](https://huggingface.co/datasets/OwensLab/CommunityForensics-Eval). Ověřeno. |
| Alt. | DRCT (CLIP-ViT) | Zkontrolovat | 0.72, druhé místo | 🟢 | Tamtéž |
| Alt. | B-Free (GRIP, CVPR 2025) | **Jen nonprofit ❌** | Navrženo proti biasu na JPEG a velikost, takže nižší FPR. Na Flux jsem čísla nenašel. | 🟢 | [projekt](https://grip-unina.github.io/B-Free). Ověřeno. |
| Další | SAFE (0.69), SPAI (CVPR 2025, spektrální), AIDE, UnivFD, NPR | Většinou výzkumné licence | Slabší na komerčních generátorech | 🟢 | Tamtéž |
| Vyřadit | HF modely typu Organika/sdxl-detector, umm-maybe | Různé | Natrénované na starých generátorech | – | – |
| Benchmark sady | NTIRE 2026 Robust AIGI (42 generátorů včetně Nano Banana 2 a SeeDream 5), GPT-Image-2 bench | – | Pro vlastní kalibraci | – | [NTIRE](https://www.alphaxiv.org/abs/2604.11487), [GPT-img2](https://arxiv.org/abs/2608.01258) |

**Forenzika:**
- TruFor: jen nonprofit ❌ ([GitHub](https://github.com/grip-unina/TruFor), ověřeno).
- CAT-Net v2: licence pravděpodobně jen pro nekomerční výzkum, neověřeno.
- ELA a noise residual lze implementovat vlastním kódem (Go nebo numpy), bez licenčních problémů.

**Proveniance a vodoznaky:**

| Nástroj | Licence | Poznámka |
|---|---|---|
| **c2pa-rs / c2patool / c2pa-python** | MIT / Apache 2.0 ✅ | Rust, na aarch64 se zbuildí. Z Go volat c2patool jako CLI, nebo přes C FFI. |
| SynthID Detector | Proprietární, jen web portál (veřejný od 7. 10. 2026) | Lokální detektor pro obraz, audio ani video **neexistuje**. Open source je jen SynthID-Text. [PetaPixel](https://petapixel.com/2026/10/08/googles-synthid-ai-detector-is-now-freely-available-to-everyone/). Ověřeno. |
| Meta Video Seal (+ PixelSeal, ChunkySeal), AudioSeal | MIT ✅ (kód i váhy) | Detekují jen vlastní vodoznak Mety, nikoli obecně AI obsah. [videoseal](https://github.com/facebookresearch/videoseal). Ověřeno. |
| Stable Signature | Zkontrolovat (Meta, CC BY-NC?) | Pokrývá jen modely, které vodoznak vkládají |

Doporučení: pořadí signálů je C2PA → vodoznaky (AudioSeal/VideoSeal) → ensemble Community Forensics + B-Free/DRCT → ELA a šum. Práh kalibrovat na vlastní sadě reálných fotek z českých médií se zaměřením na FPR. **Nekomerční licence je potřeba vyjasnit**: pokud je projekt komerční, budou detektory nutné natrénovat vlastní, na vlastních datech.

---

## 7. Video deepfake / face-swap / lip-sync a syntetický hlas

| Role | Model / nástroj | Licence | Evidence | ARM64 | Zdroj |
|---|---|---|---|---|---|
| **Video, framework** | **DeepfakeBench** (SCLBD, přes 30 detektorů) | CC BY-NC 4.0 ❌ (neověřeno) | Na reálných datech podle Deepfake-Eval-2024 klesá AUC o ~50 % | 🟡 dlib a face-align závislosti | [GitHub](https://github.com/SCLBD/DeepfakeBench) |
| Video, alt. | GenConViT, AltFreezing, LipForensics (lip-sync) | Akademické, zkontrolovat | Trénováno na FF++ a DFDC. Na Sora 2, Veo 3.1 a Kling slabé. | 🟡 decord a dlib nahradit | – |
| Video, benchmarky | AIGVDBench (31 generátorů včetně Sora a Veo), FVBench (CVPR 2026), SynthForensics | – | Pro vlastní eval | – | [AIGVDBench](https://arxiv.org/abs/2601.11035), [FVBench](https://github.com/IntMeGroup/FVBench) |
| Video, pragmaticky | Snímky z videa → detektor obrázků (oddíl 6) + VLM pro artefakty + audio stopa zvlášť | – | Nejrealističtější cesta | 🟢 | – |
| **Hlas, primární** | **XLS-R + SLS** (Zhang et al.) | Zkontrolovat (GitHub) | EER pod 2 % na ASVspoof21 DF. Silný na In-the-Wild. | 🟢 PyTorch | [paper](https://sotaverified.org/papers/audio-deepfake-detection-with-self-supervised-1) |
| Hlas, alt. | SpeechAntiSpoofingBenchmarks/W2V2-AASIST | MIT ✅ | Trénováno jen na ASVspoof2019 LA + RawBoost | 🟢 | [HF](https://huggingface.co/SpeechAntiSpoofingBenchmarks/W2V2-AASIST). Ověřeno. |
| Hlas, alt. | AASIST / RawNet2 (clovaai) | MIT ✅ (neověřeno) | Baseline | 🟢 | – |
| Hlas, eval | **ML-ITW** (14 jazyků, in-the-wild), Speech DF Arena (leaderboard), Deepfake-Eval-2024 (pokles AUC ~48 %) | – | Obsahuje multilingual data | – | [ML-ITW](https://arxiv.org/abs/2603.05852), [DE-2024](https://github.com/nuriachandra/Deepfake-Eval-2024) |

---

## 8. Percepční hash a reverse image search

| Volba | Licence / cena | Poznámka |
|---|---|---|
| **PDQ** (Meta ThreatExchange), TMK+PDQF pro video | BSD ✅ | Standard pro near-duplicate detekci. Existuje C++ i Go port (neověřeno). |
| imagehash (Python), goimagehash (Go) | BSD-2 ✅ | pHash, dHash, aHash |
| Vlastní index | – | PDQ + SigLIP/CLIP embedding ve vektorové DB nad vlastním korpusem. Jediná plně self-hosted reverse search. |
| TinEye API | Předplacené balíky, ≈ $200/5000 hledání ($0.04/hledání), sekundární zdroj | [TinEye blog](https://blog.tineye.com/new-image-search-pricing/) |
| SerpApi (engine Google Lens) | Od ≈ $75/měs za 5k hledání (neověřeno) | Neoficiální scraping Google Lens. Právní riziko ToS. |
| Bing Visual Search API | Bing Search APIs Microsoft ukončil 11. 8. 2025 (neověřeno dnes) | Nepoužitelné |
| Google Lens | Oficiální API neexistuje | – |

Všechny externí API posílají obrázek ven. U citlivého obsahu je proto potřeba rozhodnutí vlastníka projektu.

---

## 9. ASR a OCR/VLM

**ASR:**

| Role | Model | Licence | WER čeština (FLEURS) | ARM64 | Zdroj |
|---|---|---|---|---|---|
| **Primární** | **NVIDIA Canary-1B-v2** (25 evropských jazyků, ASR + překlad, timestampy) | CC BY 4.0 ✅ | **7.86** | 🟢 NeMo/PyTorch (neověřeno na GB10) | [HF](https://huggingface.co/nvidia/canary-1b-v2). Ověřeno 2026-11-12. |
| Alt. (rychlý) | Parakeet-TDT-0.6B-v3 | CC BY 4.0 ✅ | 11.01 (SK 8.82, PL 7.31, UK 6.79, RU 5.51) | 🟢 | [HF](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Ověřeno. |
| Alt. | Qwen3-ASR-1.7B (52 jazyků včetně CS) + komunitní CS fine-tune | Apache 2.0 ✅ (neověřeno) | Komunitní fine-tune uvádí pro Whisper-large-v3 na FLEURS-cs 12.10 a pro sebe lepší výsledek | 🟢 vLLM | [GitHub](https://github.com/QwenLM/Qwen3-ASR), [CS FT](https://huggingface.co/inferRouter/qwen3-asr-cs-1.7b) |
| Stávající | Whisper large-v3-turbo | MIT ✅ | ≈ 12+ (v3 má 12.1, turbo je horší) | 🟢 | – |

Ukrajinštinu a ruštinu Canary/Parakeet pokrývají. Výsledek: Canary je v češtině zhruba o třetinu přesnější než Whisper-v3. Benchmark na vlastních CZ/SK nahrávkách z médií je nutný.

**OCR / VLM pro screenshoty:**

| Role | Model | Licence | Evidence | ARM64 | Zdroj |
|---|---|---|---|---|---|
| **Primární** | **Qwen3-VL-8B-Instruct** (32B pro obtížné případy) | Apache 2.0 ✅ | OCR ve 32 jazycích. GlotOCR Acc@5 52.4. | 🟢 vLLM | [GitHub](https://github.com/QwenLM/Qwen3-VL) |
| Alt. | **dots.ocr** (3B) | MIT (neověřeno) | Nejlepší v GlotOCR (59.3) a v olmOCR-Bench (≈ 88) | 🟢 vLLM (neověřeno) | [GlotOCR](https://www.alphaxiv.org/abs/2604.12978) |
| Alt. | PaddleOCR-VL(-1.5) 0.9B | Apache 2.0 ✅ | Diakritiku zvládá dobře (sekundární zdroj). GlotOCR 43.5. | 🟡 Paddle na aarch64. Pouštět přes vLLM. | [paper](https://arxiv.org/abs/2510.14528) |
| Zkusit | Qwen3.6-35B-A3B sám (je multimodální) | Apache 2.0 | Mohl by nahradit samostatný VLM | 🟢 | Benchmark |
| Vyřadit | olmOCR-2 (zaměřený na angličtinu), GOT-OCR (starší) | – | – | – | – |

Typické chyby v češtině: ř→r, ů→u. Potřeba je vlastní testovací sada screenshotů s diakritikou (CS/SK, azbuka UK/RU).

---

## 10. Extrakce článků

- **go-trafilatura** (markusmobius) je nativní Go port. Dosahuje F-score ≈ 0.90–0.91 s fallbackem, zatímco go-readability má 0.88 ([benchmark](https://github.com/markusmobius/content-extractor-benchmark)). Licence Apache 2.0 (neověřeno).
- Fallback: go-readability (go-shiori).
- Python trafilatura je potřeba jen pro zvláštní weby. newspaper4k nepotřebujeme.
- Recency go-trafilatura jsem neověřil, je potřeba zkontrolovat commity.

---

## Spark pilot set (128 GB unified, nic jiného neběží)

| Služba | Model | Runtime | Paměť (váhy + KV/overhead) |
|---|---|---|---|
| Hlavní LLM | Qwen3.6-35B-A3B NVFP4 | vLLM (stávající profil) | ~40 GB |
| Soudce / labeler (střídat, ne souběžně s velkým batch během) | Qwen3.6-27B NVFP4 | vLLM | ~24 GB |
| VLM/OCR | Qwen3-VL-8B FP8, nebo vynechat, pokud stačí Qwen3.6 | vLLM | ~14 GB |
| Embedding + reranker | Qwen3-Embedding-4B + Qwen3-Reranker-0.6B | vLLM `--task embed/score` | ~12 GB |
| Enkodéry | XLM-R-large CsFEVER NLI, KInIT persuasion, MORESPulse emoce | PyTorch / FastAPI sidecar | ~4 GB |
| ASR | Canary-1B-v2 (+ Whisper-turbo jako fallback) | NeMo | ~5 GB |
| Obraz | Community Forensics + B-Free/DRCT, PDQ, c2patool | PyTorch + CLI | ~4 GB |
| Audio deepfake | XLS-R-300M SLS / W2V2-AASIST | PyTorch | ~2 GB |
| OS, page cache, rezerva | – | – | ~20 GB |
| **Celkem** | | | **~125 GB** (bez soudce ~100 GB) |

Nemotron 3 Super (~70 GB) nebo Mistral Small 4 (~65 GB) se do této sestavy nevejdou. Dají se testovat jen jako samostatné okno přes `sparkctl window`. Každé vLLM instanci je nutné nastavit explicitní `--gpu-memory-utilization`, protože vLLM na unified memory počítá podíl z celých 128 GB.

**Nutné benchmarky před produkcí:**
1. CZ/SK eval LLM: extrakce tvrzení a NLI na CsFEVER a CTKFacts, kvalita JSON, BenCzechMark subset. Srovnat Qwen3.6-35B-A3B, Qwen3.6-27B, Gemma 4 26B a Nemotron 3 Super.
2. Retrieval: Qwen3-Emb-4B vs. BGE-M3 na DaReCzech a na vlastních párech.
3. Detektory obrázků: FPR na ≥ 2k reálných fotkách z CZ médií (JPEG, screenshoty) a TPR na Flux, GPT-image, Nano Banana, Seedream a Qwen-Image.
4. ASR: Canary-1B-v2 vs. Whisper-turbo vs. Qwen3-ASR na vlastním CZ/SK audiu (WER a rychlost na GB10).
5. OCR: Qwen3-VL-8B vs. dots.ocr vs. Qwen3.6-35B-A3B na screenshotech s diakritikou.
6. Audio deepfake: XLS-R-SLS na ML-ITW a na CZ vzorcích (EER).
7. Licenční audit: Community Forensics, DRCT, KInIT, MORESPulse, ctu-aic a DeepfakeBench. Pokud jsou nekomerční, rozhodnout o vlastním tréninku.
8. ARM64 smoke test kontejnerů: NeMo (Canary), PDQ, c2patool, video pipeline bez decord a dlib.
