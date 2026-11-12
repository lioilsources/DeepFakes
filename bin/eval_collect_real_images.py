#!/usr/bin/env python3
"""Collect real (camera) photos from Wikimedia Commons for the image eval set.

Goal: measure false positives of synthetic-image detectors on genuine photos,
so we prefer news-like scenes, recent uploads (2024+), camera EXIF present,
free licence, and exclude anything in AI-generated categories.

  eval/tier1/images_real.csv     committed: id, title, url, licence, author, camera, taken, topic, sha256
  run/eval/images/real/<id>.jpg  gitignored: original file (no re-encoding)

Usage: .venv/bin/python -I bin/eval_collect_real_images.py [--n 100]
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_CSV = ROOT / "eval/tier1/images_real.csv"
OUT_DIR = ROOT / "run/eval/images/real"
API = "https://commons.wikimedia.org/w/api.php"
UA = os.environ.get("BOT_USER_AGENT", "DeepFakeBot/0.1 (+https://github.com/lioilsources/DeepFakes)")
# Topics mirror eval/tier1/image_prompts.csv so real and synthetic sets are comparable.
TOPICS = ["protest", "press conference", "flood", "parliament speech", "street market", "hospital",
          "soldiers", "concert crowd", "wildfire", "portrait", "politician", "traffic accident",
          "refugees", "farmers", "election", "storm damage", "city street night", "classroom",
          "football match", "police"]
FREE = re.compile(r"^(cc0|cc[- ]by(-sa)?[- ]\d|public domain|pd)", re.I)
BAD_CAT = re.compile(r"(AI[- ]generated|artificial intelligence|Midjourney|Stable Diffusion|DALL|Flux|composit|"
                     r"photomontage|manipulated|edited)", re.I)
MAX_BYTES = 15_000_000


def api(params: dict) -> dict:
    url = API + "?" + urllib.parse.urlencode(params | {"format": "json", "formatversion": 2})
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def fetch(url: str, tries: int = 5) -> bytes | None:
    """Downloads with backoff; Commons rate-limits original-file downloads (HTTP 429)."""
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return urllib.request.urlopen(req, timeout=120).read()
        except urllib.error.HTTPError as exc:
            if exc.code != 429:
                return None
            wait = int(exc.headers.get("Retry-After") or 0) or 15 * (i + 1)
            print(f"429, waiting {wait}s", file=sys.stderr, flush=True)
            time.sleep(wait)
    return None


def candidates(topic: str) -> list[dict]:
    data = api({
        "action": "query", "generator": "search", "gsrnamespace": 6, "gsrlimit": 40,
        "gsrsearch": f'{topic} filemime:image/jpeg fileres:>1000',
        "prop": "imageinfo|categories", "cllimit": "max",
        "iiprop": "url|size|sha1|extmetadata|metadata|timestamp", "iiextmetadatafilter":
            "LicenseShortName|Artist|DateTimeOriginal|ImageDescription",
    })
    return data.get("query", {}).get("pages", [])


def write_rows(rows: list[dict]) -> None:
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else ["id"])
        w.writeheader()
        w.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    args = ap.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    per_topic = max(1, args.n // len(TOPICS))
    rows: list[dict] = []
    seen: set[str] = set()
    for topic in TOPICS:
        got = 0
        for page in candidates(topic):
            if got >= per_topic or len(rows) >= args.n:
                break
            cats = " ".join(c["title"] for c in page.get("categories", []))
            if BAD_CAT.search(cats) or BAD_CAT.search(page["title"]):
                continue
            ii = (page.get("imageinfo") or [{}])[0]
            meta = {m["name"]: m["value"] for m in (ii.get("metadata") or []) if isinstance(m, dict)}
            em = {k: v.get("value", "") for k, v in (ii.get("extmetadata") or {}).items()}
            lic = em.get("LicenseShortName", "")
            camera = f"{meta.get('Make', '')} {meta.get('Model', '')}".strip()
            taken = str(meta.get("DateTimeOriginal", em.get("DateTimeOriginal", "")))
            year = re.search(r"(20\d\d)", taken)
            if not camera or not FREE.search(lic) or not year or int(year.group(1)) < 2023:
                continue
            if ii.get("size", 0) > MAX_BYTES or ii.get("sha1") in seen:
                continue
            seen.add(ii["sha1"])
            rid = f"real-{len(rows) + 1:03d}"
            blob = fetch(ii["url"])
            if blob is None:
                continue
            (OUT_DIR / f"{rid}.jpg").write_bytes(blob)
            artist = re.sub(r"<[^>]+>", "", em.get("Artist", "")).strip()[:120]
            rows.append({"id": rid, "title": page["title"], "url": ii.get("descriptionurl", ii["url"]),
                         "licence": lic, "author": artist, "camera": camera, "taken": taken[:19],
                         "topic": topic, "width": ii.get("width"), "height": ii.get("height"),
                         "sha256": hashlib.sha256(blob).hexdigest()})
            write_rows(rows)  # incremental: a stopped run keeps its manifest
            got += 1
            time.sleep(3)
        print(f"{topic}: {got}", file=sys.stderr, flush=True)
    write_rows(rows)
    print(f"wrote {len(rows)} rows to {OUT_CSV.relative_to(ROOT)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
