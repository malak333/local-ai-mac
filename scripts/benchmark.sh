#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

mkdir -p "${REPO_DIR}/results"
timestamp="$(date +%Y%m%d-%H%M%S)"
output_file="${REPO_DIR}/results/benchmark-${timestamp}.json"

curl --fail --silent --show-error --max-time 600 \
  "${LOCAL_AI_BASE_URL}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg model "${LOCAL_AI_MODEL_ALIAS}" '{
    model: $model,
    messages: [{role: "user", content: "Write a thread-safe least-recently-used cache in Rust and include focused unit tests."}],
    temperature: 0.2,
    max_tokens: 1024,
    chat_template_kwargs: {enable_thinking: false}
  }')" > "${output_file}"

jq '{
  created: .created,
  model: .model,
  usage: .usage,
  timings: .timings
}' "${output_file}"
echo "Full response: ${output_file}"
