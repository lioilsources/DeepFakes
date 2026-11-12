# Návrh profilu brokeru `deepfake`

Rozhodnuto 12. 11. 2026: Pravdoměr dostane vlastní profil spark-brokeru. Tenhle dokument je zadání pro změnu v AiStacku (compose služby) a v konfiguraci brokeru. Obojí jde přes PR do těch rep a nasazuje Olin; z tohoto repa se na SPARKu nic nespouští.

## Služby

| Služba | Model | Runtime | `--gpu-memory-utilization` | Paměť | V profilu |
|---|---|---|---|---|---|
| `qwen36` | Qwen3.6-35B-A3B NVFP4 (existující) | vLLM | jako dnes | ~40 GB | základ |
| `df-embed` | Qwen3-Embedding-4B | vLLM `--runner pooling` | 0.08 | ~10 GB | základ |
| `df-rerank` | Qwen3-Reranker-0.6B | vLLM score | 0.03 | ~3 GB | základ |
| `df-encoders` | XLM-R CsFEVER NLI, KInIT persuasion, emoce (MORESPulse) | PyTorch + FastAPI | — | ~4 GB | základ |
| `df-media` | Community Forensics + B-Free/DRCT, PDQ, c2patool | PyTorch + CLI | — | ~4 GB | základ |
| `asr` | Canary-1B-v2 (Whisper-turbo fallback, existující doplněk) | NeMo | — | ~5 GB | doplněk |
| `vl` | Qwen3-VL-8B (OCR screenshotů) | vLLM | 0.12 | ~14 GB | doplněk |
| `df-judge` | Qwen3.6-27B NVFP4 (labeler pro destilaci, dávky) | vLLM | 0.20 | ~24 GB | doplněk, jen dávkově |

Základ ≈ 61 GB, se všemi doplňky ≈ 104 GB z 128 GB. ComfyUI v profilu není (pravidlo: ComfyUI a velký LLM nikdy souběžně).

## Pravidla pro služby

- Kontejnery pro ARM64; bez `onnxruntime-gpu`, `decord`, `dlib` (na GB10 problémy, viz `PRAVDOMER_MODELS.md`).
- vLLM bez `--kv-cache-dtype fp8` (na GB10 kazí tokeny).
- Všechny modely v LiteLLM pod aliasy `deepfake-llm`, `deepfake-embed`, `deepfake-rerank`, `deepfake-vl`; aplikace zná jen aliasy.
- Enkodéry a média: vlastní HTTP API (`/v1/nli`, `/v1/temperature`, `/v1/image/check`) za gateway, stejně autentizované jako LiteLLM.

## Kroky

1. Stáhnout váhy (schváleno 12. 11.) přes `sparkctl run` do HF cache AiStacku.
2. PR do AiStacku: compose `docker-compose.deepfake.yaml` + aliasy v `litellm_config.yaml`.
3. PR do spark-brokeru: profil `deepfake` (služby základu, doplňky `asr`, `vl`, `df-judge`), strop priority projektu `deepfake`.
4. Smoke test v okně + benchmark (`bin/bench_llm.py`) a zápis do `PRAVDOMER_EVAL.md`.
