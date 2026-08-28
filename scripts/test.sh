#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

for script in "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/local-ai" "${SCRIPT_DIR}/opencode-wrapper"; do
  bash -n "${script}"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -P "${SCRIPT_DIR}" "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/local-ai"
fi

jq --exit-status . "${REPO_DIR}/config/opencode.json" >/dev/null

default_context="$(
  unset LOCAL_AI_CONTEXT
  # shellcheck source=common.sh
  source "${SCRIPT_DIR}/common.sh"
  printf '%s' "${LOCAL_AI_CONTEXT}"
)"
configured_context="$(
  jq --raw-output \
    '.provider["llama.cpp"].models["qwen36-local"].limit.context' \
    "${REPO_DIR}/config/opencode.json"
)"
if [[ "${default_context}" != "${configured_context}" ]]; then
  echo "Server and OpenCode context limits do not match: ${default_context} != ${configured_context}" >&2
  exit 1
fi

jq --exit-status '
  .tools.webfetch == true
  and .tools.websearch == true
  and .permission == "allow"
' "${REPO_DIR}/config/opencode.json" >/dev/null || {
  echo "OpenCode web tools and full auto-approval are not enabled." >&2
  exit 1
}

wrapper_environment="$(OPENCODE_REAL_BIN=/usr/bin/env "${SCRIPT_DIR}/opencode-wrapper")"
if ! grep -qx 'OPENCODE_ENABLE_EXA=1' <<<"${wrapper_environment}"; then
  echo "OpenCode launcher does not enable Exa web search." >&2
  exit 1
fi
if ! grep -qx 'OPENCODE_DISABLE_EXTERNAL_SKILLS=1' <<<"${wrapper_environment}"; then
  echo "OpenCode launcher does not suppress the oversized external skill catalog." >&2
  exit 1
fi

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
