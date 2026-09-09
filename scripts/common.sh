#!/usr/bin/env bash

set -euo pipefail

LOCAL_AI_HOST="${LOCAL_AI_HOST:-127.0.0.1}"
LOCAL_AI_PORT="${LOCAL_AI_PORT:-8080}"
LOCAL_AI_MODEL_ALIAS="${LOCAL_AI_MODEL_ALIAS:-qwen36-local}"
LOCAL_AI_DEFAULT_MODEL_REPO="bartowski/Qwen_Qwen3.6-35B-A3B-GGUF"
LOCAL_AI_MODEL="${LOCAL_AI_MODEL:-${LOCAL_AI_DEFAULT_MODEL_REPO}:IQ4_XS}"
LOCAL_AI_CONTEXT="${LOCAL_AI_CONTEXT:-262144}"
LOCAL_AI_OUTPUT="${LOCAL_AI_OUTPUT:-4096}"
LOCAL_AI_CACHE_RAM="${LOCAL_AI_CACHE_RAM:-2048}"
LOCAL_AI_STATE_DIR="${LOCAL_AI_STATE_DIR:-${HOME}/Library/Application Support/local-ai-mac}"
LOCAL_AI_MMPROJ_WAS_SET="${LOCAL_AI_MMPROJ+x}"
LOCAL_AI_MMPROJ_URL_WAS_SET="${LOCAL_AI_MMPROJ_URL+x}"
LOCAL_AI_MMPROJ_SHA256_WAS_SET="${LOCAL_AI_MMPROJ_SHA256+x}"
LOCAL_AI_MMPROJ="${LOCAL_AI_MMPROJ:-${LOCAL_AI_STATE_DIR}/models/mmproj-Qwen_Qwen3.6-35B-A3B-f16.gguf}"
LOCAL_AI_MMPROJ_URL="${LOCAL_AI_MMPROJ_URL:-https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF/resolve/main/mmproj-Qwen_Qwen3.6-35B-A3B-f16.gguf}"
LOCAL_AI_MMPROJ_SHA256="${LOCAL_AI_MMPROJ_SHA256:-67924785ff1885c2b34c15d0e52979e991acca64221694ba2cc3a6474a053fb4}"
LOCAL_AI_DISABLE_VISION="${LOCAL_AI_DISABLE_VISION:-0}"
LOCAL_AI_PID_FILE="${LOCAL_AI_PID_FILE:-${LOCAL_AI_STATE_DIR}/server.pid}"
LOCAL_AI_LOG_FILE="${LOCAL_AI_LOG_FILE:-${LOCAL_AI_STATE_DIR}/server.log}"
LOCAL_AI_LAUNCHD_LABEL="${LOCAL_AI_LAUNCHD_LABEL:-com.malak333.local-ai-mac}"
LOCAL_AI_BASE_URL="http://${LOCAL_AI_HOST}:${LOCAL_AI_PORT}"

local_ai_validate_projector_configuration() {
  local model_repo="${LOCAL_AI_MODEL%%:*}"

  case "${LOCAL_AI_DISABLE_VISION}" in
    0|1) ;;
    *) echo "LOCAL_AI_DISABLE_VISION must be 0 or 1." >&2; return 1 ;;
  esac
  if [[ "${LOCAL_AI_DISABLE_VISION}" == "1" ]]; then
    return 0
  fi

  if [[ "${model_repo}" != "${LOCAL_AI_DEFAULT_MODEL_REPO}" ]]; then
    if [[ -z "${LOCAL_AI_MMPROJ_WAS_SET}" || -z "${LOCAL_AI_MMPROJ_SHA256_WAS_SET}" ]]; then
      echo "LOCAL_AI_MODEL uses a different model repository; set a matching LOCAL_AI_MMPROJ and LOCAL_AI_MMPROJ_SHA256, or set LOCAL_AI_DISABLE_VISION=1." >&2
      return 1
    fi
    if [[ ! -f "${LOCAL_AI_MMPROJ}" && -z "${LOCAL_AI_MMPROJ_URL_WAS_SET}" ]]; then
      echo "Custom projector is absent; also set LOCAL_AI_MMPROJ_URL so it can be downloaded." >&2
      return 1
    fi
  fi
}

local_ai_ensure_projector() {
  local actual_sha256
  local download_file

  local_ai_validate_projector_configuration
  if [[ "${LOCAL_AI_DISABLE_VISION}" == "1" ]]; then
    return 0
  fi

  if [[ -f "${LOCAL_AI_MMPROJ}" ]]; then
    actual_sha256="$(shasum -a 256 "${LOCAL_AI_MMPROJ}" | awk '{print $1}')"
    if [[ "${actual_sha256}" == "${LOCAL_AI_MMPROJ_SHA256}" ]]; then
      return 0
    fi
    echo "Projector checksum mismatch: ${LOCAL_AI_MMPROJ}" >&2
    return 1
  fi

  mkdir -p "$(dirname "${LOCAL_AI_MMPROJ}")"
  download_file="${LOCAL_AI_MMPROJ}.download"
  rm -f "${download_file}"
  if ! curl --fail --location --retry 3 --output "${download_file}" "${LOCAL_AI_MMPROJ_URL}"; then
    rm -f "${download_file}"
    return 1
  fi
  actual_sha256="$(shasum -a 256 "${download_file}" | awk '{print $1}')"
  if [[ "${actual_sha256}" != "${LOCAL_AI_MMPROJ_SHA256}" ]]; then
    rm -f "${download_file}"
    echo "Downloaded projector checksum mismatch." >&2
    return 1
  fi
  mv "${download_file}" "${LOCAL_AI_MMPROJ}"
}

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

local_ai_runtime_matches_projector_configuration() {
  local pid
  local process_command
  pid="$(local_ai_pid)"
  [[ -n "${pid}" ]] || return 1
  process_command="$(ps -p "${pid}" -o command= 2>/dev/null || true)"

  if [[ "${LOCAL_AI_DISABLE_VISION}" == "1" ]]; then
    [[ "${process_command}" == *"--no-mmproj"* ]]
  else
    [[ "${process_command}" == *"--mmproj ${LOCAL_AI_MMPROJ}"* ]]
  fi
}

local_ai_runtime_capabilities_match_configuration() {
  local props
  local vision
  props="$(curl --fail --silent --max-time 2 "${LOCAL_AI_BASE_URL}/props")" || return 1
  vision="$(printf '%s\n' "${props}" | jq --raw-output '.modalities.vision // false')" || return 1

  if [[ "${LOCAL_AI_DISABLE_VISION}" == "1" ]]; then
    [[ "${vision}" != "true" ]]
  else
    [[ "${vision}" == "true" ]]
  fi
}

local_ai_runtime_matches_configuration() {
  local_ai_runtime_matches_projector_configuration \
    && local_ai_runtime_capabilities_match_configuration
}

local_ai_wait_ready() {
  local attempts="${1:-120}"
  local delay="${2:-2}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --silent --max-time 2 "${LOCAL_AI_BASE_URL}/health" >/dev/null 2>&1; then
      if local_ai_runtime_capabilities_match_configuration; then
        return 0
      fi
      echo "Server is healthy but /props does not match the requested vision configuration." >&2
      return 1
    fi
    if ! local_ai_running; then
      return 1
    fi
    sleep "${delay}"
  done
  return 1
}
