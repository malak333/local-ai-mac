#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

echo "Checking ${LOCAL_AI_BASE_URL}..."
curl --fail --silent --show-error "${LOCAL_AI_BASE_URL}/health" | jq .

echo "Checking model alias..."
models="$(curl --fail --silent --show-error "${LOCAL_AI_BASE_URL}/v1/models")"
echo "${models}" | jq .
echo "${models}" | jq --exit-status --arg model "${LOCAL_AI_MODEL_ALIAS}" \
  '.data | any(.id == $model)' >/dev/null

echo "Running a short completion..."
response="$(curl --fail --silent --show-error --max-time 300 \
  "${LOCAL_AI_BASE_URL}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg model "${LOCAL_AI_MODEL_ALIAS}" '{
    model: $model,
    messages: [{role: "user", content: "Reply with exactly: LOCAL_AI_OK"}],
    temperature: 0,
    max_tokens: 512,
    chat_template_kwargs: {enable_thinking: false}
  }')")"

echo "${response}" | jq '{content: .choices[0].message.content, timings: .timings}'
echo "${response}" | jq --exit-status \
  '.choices[0].message.content | contains("LOCAL_AI_OK")' >/dev/null
echo "Health check passed."
