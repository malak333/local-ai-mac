#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "This setup requires an Apple Silicon Mac." >&2
  exit 1
fi

memory_bytes="$(sysctl -n hw.memsize)"
if ((memory_bytes < 32 * 1024 * 1024 * 1024)); then
  echo "Warning: the default 35B model is intended for a Mac with at least 32 GB RAM." >&2
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh" >&2
  exit 1
fi

if ! command -v llama >/dev/null 2>&1; then
  brew install llama.cpp
fi

if ! command -v opencode >/dev/null 2>&1; then
  brew install anomalyco/tap/opencode
fi

mkdir -p "${OPENCODE_CONFIG_DIR}"
if [[ -e "${OPENCODE_CONFIG_FILE}" ]] && ! cmp -s "${REPO_DIR}/config/opencode.json" "${OPENCODE_CONFIG_FILE}"; then
  backup="${OPENCODE_CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
  cp "${OPENCODE_CONFIG_FILE}" "${backup}"
  echo "Backed up existing OpenCode config to ${backup}"
fi
cp "${REPO_DIR}/config/opencode.json" "${OPENCODE_CONFIG_FILE}"

echo "llama.cpp: $(llama --version 2>&1 | head -n 1)"
echo "OpenCode: $(opencode --version)"
echo "OpenCode config: ${OPENCODE_CONFIG_FILE}"
echo
echo "Setup complete. Run: make start"
