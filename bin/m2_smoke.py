"""M2 smoke test: claim extraction and checking against a running API.

Submits article URLs from eval/tier1/articles.csv, follows the SSE stream
and records claim timings, verdict labels and gate counters. Also checks the
quote invariant client-side: every claim quote must equal the paragraph text
at its UTF-16 offsets.

Outputs (gitignored, contain article excerpts):
  run/bench/m2_smoke.csv           one row per article
  run/bench/m2_claims.jsonl        every claim with its verdict, for manual review
  run/bench/m2_smoke_summary.json
Last stdout line is broker metrics: {"articles":{"ok":N,"failed":M}}
"""

from __future__ import annotations

import argparse
import collections
import csv
import json
import random
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


def utf16_slice(s: str, start: int, end: int) -> str:
    b = s.encode("utf-16-le")
    return b[2 * start : 2 * end].decode("utf-16-le")


def follow(api: str, aid: str, t0: float) -> tuple[dict, list[dict]]:
    row: dict = {"id": aid}
    paragraphs: dict[int, str] = {}
    claims: dict[str, dict] = {}
    bad_offsets = 0
    req = urllib.request.Request(f"{api}/v1/analyses/{aid}/events", headers={"Accept": "text/event-stream"})
    with urllib.request.urlopen(req, timeout=1200) as r:
        event = ""
        for raw in r:
            line = raw.decode().rstrip("\n")
            if line.startswith("event: "):
                event = line[7:]
                continue
            if not line.startswith("data: "):
                continue
            data = json.loads(line[6:])
            t = round(time.monotonic() - t0, 2)
            if event == "document":
                paragraphs = {p["p"]: p["text"] for p in data["paragraphs"]}
                row |= {"t_document": t, "paragraphs": len(paragraphs), "language": data["language"]}
            elif event == "summary":
                row["t_summary"] = t
            elif event == "claim":
                row.setdefault("t_first_claim", t)
                if utf16_slice(paragraphs.get(data["p"], ""), data["start"], data["end"]) != data["quote"]:
                    bad_offsets += 1
                claims[data["id"]] = {"claim": data}
            elif event == "verdict":
                if data["label"] != "not_checked":
                    row.setdefault("t_first_verdict", t)
                claims.setdefault(data["claim_id"], {})["verdict"] = data
            elif event == "claims_summary":
                row |= {"t_claims_summary": t, "claims_found": data["claims_found"], "checked": data["checked"],
                        "quotes_dropped": data["quotes_dropped"], "evidence_quotes_dropped": data["evidence_quotes_dropped"],
                        "searches": data["searches"], "search_errors": data["search_errors"],
                        "pages_fetched": data["pages_fetched"], "refutes_rejected": data.get("refutes_rejected", 0),
                        "claims_error": data.get("error", "")}
            elif event == "error":
                row |= {"t_error": t, "error": data["code"]}
            elif event == "done":
                break
    labels = collections.Counter(c.get("verdict", {}).get("label", "missing") for c in claims.values())
    row |= {"bad_offsets": bad_offsets, "labels": dict(labels),
            "evidence": sum(len(c.get("verdict", {}).get("evidence", [])) for c in claims.values())}
    return row, list(claims.values())


def pct(xs: list[float], q: float) -> float | None:
    if not xs:
        return None
    xs = sorted(xs)
    return xs[min(len(xs) - 1, round(q * (len(xs) - 1)))]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://localhost:8096")
    ap.add_argument("--per-lang", type=int, default=3)
    ap.add_argument("--concurrency", type=int, default=2)
    ap.add_argument("--seed", type=int, default=1120)
    args = ap.parse_args()

    with (ROOT / "eval/tier1/articles.csv").open() as f:
        rows = list(csv.DictReader(f))
    rng = random.Random(args.seed)
    picked = []
    for lang in ["cs", "sk", "en"]:
        lr = [r for r in rows if r["lang"] == lang]
        picked += rng.sample(lr, min(args.per_lang, len(lr)))
    device = str(uuid.uuid4())

    def one(r: dict) -> tuple[dict, list[dict]]:
        t0 = time.monotonic()
        try:
            aid = submit(args.api, device, r["url"])
            out, cl = follow(args.api, aid, t0)
        except (urllib.error.URLError, OSError, ValueError) as exc:
            out, cl = {"error": f"client: {exc}"}, []
        meta = {"article": r["id"], "lang": r["lang"], "domain": r["domain"]}
        return meta | out, [meta | c for c in cl]

    with ThreadPoolExecutor(args.concurrency) as ex:
        res = list(ex.map(one, picked))
    results = [r for r, _ in res]

    OUT.mkdir(parents=True, exist_ok=True)
    cols = ["article", "lang", "domain", "id", "language", "paragraphs", "t_document", "t_first_claim",
            "t_first_verdict", "t_summary", "t_claims_summary", "claims_found", "checked", "labels", "evidence",
            "quotes_dropped", "evidence_quotes_dropped", "bad_offsets", "searches", "search_errors",
            "pages_fetched", "refutes_rejected", "claims_error", "t_error", "error"]
    with (OUT / "m2_smoke.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(results)
    with (OUT / "m2_claims.jsonl").open("w") as f:
        for _, cl in res:
            for c in cl:
                f.write(json.dumps(c, ensure_ascii=False) + "\n")

    ok = [r for r in results if "t_claims_summary" in r and not r.get("claims_error")]
    labels: collections.Counter = collections.Counter()
    for r in ok:
        labels.update(r["labels"])
    summary = {"n": len(results), "ok": len(ok),
               "errors": sorted({r.get("error") or r.get("claims_error") for r in results
                                 if r.get("error") or r.get("claims_error")}),
               "labels": dict(labels)}
    for k in ["t_first_claim", "t_first_verdict", "t_claims_summary"]:
        xs = [r[k] for r in ok if k in r]
        summary[k] = {"p50": pct(xs, 0.5), "p95": pct(xs, 0.95)}
    for k in ["claims_found", "checked", "evidence", "quotes_dropped", "evidence_quotes_dropped", "bad_offsets",
              "searches", "search_errors", "pages_fetched", "refutes_rejected"]:
        summary[k + "_total"] = sum(r.get(k, 0) for r in ok)
    (OUT / "m2_smoke_summary.json").write_text(json.dumps(summary, indent=1))
    print(json.dumps(summary, indent=1), file=sys.stderr)
    print(json.dumps({"articles": {"ok": len(ok), "failed": len(results) - len(ok)}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
