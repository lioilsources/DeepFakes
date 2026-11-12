#!/usr/bin/env python3
"""Collect Tier 1 eval article candidates from outlet RSS feeds.

Reads eval/tier1/outlets.csv, fetches each feed, samples a balanced set per
language and stratum, extracts the main text with trafilatura and writes:

  eval/tier1/articles.csv          committed: id, lang, outlet, stratum, url, title, published, sha256
  run/eval/articles/<id>.json      gitignored: full extracted text + metadata (copyrighted, never commit)

The extracted text is treated as data only. Respects robots.txt per domain.
Usage: .venv/bin/python -I bin/eval_collect_articles.py [--per-lang 50] [--seed 1112]
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
import sys
import time
import urllib.robotparser
from collections import defaultdict
from pathlib import Path
from urllib.parse import urlparse

import feedparser
import trafilatura

ROOT = Path(__file__).resolve().parent.parent
OUTLETS = ROOT / "eval/tier1/outlets.csv"
OUT_CSV = ROOT / "eval/tier1/articles.csv"
OUT_DIR = ROOT / "run/eval/articles"
UA = "DeepFakeBot/0.1 (+https://github.com/lioilsources/DeepFakes)"
MIN_CHARS = 1200  # skip short notices, galleries, live tickers
# Target share of each stratum within a language; leftovers are filled from 'news'.
STRATUM_SHARE = {"news": 0.5, "opinion": 0.2, "tabloid": 0.15, "listed": 0.15}

_robots: dict[str, urllib.robotparser.RobotFileParser | None] = {}


MIN_TEXT_CHARS = 600  # shorter = teaser, gallery or error page


def allowed(url: str) -> bool:
    host = urlparse(url).scheme + "://" + urlparse(url).netloc
    if host not in _robots:
        rp = urllib.robotparser.RobotFileParser(host + "/robots.txt")
        try:
            rp.read()
        except Exception:
            rp = None  # unreachable robots.txt: treat as allowed (standard behaviour)
        _robots[host] = rp
    rp = _robots[host]
    return True if rp is None else rp.can_fetch(UA, url)


def feed_items(row: dict) -> list[dict]:
    parsed = feedparser.parse(row["feed"], agent=UA)
    items = []
    for e in parsed.entries:
        link = e.get("link")
        if not link:
            continue
        items.append({
            "lang": row["lang"], "outlet": row["outlet"], "domain": row["domain"],
            "stratum": row["stratum"], "url": link, "title": e.get("title", "").strip(),
            "published": e.get("published", e.get("updated", "")),
        })
    return items


def extract(url: str) -> dict | None:
    html = trafilatura.fetch_url(url)
    if not html:
        return None
    doc = trafilatura.bare_extraction(html, url=url, with_metadata=True, include_comments=False)
    if doc is None:
        return None
    d = doc.as_dict() if hasattr(doc, "as_dict") else dict(doc)
    text = (d.get("text") or "").strip()
    if len(text) < MIN_CHARS:
        return None
    return {k: d.get(k) for k in ("title", "author", "date", "sitename", "hostname", "language")} | {"text": text}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-lang", type=int, default=50)
    ap.add_argument("--max-per-outlet", type=int, default=6)
    ap.add_argument("--seed", type=int, default=1112)
    ap.add_argument("--langs", default="", help="re-collect only these languages (comma list); keep the rest")
    args = ap.parse_args()
    rng = random.Random(args.seed)

    with OUTLETS.open() as f:
        outlets = list(csv.DictReader(f))
    keep: list[dict] = []
    if args.langs:
        only = set(args.langs.split(","))
        if OUT_CSV.exists():
            with OUT_CSV.open() as f:
                keep = [r for r in csv.DictReader(f) if r["lang"] not in only]
        for old in OUT_DIR.glob("*.json"):
            if old.name[:2] in only:
                old.unlink()
        outlets = [o for o in outlets if o["lang"] in only]

    pool: dict[tuple[str, str], list[dict]] = defaultdict(list)
    feed_report = []
    for row in outlets:
        try:
            items = feed_items(row)
        except Exception as exc:  # noqa: BLE001 - keep going, report per feed
            items = []
            print(f"feed error {row['outlet']}: {exc}", file=sys.stderr)
        feed_report.append((row["lang"], row["outlet"], len(items)))
        rng.shuffle(items)
        pool[(row["lang"], row["stratum"])].extend(items[: args.max_per_outlet * 3])

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    chosen: list[dict] = list(keep)
    for lang in sorted({o["lang"] for o in outlets}):
        quota = {s: round(args.per_lang * share) for s, share in STRATUM_SHARE.items()}
        got: list[dict] = []
        per_outlet: dict[str, int] = defaultdict(int)
        # Identical text under different URLs = consent wall, section page or
        # paywall teaser, not an article: drop every copy and ban the hash.
        banned: set[str] = set()
        for stratum in ["listed", "tabloid", "opinion", "news"]:
            want = quota[stratum] if stratum != "news" else args.per_lang - len(got)
            for it in pool[(lang, stratum)]:
                if sum(1 for g in got if g["stratum"] == stratum) >= want:
                    break
                if per_outlet[it["outlet"]] >= args.max_per_outlet or not allowed(it["url"]):
                    continue
                try:
                    doc = extract(it["url"])
                except Exception as exc:  # noqa: BLE001
                    print(f"extract error {it['url']}: {exc}", file=sys.stderr)
                    doc = None
                time.sleep(1.0)  # politeness
                if not doc or len(doc["text"]) < MIN_TEXT_CHARS:
                    continue
                sha = hashlib.sha256(doc["text"].encode()).hexdigest()
                if sha in banned:
                    continue
                dup = [g for g in got if g["sha256"] == sha]
                if dup:
                    banned.add(sha)
                    for g in dup:
                        got.remove(g)
                        per_outlet[g["outlet"]] -= 1
                    print(f"duplicate text dropped: {it['outlet']} {it['url']}", file=sys.stderr)
                    continue
                got.append(it | {"sha256": sha, "doc": doc})
                per_outlet[it["outlet"]] += 1
            # unmet quota of minor strata rolls over to 'news' automatically
        for i, it in enumerate(got, 1):
            it["id"] = f"{lang}-{i:03d}"
            (OUT_DIR / f"{it['id']}.json").write_text(json.dumps(it, ensure_ascii=False, indent=1))
            del it["doc"]
        print(f"{lang}: {len(got)} articles", file=sys.stderr)
        chosen.extend(got)

    cols = ["id", "lang", "outlet", "domain", "stratum", "url", "title", "published", "sha256"]
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(chosen)
    (ROOT / f"run/eval/feed_report{'-' + args.langs if args.langs else ''}.tsv").write_text("".join(f"{l}\t{o}\t{n}\n" for l, o, n in feed_report))
    print(f"wrote {len(chosen)} rows to {OUT_CSV.relative_to(ROOT)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
