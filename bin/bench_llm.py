#!/usr/bin/env python3
"""M0 LLM benchmark: latency, throughput, JSON validity and quote validity.

Runs llm_prompts/temperature.md and llm_prompts/claims.md over eval articles in
run/eval/articles/ against an OpenAI-compatible endpoint (LiteLLM on SPARK).
Outputs double as *silver* pre-annotations for human review (never as gold).

  run/eval/silver/<model>/<article>.<task>.json   raw model output + parsed JSON
  run/bench/<stamp>-<model>.csv                    one row per request
  run/bench/<stamp>-<model>.summary.json           p50/p95 latency, tok/s, validity

Quote validity is the M2 hard gate rehearsal: every "quote" must be an exact
substring of the source text (after whitespace normalisation); fuzzy ratio is logged.

Env: LLM_BASE_URL (e.g. http://<spark>:4000/v1), LLM_API_KEY.
Usage: .venv/bin/python -I bin/bench_llm.py --model auto --limit 30 --concurrency 4
"""
from __future__ import annotations

import argparse
import csv
import difflib
import json
import os
import re
import statistics
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARTICLES = ROOT / "run/eval/articles"
TASKS = {"temperature": ROOT / "llm_prompts/temperature.md", "claims": ROOT / "llm_prompts/claims.md"}
MAX_CHARS = 12000  # keep requests comparable; long articles are truncated at a paragraph boundary


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def build_doc(article: dict) -> tuple[str, str]:
    text = article["doc"]["text"]
    paras = [p.strip() for p in text.split("\n") if p.strip()]
    out, n = [], 0
    for i, p in enumerate(paras, 1):
        line = f"[p{i}] {p}"
        if n + len(line) > MAX_CHARS:
            break
        out.append(line)
        n += len(line) + 1
    body = "\n".join(out)
    title = article.get("title") or article["doc"].get("title") or ""
    return f"<document>\nTITLE: {title}\n{body}\n</document>", body


