#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
candidate_tag=$(jq -er '.candidate_tag' "$repo/release.json")
cache_schema=$(jq -er '.cache_schema' "$repo/release.json")
local_image="sglang-qwen38-flash-next-sm120:${candidate_tag}"
launcher="$repo/examples/serve-qwen38-flash-next.sh"

for file in README.md RUN.md BENCHMARKS.md CHANGELOG.md NOTICE.md \
  evidence/v0.1.0-rc.9/publication-summary.json "$launcher"; do
  [[ -s "$repo/$file" || -s "$file" ]] || { echo "required file missing: $file" >&2; exit 1; }
done

require_text() {
  local file=$1 expected=$2
  grep -F -- "$expected" "$file" >/dev/null || { echo "${file#$repo/} missing: $expected" >&2; exit 1; }
}

require_text "$repo/README.md" "$local_image"
require_text "$repo/RUN.md" "IMAGE=$local_image"
require_text "$launcher" "IMAGE=\${IMAGE:-${local_image}}"
require_text "$repo/RUN.md" "/srv/cache/sglang-qwen38-flash-next-sm120-${cache_schema}"
require_text "$repo/CHANGELOG.md" "## ${candidate_tag}"
require_text "$repo/BENCHMARKS.md" '95.83%'
require_text "$repo/BENCHMARKS.md" '3772dddaf9b0caf6027d09ca084df2862daedbb3c0961c3b8015c19a3b47205c'
require_text "$repo/BENCHMARKS.md" '0797bb93a90b915d29ccacb068f1ca10bd8a0e62c1c87216a1bd889860019f53'

critical=(
  'TP_SIZE=${TP_SIZE:-2}'
  'EP_SIZE=${EP_SIZE:-2}'
  'CONTEXT_LENGTH=${CONTEXT_LENGTH:-262144}'
  'NEXTN=${NEXTN:-1}'
  '--mem-fraction-static 0.85'
  '--chunked-prefill-size 8192'
  '--linear-attn-prefill-backend flashinfer'
  '--linear-attn-decode-backend flashinfer'
  '--mamba-ssm-dtype bfloat16'
  '--ple-offload-embedding'
  '--reasoning-parser auto'
  '--tool-call-parser auto'
)
for value in "${critical[@]}"; do require_text "$launcher" "$value"; done

if grep -E -- '--enable-hierarchical-cache|--hicache-|SGLANG_HICACHE' "$launcher" >/dev/null; then
  echo "v0.1 launcher unexpectedly enables HiCache" >&2
  exit 1
fi
if grep -F -- '--trust-remote-code' "$launcher" >/dev/null; then
  echo "native Qwen support must not require trust-remote-code" >&2
  exit 1
fi

echo "public documentation valid: ${candidate_tag}, cache ${cache_schema}, SM120-only"
