#!/usr/bin/env bash
# Candidate serving envelope for Qwen3.8-Flash-Next FP8 on two RTX PRO 6000
# Blackwell GPUs (SM120, TP=2). See BENCHMARKS.md for the passing gates and
# remaining experimental scope.
set -euo pipefail

: "${MODEL_DIR:?set MODEL_DIR to the Qwen3.8-Flash-Next-FP8 snapshot directory}"
: "${CACHE_DIR:?set CACHE_DIR to a persistent, image-specific cache directory}"

IMAGE=${IMAGE:-sglang-qwen38-flash-next-sm120:v0.1.0-rc.9}
PORT=${PORT:-8000}
CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0,1}
TP_SIZE=${TP_SIZE:-2}
EP_SIZE=${EP_SIZE:-2}
CONTEXT_LENGTH=${CONTEXT_LENGTH:-262144}
MAX_RUNNING_REQUESTS=${MAX_RUNNING_REQUESTS:-32}
NEXTN=${NEXTN:-1}
CONTAINER_NAME=${CONTAINER_NAME:-qwen38-flash-next-sm120}

if [[ ! -f "$MODEL_DIR/config.json" ]]; then
  echo "MODEL_DIR does not contain config.json: $MODEL_DIR" >&2
  exit 2
fi
if [[ -e "$CACHE_DIR" && ! -d "$CACHE_DIR" ]]; then
  echo "CACHE_DIR exists but is not a directory: $CACHE_DIR" >&2
  exit 2
fi
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
  echo "PORT must be an integer from 1 through 65535" >&2
  exit 2
fi
if [[ "$TP_SIZE" != 2 ]]; then
  echo "v0.1.0-rc.9 is scoped to TP_SIZE=2" >&2
  exit 2
fi
if [[ "$EP_SIZE" != 2 ]]; then
  echo "v0.1.0-rc.9 requires EP_SIZE=2 to preserve 128-column FP8 expert blocks" >&2
  exit 2
fi
if [[ "$CONTEXT_LENGTH" != 262144 ]]; then
  echo "v0.1.0-rc.9 is scoped to the native 262144-token context" >&2
  exit 2
fi
if [[ "$NEXTN" != 0 && "$NEXTN" != 1 ]]; then
  echo "NEXTN must be 0 or 1" >&2
  exit 2
fi
if ! [[ "$MAX_RUNNING_REQUESTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "MAX_RUNNING_REQUESTS must be a positive integer" >&2
  exit 2
fi

mkdir -p "$CACHE_DIR"
model_dir=$(cd "$MODEL_DIR" && pwd)
cache_dir=$(cd "$CACHE_DIR" && pwd)
container_model_path=/models/Qwen/Qwen3.8-Flash-Next-FP8

speculative_args=()
if [[ "$NEXTN" == 1 ]]; then
  speculative_args+=(
    --speculative-algorithm NEXTN
    --speculative-num-steps 3
    --speculative-eagle-topk 1
    --speculative-num-draft-tokens 4
  )
fi

# HiCache is deliberately absent from v0.1. Its Qwen hybrid-cache support and
# dedicated PVC are a v0.2 gate, not an implicit host-path side effect.
exec docker run --rm \
  --name "$CONTAINER_NAME" \
  --entrypoint sglang \
  --gpus all \
  --shm-size 64g \
  --ulimit memlock=-1 \
  --publish "${PORT}:8000" \
  --volume "${model_dir}:${container_model_path}:ro" \
  --volume "${cache_dir}:/root/.cache" \
  --env CUDA_VISIBLE_DEVICES="$CUDA_VISIBLE_DEVICES" \
  --env SGLANG_ENABLE_HEALTH_ENDPOINT_GENERATION=0 \
  --env TORCHINDUCTOR_CACHE_DIR=/root/.cache/torchinductor \
  --env TILELANG_CACHE_DIR=/root/.cache/tilelang \
  --env TRITON_CACHE_DIR=/root/.cache/triton \
  "$IMAGE" \
  serve \
  --model-path "$container_model_path" \
  --served-model-name qwen38-flash-next-sm120 \
  --tp "$TP_SIZE" \
  --ep "$EP_SIZE" \
  --context-length "$CONTEXT_LENGTH" \
  --mem-fraction-static 0.85 \
  --chunked-prefill-size 8192 \
  --linear-attn-prefill-backend flashinfer \
  --linear-attn-decode-backend flashinfer \
  --mamba-ssm-dtype bfloat16 \
  --ple-offload-embedding \
  --max-running-requests "$MAX_RUNNING_REQUESTS" \
  --cuda-graph-max-bs 32 \
  --reasoning-parser auto \
  --tool-call-parser auto \
  --enable-metrics \
  --enable-cache-report \
  "${speculative_args[@]+"${speculative_args[@]}"}" \
  --host 0.0.0.0 \
  --port 8000