def post(base: str, key: str, payload: dict, timeout: int = 600) -> tuple[dict, float, float]:
    """Streams a chat completion; returns (result, ttft_s, total_s)."""
    req = urllib.request.Request(
        base.rstrip("/") + "/chat/completions",
        data=json.dumps(payload | {"stream": True, "stream_options": {"include_usage": True}}).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    t0 = time.monotonic()
    ttft = None
    content, usage = [], {}
    with urllib.request.urlopen(req, timeout=timeout) as r:
        for raw in r:
            line = raw.decode().strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            chunk = json.loads(data)
            if chunk.get("usage"):
                usage = chunk["usage"]
            for ch in chunk.get("choices", []):
                piece = (ch.get("delta") or {}).get("content")
                if piece:
                    if ttft is None:
                        ttft = time.monotonic() - t0
                    content.append(piece)
    return {"content": "".join(content), "usage": usage}, ttft or 0.0, time.monotonic() - t0


def quotes_of(task: str, parsed: dict) -> list[str]:
    if task == "claims":
        return [c.get("quote", "") for c in parsed.get("claims", [])]
    return [t.get("quote", "") for p in parsed.get("paragraphs", []) for t in p.get("techniques", [])
            if t.get("technique") != "none"]


def check_quotes(quotes: list[str], source: str) -> tuple[int, int, float]:
    src = norm(source)
    exact, ratios = 0, []
    for q in quotes:
        q = norm(q)
        if q and q in src:
            exact += 1
            ratios.append(1.0)
        elif q:
            sm = difflib.SequenceMatcher(None, src, q, autojunk=False)
            m = sm.find_longest_match(0, len(src), 0, len(q))
            ratios.append(m.size / max(len(q), 1))
    return exact, len(quotes), (statistics.mean(ratios) if ratios else 1.0)


def pick_model(base: str, key: str, want: str) -> str:
    req = urllib.request.Request(base.rstrip("/") + "/models", headers={"Authorization": f"Bearer {key}"})
    ids = [m["id"] for m in json.load(urllib.request.urlopen(req, timeout=30))["data"]]
    print("available models:", ", ".join(ids), file=sys.stderr)
    if want != "auto":
        return want
    for pref in ("openclaw-default", "qwen36", "qwen", "gemma", "gpt-oss", "nemotron"):
        for i in ids:
            if pref in i.lower():
                return i
    return ids[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="auto")
    ap.add_argument("--limit", type=int, default=30)
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--tasks", default="temperature,claims")
    ap.add_argument("--max-tokens", type=int, default=3000)
    args = ap.parse_args()

    base = os.environ.get("LLM_BASE_URL")
    key = os.environ.get("LLM_API_KEY", "dummy")
    if not base:
        print("LLM_BASE_URL is not set (see .env.example)", file=sys.stderr)
        return 2
    model = pick_model(base, key, args.model)
    slug = re.sub(r"[^a-zA-Z0-9._-]+", "_", model)
    files = sorted(ARTICLES.glob("*.json"))
    # interleave languages so a partial run still covers cs/sk/en
    by_lang: dict[str, list[Path]] = {}
    for f in files:
        by_lang.setdefault(f.name[:2], []).append(f)
    order = [f for group in zip(*by_lang.values()) for f in group][: args.limit]
    sil = ROOT / f"run/eval/silver/{slug}"
    sil.mkdir(parents=True, exist_ok=True)
    bench = ROOT / "run/bench"
    bench.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M")
    rows: list[dict] = []
    lock = threading.Lock()
    prompts = {t: TASKS[t].read_text() for t in args.tasks.split(",")}

    def job(path: Path, task: str) -> None:
        art = json.loads(path.read_text())
        doc, body = build_doc(art)
        payload = {
            "model": model, "temperature": 0, "max_tokens": args.max_tokens,
            "response_format": {"type": "json_object"},
            "messages": [{"role": "system", "content": prompts[task]}, {"role": "user", "content": doc}],
            "chat_template_kwargs": {"enable_thinking": False},
        }
        row = {"article": art["id"], "lang": art["lang"], "task": task, "in_chars": len(doc)}
        try:
            res, ttft, total = post(base, key, payload)
            usage = res["usage"]
            row |= {"ttft_s": round(ttft, 3), "total_s": round(total, 3),
                    "prompt_tokens": usage.get("prompt_tokens"), "completion_tokens": usage.get("completion_tokens")}
            ct = usage.get("completion_tokens") or 0
            row["out_tok_s"] = round(ct / max(total - ttft, 1e-3), 1)
            try:
                parsed = json.loads(res["content"])
                row["json_ok"] = 1
            except json.JSONDecodeError:
                parsed, row["json_ok"] = {}, 0
            ex, n, fuzz = check_quotes(quotes_of(task, parsed), body)
            row |= {"quotes": n, "quotes_exact": ex, "quote_fuzzy_mean": round(fuzz, 3)}
            if task == "claims":
                row["claims_fact"] = sum(1 for c in parsed.get("claims", []) if c.get("kind") == "fact")
            (sil / f"{art['id']}.{task}.json").write_text(
                json.dumps({"model": model, "raw": res["content"], "parsed": parsed}, ensure_ascii=False, indent=1))
        except Exception as exc:  # noqa: BLE001 - log the body, keep the batch alive
            body_txt = getattr(exc, "read", lambda: b"")().decode(errors="replace")[:500]
            row |= {"error": f"{exc} {body_txt}".strip()}
            print(f"ERROR {art['id']} {task}: {row['error']}", file=sys.stderr, flush=True)
        with lock:
            rows.append(row)
            if len(rows) % 10 == 0:
                print(f"{len(rows)} requests done", file=sys.stderr, flush=True)

    with ThreadPoolExecutor(args.concurrency) as pool:
        for p in order:
            for t in prompts:
                pool.submit(job, p, t)

    cols = ["article", "lang", "task", "in_chars", "prompt_tokens", "completion_tokens", "ttft_s", "total_s",
            "out_tok_s", "json_ok", "quotes", "quotes_exact", "quote_fuzzy_mean", "claims_fact", "error"]
    with (bench / f"{stamp}-{slug}.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    def pct(xs: list[float], q: float) -> float | None:
        xs = sorted(xs)
        return round(xs[min(len(xs) - 1, int(q * len(xs)))], 2) if xs else None

    summary = {"model": model, "concurrency": args.concurrency, "requests": len(rows),
               "errors": sum(1 for r in rows if r.get("error"))}
    for task in prompts:
        ok = [r for r in rows if r["task"] == task and not r.get("error")]
        tot = [r["total_s"] for r in ok]
        q_all = sum(r["quotes"] for r in ok)
        summary[task] = {
            "n": len(ok), "total_p50_s": pct(tot, 0.5), "total_p95_s": pct(tot, 0.95),
            "ttft_p50_s": pct([r["ttft_s"] for r in ok], 0.5),
            "out_tok_s_p50": pct([r["out_tok_s"] for r in ok], 0.5),
            "json_ok_rate": round(sum(r["json_ok"] for r in ok) / max(len(ok), 1), 3),
            "quote_exact_rate": round(sum(r["quotes_exact"] for r in ok) / max(q_all, 1), 3),
            "by_lang": {lang: pct([r["total_s"] for r in ok if r["lang"] == lang], 0.5) for lang in by_lang},
        }
    (bench / f"{stamp}-{slug}.summary.json").write_text(json.dumps(summary, indent=1))
    print(json.dumps(summary, indent=1))
    # last line for spark-broker summary
    print(json.dumps({"requests": {"ok": len(rows) - summary["errors"], "failed": summary["errors"]}}))
    return 0 if summary["errors"] < len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
