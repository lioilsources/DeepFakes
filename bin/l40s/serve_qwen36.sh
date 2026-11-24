#!/bin/bash
# DeepFake (Pravdomer) eval window: serve Qwen3.6-35B-A3B-FP8 on 127.0.0.1:8005
# until /srv/work/deepfake/DF_DONE exists or guard expires. Started by qctl.
set -u
D=/srv/work/deepfake
rm -f $D/DF_READY $D/DF_DONE
# Finish/verify the download (idempotent).
docker run --rm -v /srv/hf:/root/.cache/huggingface --entrypoint hf vllm/vllm-openai:latest download Qwen/Qwen3.6-35B-A3B-FP8 >/dev/null 2>&1 || { echo "download failed"; exit 1; }
docker rm -f df-qwen36 >/dev/null 2>&1
docker run -d --name df-qwen36 --gpus all --ipc=host -p 127.0.0.1:8005:8000 \
  -v /srv/hf:/root/.cache/huggingface -v /cold:/cold:ro vllm/vllm-openai:latest \
  --model Qwen/Qwen3.6-35B-A3B-FP8 --served-model-name qwen36 \
  --max-model-len 16384 --gpu-memory-utilization 0.92 --kv-cache-dtype fp8 \
  --max-num-seqs 32 --enable-prefix-caching --reasoning-parser qwen3 \
  --limit-mm-per-prompt "{\"image\":0,\"video\":0}" || exit 1
trap "docker rm -f df-qwen36 >/dev/null 2>&1" EXIT
for i in $(seq 1 120); do
  curl -sf 127.0.0.1:8005/v1/models >/dev/null && break
  docker ps -q -f name=df-qwen36 | grep -q . || { docker logs --tail 40 df-qwen36; echo "vllm died"; exit 1; }
  sleep 10
done
curl -sf 127.0.0.1:8005/v1/models >/dev/null || { docker logs --tail 40 df-qwen36; echo "vllm not healthy"; exit 1; }
touch $D/DF_READY
end=$(( $(date +%s) + ${GUARD_MIN:-150}*60 ))
while [ ! -e $D/DF_DONE ] && [ $(date +%s) -lt $end ]; do sleep 20; done
echo "window closed"
