"""M1 latency and quality smoke test against a running Pravdoměr API.

Submits article URLs from eval/tier1/articles.csv, follows the SSE stream
and records time to document, first paragraph and summary.

Outputs (gitignored):
  run/bench/m1_latency.csv
  run/bench/m1_latency_summary.json
Last stdout line is broker metrics: {"articles":{"ok":N,"failed":M}}
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import statistics
import sys
import time
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "run/bench"


def submit(api: str, device: str, url: str) -> str:
    req = urllib.request.Request(
        f"{api}/v1/analyses",
        data=json.dumps({"url": url}).encode(),
        headers={"Content-Type": "application/json", "X-Device-Id": device},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["id"]


def follow(api: str, aid: str, t0: float) -> dict:
    row: dict = {"id": aid}
    req = urllib.request.Request(f"{api}/v1/analyses/{aid}/events", headers={"Accept": "text/event-stream"})
    with urllib.request.urlopen(req, timeout=900) as r:
        event = ""
        for raw in r:
            line = raw.decode().rstrip("\n")
            if line.startswith("event: "):
                event = line[7:]
            elif line.startswith("data: "):
                data = json.loads(line[6:])
                t = round(time.monotonic() - t0, 2)
                if event == "document":
                    row |= {"t_document": t, "paragraphs": len(data["paragraphs"]), "language": data["language"],
                            "chars": sum(len(p["text"]) for p in data["paragraphs"])}
                elif event == "paragraph" and "t_first_paragraph" not in row:
                    row["t_first_paragraph"] = t
                elif event == "summary":
                    row |= {"t_summary": t, "score": data["score"], "techniques": sum(data["techniques"].values()),
                            "quotes_dropped": data["quotes_dropped"], "paragraphs_failed": data["paragraphs_failed"]}
                elif event == "error":
                    row |= {"t_error": t, "error": data["code"]}
                elif event == "done":
                    break
    return row


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://localhost:8096")
    ap.add_argument("--per-lang", type=int, default=5)
    ap.add_argument("--concurrency", type=int, default=2, help="simultaneous articles (users)")
    ap.add_argument("--seed", type=int, default=1112)
    args = ap.parse_args()

    with (ROOT / "eval/tier1/articles.csv").open() as f:
        rows = list(csv.DictReader(f))
    rng = random.Random(args.seed)
    picked = []
    for lang in ["cs", "sk", "en"]:
        lr = [r for r in rows if r["lang"] == lang]
        picked += rng.sample(lr, min(args.per_lang, len(lr)))

    device = str(uuid.uuid4())

    def one(r: dict) -> dict:
        t0 = time.monotonic()
        try:
            aid = submit(args.api, device, r["url"])
            out = follow(args.api, aid, t0)
        except (urllib.error.URLError, OSError, ValueError) as exc:
            out = {"error": f"client: {exc}"}
        return {"article": r["id"], "lang": r["lang"], "domain": r["domain"]} | out

    with ThreadPoolExecutor(args.concurrency) as ex:
        results = list(ex.map(one, picked))

    OUT.mkdir(parents=True, exist_ok=True)
    cols = ["article", "lang", "domain", "id", "language", "paragraphs", "chars", "t_document", "t_first_paragraph",
            "t_summary", "score", "techniques", "quotes_dropped", "paragraphs_failed", "t_error", "error"]
    with (OUT / "m1_latency.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(results)

    ok = [r for r in results if "t_summary" in r]

    def pct(xs: list[float], q: float) -> float | None:
        if not xs:
            return None
        xs = sorted(xs)
        return xs[min(len(xs) - 1, round(q * (len(xs) - 1)))]

    summary = {"n": len(results), "ok": len(ok), "concurrency": args.concurrency,
               "errors": sorted({r.get("error", "") for r in results if "error" in r})}
    for k in ["t_document", "t_first_paragraph", "t_summary"]:
        xs = [r[k] for r in ok if k in r]
        summary[k] = {"p50": pct(xs, 0.5), "p95": pct(xs, 0.95)}
    summary["language_match"] = round(statistics.mean(r.get("language") == r["lang"] for r in ok), 2) if ok else None
    summary["quotes_dropped_total"] = sum(r.get("quotes_dropped", 0) for r in ok)
    summary["techniques_total"] = sum(r.get("techniques", 0) for r in ok)
    (OUT / "m1_latency_summary.json").write_text(json.dumps(summary, indent=1))
    print(json.dumps(summary, indent=1), file=sys.stderr)
    print(json.dumps({"articles": {"ok": len(ok), "failed": len(results) - len(ok)}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
