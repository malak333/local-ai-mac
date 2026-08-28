#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

output_file="$(mktemp -t local-ai-opencode-web.XXXXXX)"
trap 'rm -f "${output_file}"' EXIT

OPENCODE_ENABLE_EXA=1 opencode run \
  --pure \
  --dir "${REPO_DIR}" \
  --model "llama.cpp/${LOCAL_AI_MODEL_ALIAS}" \
  --format json \
  'Do not modify files or run shell commands. Use websearch to find the official OpenCode tools documentation, then use webfetch to read that URL. Report the URL and end with LOCAL_WEB_TOOLS_OK.' \
  | tee "${output_file}"

if ! grep -q '"tool":"websearch"' "${output_file}"; then
  echo "OpenCode web smoke test did not call websearch." >&2
  exit 1
fi
if ! grep -q '"tool":"webfetch"' "${output_file}"; then
  echo "OpenCode web smoke test did not call webfetch." >&2
  exit 1
fi
if ! grep -q 'LOCAL_WEB_TOOLS_OK' "${output_file}"; then
  echo "OpenCode web smoke test did not return its success marker." >&2
  exit 1
fi

echo "OpenCode web-search and web-fetch smoke test passed."
