#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

output_file="$(mktemp -t local-ai-opencode.XXXXXX)"
trap 'rm -f "${output_file}"' EXIT

opencode run \
  --pure \
  --dir "${REPO_DIR}" \
  --model "llama.cpp/${LOCAL_AI_MODEL_ALIAS}" \
  --format json \
  'Do not modify any files. Read README.md with your file tool, identify the default local model, then end your answer with LOCAL_OPENCODE_OK.' \
  | tee "${output_file}"

if ! grep -q 'LOCAL_OPENCODE_OK' "${output_file}"; then
  echo "OpenCode smoke test did not return its success marker." >&2
  exit 1
fi

echo "OpenCode end-to-end smoke test passed."
