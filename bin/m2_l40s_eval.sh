#!/bin/sh
# Waits for the qctl window on the L40S sandbox (serve_qwen36.sh writes
# DF_READY), tunnels the vLLM port, runs the M2 stance eval (CsFEVER) and
# the M2 smoke, then closes the window (DF_DONE). Logs in run/bench/.
set -u
cd "$(dirname "$0")/.."
R=/srv/work/deepfake
until ssh tcloud "test -e $R/DF_READY"; do
  ssh tcloud "~/bin/qctl ls" 2>/dev/null | grep -q "failed .*deepfake-m2-eval-qwen36-dates" && { echo "window job failed"; exit 1; }
  sleep 60
done
echo "window ready $(date)"
ssh -N -o ExitOnForwardFailure=yes -L 18005:127.0.0.1:8005 tcloud &
TUN=$!
trap 'kill $TUN 2>/dev/null; ssh tcloud "touch '$R'/DF_DONE"' EXIT INT TERM
sleep 5
(cd api && go build -o ../run/stance-eval ./cmd/stance-eval)
LLM_BASE_URL=http://127.0.0.1:18005/v1 LLM_MODEL=qwen36 ./run/stance-eval \
  -in run/data/csfever/test.jsonl -out run/bench -per-label 100 -concurrency 16 > run/bench/m2_stance.out 2>&1
echo "stance eval exit $? $(date)"
M2_LLM_BASE_URL=http://127.0.0.1:18005/v1 M2_LLM_MODEL=qwen36 bin/m2_smoke.sh --per-lang 3 --concurrency 2 > run/bench/m2_smoke.out 2>&1
echo "smoke exit $? $(date)"
