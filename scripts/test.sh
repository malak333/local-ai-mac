#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

for script in "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/local-ai"; do
  bash -n "${script}"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -P "${SCRIPT_DIR}" "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/local-ai"
fi

jq --exit-status . "${REPO_DIR}/config/opencode.json" >/dev/null

for required in llama opencode curl jq; do
  command -v "${required}" >/dev/null 2>&1 || {
    echo "Missing required command: ${required}" >&2
    exit 1
  }
done

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "Expected an Apple Silicon Mac." >&2
  exit 1
fi

echo "Static checks passed."
