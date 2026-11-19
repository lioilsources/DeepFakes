#!/bin/sh
# Builds and starts the API locally (in-memory store), runs the M2 claims
# smoke test against the LLM gateway from .env, then stops the API.
# Meant for: sparkctl exec deepfake qwen36 <min> <prio> "<title>" -- bin/m2_smoke.sh
set -eu
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
# Override the gateway, e.g. the L40S sandbox: M2_LLM_BASE_URL=… M2_LLM_MODEL=…
LLM_BASE_URL=${M2_LLM_BASE_URL:-$LLM_BASE_URL}
LLM_MODEL=${M2_LLM_MODEL:-${LLM_MODEL:-openclaw-default}}
export LLM_BASE_URL LLM_MODEL
mkdir -p run/bench
(cd api && go build -o ../run/pravdomer-api ./cmd/pravdomer-api)
PORT=${M2_PORT:-18097}
LISTEN_ADDR=127.0.0.1:$PORT SUBMIT_BURST=1000 DATABASE_URL= LOG_LEVEL=${M2_LOG_LEVEL:-info} \
  ./run/pravdomer-api > run/bench/m2_api.log 2>&1 &
API_PID=$!
trap 'kill $API_PID 2>/dev/null || true' EXIT INT TERM
for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break
  sleep 0.2
done
.venv/bin/python -I bin/m2_smoke.py --api "http://127.0.0.1:$PORT" "$@"
