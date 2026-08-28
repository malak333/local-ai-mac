#!/usr/bin/env bash

set -euo pipefail

LOCAL_AI_HOST="${LOCAL_AI_HOST:-127.0.0.1}"
LOCAL_AI_PORT="${LOCAL_AI_PORT:-8080}"
LOCAL_AI_MODEL_ALIAS="${LOCAL_AI_MODEL_ALIAS:-qwen36-local}"
LOCAL_AI_MODEL="${LOCAL_AI_MODEL:-bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:IQ4_XS}"
LOCAL_AI_CONTEXT="${LOCAL_AI_CONTEXT:-65536}"
LOCAL_AI_OUTPUT="${LOCAL_AI_OUTPUT:-4096}"
LOCAL_AI_CACHE_RAM="${LOCAL_AI_CACHE_RAM:-2048}"
LOCAL_AI_STATE_DIR="${LOCAL_AI_STATE_DIR:-${HOME}/Library/Application Support/local-ai-mac}"
LOCAL_AI_PID_FILE="${LOCAL_AI_PID_FILE:-${LOCAL_AI_STATE_DIR}/server.pid}"
LOCAL_AI_LOG_FILE="${LOCAL_AI_LOG_FILE:-${LOCAL_AI_STATE_DIR}/server.log}"
LOCAL_AI_LAUNCHD_LABEL="${LOCAL_AI_LAUNCHD_LABEL:-com.malak333.local-ai-mac}"
LOCAL_AI_BASE_URL="http://${LOCAL_AI_HOST}:${LOCAL_AI_PORT}"

local_ai_pid() {
  local launchd_state
  local launchd_pid
  if launchd_state="$(launchctl print "gui/$(id -u)/${LOCAL_AI_LAUNCHD_LABEL}" 2>/dev/null)"; then
    launchd_pid="$(printf '%s\n' "${launchd_state}" \
      | awk '/^[[:space:]]*pid = / {print $3; exit}')"
    if [[ -n "${launchd_pid}" ]]; then
      printf '%s\n' "${launchd_pid}"
    fi
    return
  fi
  if [[ -f "${LOCAL_AI_PID_FILE}" ]]; then
    tr -d '[:space:]' < "${LOCAL_AI_PID_FILE}"
  fi
}

local_ai_running() {
  local pid
  local process_command
  pid="$(local_ai_pid)"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  process_command="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
  [[ "${process_command}" == *"llama serve"* && "${process_command}" == *"--port ${LOCAL_AI_PORT}"* ]]
}

local_ai_wait_ready() {
  local attempts="${1:-120}"
  local delay="${2:-2}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --max-time 2 "${LOCAL_AI_BASE_URL}/health" >/dev/null 2>&1; then
      return 0
    fi
    if ! local_ai_running; then
      return 1
    fi
    sleep "${delay}"
  done
  return 1
}
