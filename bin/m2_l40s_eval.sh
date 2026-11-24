#!/bin/sh
# Waits for the qctl window on the L40S sandbox (serve_qwen36.sh writes
# DF_READY), tunnels the vLLM port, runs the M2 stance eval (CsFEVER) and
# the M2 smoke SMOKE_RUNS times (default 1; runs >1 keep their outputs as
# m2_*_rN.*), then closes the window (DF_DONE). Logs in run/bench/.
set -u
cd "$(dirname "$0")/.."
R=/srv/work/deepfake
JOB=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' bin/l40s/job.json)
RUNS=${SMOKE_RUNS:-1}
# A stale DF_READY can outlive an earlier window, so also require our job to
# be running and vLLM to answer.
until ssh tcloud "~/bin/qctl ls | grep -q '^running  *$JOB ' && test -e $R/DF_READY && curl -sf -m 5 127.0.0.1:8005/v1/models >/dev/null"; do
  ssh tcloud "~/bin/qctl ls" 2>/dev/null | grep -q "failed .*$JOB " && { echo "window job failed"; exit 1; }
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
i=1
while [ $i -le $RUNS ]; do
  M2_LLM_BASE_URL=http://127.0.0.1:18005/v1 M2_LLM_MODEL=qwen36 bin/m2_smoke.sh --per-lang 3 --concurrency 2 > run/bench/m2_smoke.out 2>&1
  echo "smoke $i exit $? $(date)"
  if [ $RUNS -gt 1 ]; then
    for f in m2_smoke.csv m2_claims.jsonl m2_smoke_summary.json m2_smoke.out m2_api.log; do
      cp run/bench/$f run/bench/${f%.*}_r$i.${f##*.}
    done
  fi
  i=$((i + 1))
done
