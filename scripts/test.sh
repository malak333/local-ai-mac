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

if ! bash -c 'source "$1"; local_ai_validate_projector_configuration' _ "${SCRIPT_DIR}/common.sh"; then
  echo "Default model/projector configuration is invalid." >&2
  exit 1
fi
if LOCAL_AI_MODEL='example/other-model:Q4_K_M' \
  bash -c 'source "$1"; local_ai_validate_projector_configuration' _ "${SCRIPT_DIR}/common.sh" \
  >/dev/null 2>&1; then
  echo "A different model repository was allowed to use the default projector." >&2
  exit 1
fi
if LOCAL_AI_MODEL='example/other-model:Q4_K_M' "${SCRIPT_DIR}/local-ai" foreground \
  >/dev/null 2>&1; then
  echo "Foreground launch ignored an invalid projector configuration." >&2
  exit 1
fi
if ! LOCAL_AI_MODEL='example/other-model:Q4_K_M' LOCAL_AI_DISABLE_VISION=1 \
  bash -c 'source "$1"; local_ai_validate_projector_configuration' _ "${SCRIPT_DIR}/common.sh"; then
  echo "An explicit text-only model override was rejected." >&2
  exit 1
fi
if ! LOCAL_AI_MODEL='bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q4_K_S' \
  bash -c 'source "$1"; local_ai_validate_projector_configuration' _ "${SCRIPT_DIR}/common.sh"; then
  echo "A quantization override from the matching model repository was rejected." >&2
  exit 1
fi

fake_process_command='llama serve --mmproj /tmp/projector.gguf --port 8080'
runtime_match="$({
  source "${SCRIPT_DIR}/common.sh"
  local_ai_pid() { printf '%s\n' "$$"; }
  ps() { printf '%s\n' "${fake_process_command}"; }
  LOCAL_AI_MMPROJ=/tmp/projector.gguf
  local_ai_runtime_matches_projector_configuration
} && printf match)"
if [[ "${runtime_match}" != "match" ]]; then
  echo "Matching projector runtime was reported as stale." >&2
  exit 1
fi
if (
  source "${SCRIPT_DIR}/common.sh"
  local_ai_pid() { printf '%s\n' "$$"; }
  ps() { printf '%s\n' 'llama serve --no-mmproj --port 8080'; }
  local_ai_runtime_matches_projector_configuration
); then
  echo "Text-only runtime was reported as matching the vision configuration." >&2
  exit 1
fi

if ! (
  source "${SCRIPT_DIR}/common.sh"
  curl() { printf '%s\n' '{"modalities":{"vision":true}}'; }
  local_ai_runtime_capabilities_match_configuration
); then
  echo "Vision-capable /props response was rejected." >&2
  exit 1
fi
if (
  source "${SCRIPT_DIR}/common.sh"
  local_ai_pid() { printf '%s\n' "$$"; }
  ps() { printf '%s\n' 'llama serve --mmproj /tmp/projector.gguf --port 8080'; }
  curl() { printf '%s\n' '{"modalities":{"vision":false}}'; }
  LOCAL_AI_MMPROJ=/tmp/projector.gguf
  local_ai_runtime_matches_configuration
); then
  echo "Runtime with matching arguments but stale vision capability was accepted." >&2
  exit 1
fi
if (
  source "${SCRIPT_DIR}/common.sh"
  LOCAL_AI_DISABLE_VISION=1
  curl() { printf '%s\n' '{"modalities":{"vision":true}}'; }
  local_ai_runtime_capabilities_match_configuration
); then
  echo "Text-only configuration accepted a vision-enabled /props response." >&2
  exit 1
fi
if ! (
  source "${SCRIPT_DIR}/common.sh"
  LOCAL_AI_DISABLE_VISION=1
  curl() { printf '%s\n' '{"modalities":{"vision":false}}'; }
  local_ai_runtime_capabilities_match_configuration
); then
  echo "Text-only /props response was rejected for disabled vision." >&2
  exit 1
fi

jq --exit-status '
  .tools.webfetch == true
  and .tools.websearch == true
  and .permission == "allow"
  and .enabled_providers == ["llama.cpp"]
  and .share == "disabled"
  and .autoupdate == false
  and .snapshot == true
  and (.compaction.auto == true and .compaction.prune == false and .compaction.reserved == 16384 and .compaction.threshold == 0.75)
  and .agent.build.temperature == 0.1
  and .agent.build.steps == 96
  and .provider["llama.cpp"].options.timeout == 900000
  and (.watcher.ignore | sort) == ([
    ".git/**",
    "target/**",
    ".build/**",
    "DerivedData/**",
    "node_modules/**",
    "dist/**"
  ] | sort)
' "${REPO_DIR}/config/opencode.json" >/dev/null || {
  echo "OpenCode safety, determinism, and runtime tuning is incomplete." >&2
  exit 1
}

# Validate agent guardrails configuration
jq --exit-status '
  .agent.max_steps == 96
  and .agent.max_absolute_steps == 256
  and .agent.auto_extend_steps == true
  and .agent.step_extension == 32
  and .agent.max_no_progress_steps == 8
  and .agent.max_identical_actions == 3
  and .agent.max_consecutive_errors == 5
  and .agent.task_timeout_minutes == 60
  and .agent.command_retries == 2
  and .agent.test_retries == 3
  and .agent.context_compaction == true
  and .agent.context_compaction_threshold == 0.75
  and .agent.context_reserve == 0.15
  and .agent.checkpoint_every_steps == 10
  and .agent.checkpoint_before_risky_action == true
  and .agent.use_git_worktree == true
  and .agent.auto_commit_checkpoints == true
  and .agent.rollback_on_failure == true
  and .agent.run_tests_before_complete == true
  and .agent.run_lint_before_complete == true
  and .agent.self_review_before_complete == true
  and .agent.stuck_detection.enabled == true
  and .agent.stuck_detection.repeated_error_limit == 3
  and .agent.stuck_detection.repeated_command_limit == 3
  and .agent.stuck_detection.no_diff_limit == 5
  and (.agent.stuck_detection.on_stuck | sort) == (["summarize_problem","reread_relevant_code","create_new_plan","retry"] | sort)
  and .agent.progress_tracking.enabled == true
  and .agent.progress_tracking.track_failing_tests == true
  and .agent.progress_tracking.track_diff_changes == true
' "${REPO_DIR}/config/opencode.json" >/dev/null || {
  echo "Agent guardrails configuration is incomplete or incorrect." >&2
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

# Validate harness.sh exists and is executable
if [[ ! -x "${SCRIPT_DIR}/harness.sh" ]]; then
  echo "Agent harness script is missing or not executable." >&2
  exit 1
fi

# Validate harness.sh syntax
bash -n "${SCRIPT_DIR}/harness.sh" || {
  echo "Agent harness script has syntax errors." >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "Expected an Apple Silicon Mac." >&2
  exit 1
fi

echo "Static checks passed."
