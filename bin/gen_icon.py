"""Generate app icon candidates with FLUX.1-dev in ComfyUI on SPARK.

Run through the broker:
  sparkctl exec deepfake comfyui 20 10 "pravdomer icon" -- .venv/bin/python -I bin/gen_icon.py --seeds 4
Outputs: run/icon/candidate-<seed>.png. Last stdout line: {"images":{"ok":N,"failed":M}}
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "run/icon"

PROMPT = (
    "Minimal flat vector app icon, centered symbol on a smooth deep teal background (#3E6A6B), "
    "a stylised glass thermometer whose bulb is a speech bubble, the mercury a warm gradient "
    "from cool teal to amber to red-orange, clean geometric shapes, soft subtle shadow, "
    "bold simple silhouette readable at small size, generous padding, modern iOS app icon style, "
    "no text, no letters, no border, no frame"
)


def env_file() -> dict[str, str]:
    vals = {}
    p = ROOT / ".env"
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                vals[k.strip()] = v.strip()
    return vals


def workflow(seed: int, prompt: str, steps: int) -> dict:
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "flux1-dev.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "DualCLIPLoader",
              "inputs": {"clip_name1": "clip_l.safetensors", "clip_name2": "t5xxl_fp16.safetensors", "type": "flux"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["2", 0]}},
        "5": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["4", 0], "guidance": 3.5}},
        "6": {"class_type": "EmptySD3LatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
        "7": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["5", 0], "negative": ["5", 0],
                                                    "latent_image": ["6", 0], "seed": seed, "steps": steps, "cfg": 1.0,
                                                    "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["3", 0]}},
        "9": {"class_type": "SaveImage", "inputs": {"images": ["8", 0], "filename_prefix": "pravdomer_icon"}},
    }


def call(base: str, path: str, data: dict | None = None) -> dict:
    req = urllib.request.Request(base + path, data=json.dumps(data).encode() if data else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=4)
    ap.add_argument("--first-seed", type=int, default=1112)
    ap.add_argument("--steps", type=int, default=28)
    ap.add_argument("--prompt", default=PROMPT)
    args = ap.parse_args()
    base = os.environ.get("COMFY_URL") or env_file().get("COMFY_URL") or "http://localhost:8188"
    OUT.mkdir(parents=True, exist_ok=True)
    client = str(uuid.uuid4())
    ok = failed = 0
    for seed in range(args.first_seed, args.first_seed + args.seeds):
        try:
            res = call(base, "/prompt", {"prompt": workflow(seed, args.prompt, args.steps), "client_id": client})
            if res.get("node_errors"):
                raise RuntimeError(f"node_errors: {res['node_errors']}")
            pid = res["prompt_id"]
            deadline = time.time() + 600
            while time.time() < deadline:
                hist = call(base, f"/history/{pid}")
                if pid in hist:
                    break
                time.sleep(2)
            else:
                raise TimeoutError("render timeout")
            entry = hist[pid]
            if entry.get("status", {}).get("status_str") == "error":
                raise RuntimeError(json.dumps(entry["status"])[:300])
            img = entry["outputs"]["9"]["images"][0]
            q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img["subfolder"], "type": img["type"]})
            with urllib.request.urlopen(f"{base}/view?{q}", timeout=60) as r:
                (OUT / f"candidate-{seed}.png").write_bytes(r.read())
            ok += 1
            print(f"ok seed {seed}", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001 - report and continue with next seed
            failed += 1
            print(f"FAILED seed {seed}: {exc}", file=sys.stderr)
    print(json.dumps({"images": {"ok": ok, "failed": failed}}))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
