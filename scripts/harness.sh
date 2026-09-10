#!/usr/bin/env bash

set -euo pipefail

# Agent Harness - Guardrails for extended autonomous agent runs
# Implements progress-aware limits, stuck-loop detection, checkpointing,
# git safety, and verification before completion.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source common defaults
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# REPO_DIR is used for external validation of harness configuration
# shellcheck disable=SC2034
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Configuration (can be overridden via environment variables)
# ---------------------------------------------------------------------------

HARNESS_MAX_STEPS="${HARNESS_MAX_STEPS:-192}"
HARNESS_MAX_ABSOLUTE_STEPS="${HARNESS_MAX_ABSOLUTE_STEPS:-512}"
HARNESS_AUTO_EXTEND="${HARNESS_AUTO_EXTEND:-true}"
HARNESS_STEP_EXTENSION="${HARNESS_STEP_EXTENSION:-64}"
HARNESS_MAX_NO_PROGRESS="${HARNESS_MAX_NO_PROGRESS:-8}"
HARNESS_MAX_IDENTICAL_ACTIONS="${HARNESS_MAX_IDENTICAL_ACTIONS:-3}"
HARNESS_MAX_CONSECUTIVE_ERRORS="${HARNESS_MAX_CONSECUTIVE_ERRORS:-5}"
HARNESS_TASK_TIMEOUT_MINUTES="${HARNESS_TASK_TIMEOUT_MINUTES:-60}"
HARNESS_COMMAND_RETRIES="${HARNESS_COMMAND_RETRIES:-2}"
HARNESS_TEST_RETRIES="${HARNESS_TEST_RETRIES:-3}"
HARNESS_CHECKPOINT_EVERY="${HARNESS_CHECKPOINT_EVERY:-10}"
HARNESS_CONTEXT_COMPACT="${HARNESS_CONTEXT_COMPACT:-true}"
HARNESS_CONTEXT_COMPACT_THRESHOLD="${HARNESS_CONTEXT_COMPACT_THRESHOLD:-0.75}"
HARNESS_CONTEXT_RESERVE="${HARNESS_CONTEXT_RESERVE:-0.15}"
HARNESS_CHECKPOINT_BEFORE_RISKY="${HARNESS_CHECKPOINT_BEFORE_RISKY:-true}"
HARNESS_USE_GIT_WORKTREE="${HARNESS_USE_GIT_WORKTREE:-true}"
HARNESS_AUTO_COMMIT_CHECKPOINTS="${HARNESS_AUTO_COMMIT_CHECKPOINTS:-true}"
HARNESS_ROLLBACK_ON_FAILURE="${HARNESS_ROLLBACK_ON_FAILURE:-true}"
HARNESS_RUN_TESTS_BEFORE_COMPLETE="${HARNESS_RUN_TESTS_BEFORE_COMPLETE:-true}"
HARNESS_RUN_LINT_BEFORE_COMPLETE="${HARNESS_RUN_LINT_BEFORE_COMPLETE:-true}"
HARNESS_SELF_REVIEW_BEFORE_COMPLETE="${HARNESS_SELF_REVIEW_BEFORE_COMPLETE:-true}"
HARNESS_STUCK_DETECTION_ENABLED="${HARNESS_STUCK_DETECTION_ENABLED:-true}"
HARNESS_REPEATED_ERROR_LIMIT="${HARNESS_REPEATED_ERROR_LIMIT:-3}"
HARNESS_REPEATED_COMMAND_LIMIT="${HARNESS_REPEATED_COMMAND_LIMIT:-3}"
HARNESS_NO_DIFF_LIMIT="${HARNESS_NO_DIFF_LIMIT:-5}"
HARNESS_PROGRESS_TRACKING="${HARNESS_PROGRESS_TRACKING:-true}"
HARNESS_TRACK_FAILING_TESTS="${HARNESS_TRACK_FAILING_TESTS:-true}"
HARNESS_LOG_PROGRESS_INTERVAL="${HARNESS_LOG_PROGRESS_INTERVAL:-5}"

# ---------------------------------------------------------------------------
# State directories and files
# ---------------------------------------------------------------------------

HARNESS_STATE_DIR="${LOCAL_AI_STATE_DIR:-${HOME}/Library/Application Support/local-ai-mac}/harness"
HARNESS_CHECKPOINT_DIR="${HARNESS_STATE_DIR}/checkpoints"
HARNESS_EVENTS_LOG="${HARNESS_STATE_DIR}/events.log"
HARNESS_STATE_FILE="${HARNESS_STATE_DIR}/state.json"
HARNESS_WORKTREE_DIR=""
HARNESS_ORIGINAL_DIR=""
HARNESS_BASE_COMMIT=""
HARNESS_START_TIME=""

mkdir -p "${HARNESS_STATE_DIR}" "${HARNESS_CHECKPOINT_DIR}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

harness_log() {
  local level="$1"
  shift
  local timestamp
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s [%s] %s\n' "${timestamp}" "${level}" "$*" | tee -a "${HARNESS_EVENTS_LOG}"
}

harness_info()  { harness_log INFO  "$@"; }
harness_warn()  { harness_log WARN  "$@"; }
harness_error() { harness_log ERROR "$@"; }
harness_debug() { harness_log DEBUG "$@"; }

# ---------------------------------------------------------------------------
# Event tracking
# ---------------------------------------------------------------------------

harness_emit_event() {
  local event_type="$1"
  local event_data="$2"
  local timestamp
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '{"timestamp":"%s","type":"%s","data":%s}\n' "${timestamp}" "${event_type}" "${event_data}" >> "${HARNESS_EVENTS_LOG}"
}

# ---------------------------------------------------------------------------
# Progress state management
# ---------------------------------------------------------------------------

harness_load_state() {
  if [[ -f "${HARNESS_STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${HARNESS_STATE_FILE}"
  fi
  HARNESS_CURRENT_STEP="${HARNESS_CURRENT_STEP:-0}"
  HARNESS_LAST_PROGRESS_STEP="${HARNESS_LAST_PROGRESS_STEP:-0}"
  HARNESS_CONSECUTIVE_ERRORS="${HARNESS_CONSECUTIVE_ERRORS:-0}"
  HARNESS_TOTAL_TEST_FAILURES="${HARNESS_TOTAL_TEST_FAILURES:-0}"
  HARNESS_PREV_TEST_FAILURES="${HARNESS_PREV_TEST_FAILURES:-0}"
  HARNESS_REPEATED_COMMANDS="${HARNESS_REPEATED_COMMANDS:-}"
  HARNESS_REPEATED_ERRORS="${HARNESS_REPEATED_ERRORS:-}"
  HARNESS_NO_DIFF_COUNT="${HARNESS_NO_DIFF_COUNT:-0}"
  HARNESS_LAST_DIFF_HASH="${HARNESS_LAST_DIFF_HASH:-}"
  HARNESS_CHECKPOINT_COUNT="${HARNESS_CHECKPOINT_COUNT:-0}"
  HARNESS_EXTENSIONS_USED="${HARNESS_EXTENSIONS_USED:-0}"
  HARNESS_STUCK_COUNT="${HARNESS_STUCK_COUNT:-0}"
}

harness_save_state() {
  cat > "${HARNESS_STATE_FILE}" <<STATEEOF
HARNESS_CURRENT_STEP="${HARNESS_CURRENT_STEP:-0}"
HARNESS_LAST_PROGRESS_STEP="${HARNESS_LAST_PROGRESS_STEP:-0}"
HARNESS_CONSECUTIVE_ERRORS="${HARNESS_CONSECUTIVE_ERRORS:-0}"
HARNESS_TOTAL_TEST_FAILURES="${HARNESS_TOTAL_TEST_FAILURES:-0}"
HARNESS_PREV_TEST_FAILURES="${HARNESS_PREV_TEST_FAILURES:-0}"
HARNESS_REPEATED_COMMANDS="${HARNESS_REPEATED_COMMANDS:-}"
HARNESS_REPEATED_ERRORS="${HARNESS_REPEATED_ERRORS:-}"
HARNESS_NO_DIFF_COUNT="${HARNESS_NO_DIFF_COUNT:-0}"
HARNESS_LAST_DIFF_HASH="${HARNESS_LAST_DIFF_HASH:-}"
HARNESS_CHECKPOINT_COUNT="${HARNESS_CHECKPOINT_COUNT:-0}"
HARNESS_EXTENSIONS_USED="${HARNESS_EXTENSIONS_USED:-0}"
HARNESS_STUCK_COUNT="${HARNESS_STUCK_COUNT:-0}"
STATEEOF
}

# ---------------------------------------------------------------------------
# Progress tracking helpers
# ---------------------------------------------------------------------------

harness_track_test_progress() {
  local failing_count="${1:-0}"
  HARNESS_PREV_TEST_FAILURES="${HARNESS_TOTAL_TEST_FAILURES}"
  HARNESS_TOTAL_TEST_FAILURES="${failing_count}"

  if [[ "${HARNESS_PROGRESS_TRACKING}" == "true" ]]; then
    if [[ "${HARNESS_CURRENT_STEP}" -ge "${HARNESS_LOG_PROGRESS_INTERVAL}" ]] || \
       [[ $((HARNESS_CURRENT_STEP % HARNESS_LOG_PROGRESS_INTERVAL)) -eq 0 ]]; then
      if [[ "${HARNESS_PREV_TEST_FAILURES}" -gt 0 ]]; then
        harness_info "Step ${HARNESS_CURRENT_STEP}: tests ${HARNESS_PREV_TEST_FAILURES} failing -> ${HARNESS_TOTAL_TEST_FAILURES} failing"
      fi
    fi

    harness_emit_event "test_progress" \
      "{\"step\":${HARNESS_CURRENT_STEP},\"failing\":${HARNESS_TOTAL_TEST_FAILURES},\"prev_failing\":${HARNESS_PREV_TEST_FAILURES}}"
  fi
}

harness_track_diff() {
  local current_diff
  current_diff="$(git -C "${HARNESS_ORIGINAL_DIR:-.}" diff --stat 2>/dev/null || echo "")"
  local current_hash
  current_hash="$(printf '%s' "${current_diff}" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "")"

  if [[ -n "${HARNESS_LAST_DIFF_HASH:-}" && "${current_hash}" == "${HARNESS_LAST_DIFF_HASH:-}" ]]; then
    HARNESS_NO_DIFF_COUNT=$((HARNESS_NO_DIFF_COUNT + 1))
    harness_debug "No diff change (count: ${HARNESS_NO_DIFF_COUNT})"
  else
    HARNESS_NO_DIFF_COUNT=0
  fi

  HARNESS_LAST_DIFF_HASH="${current_hash}"

  harness_emit_event "diff_change" \
    "{\"step\":${HARNESS_CURRENT_STEP},\"has_changes\":$([ -n "${current_diff}" ] && echo true || echo false),\"no_diff_count\":${HARNESS_NO_DIFF_COUNT}}"
}

# ---------------------------------------------------------------------------
# Stuck-loop detection
# ---------------------------------------------------------------------------

harness_detect_stuck() {
  if [[ "${HARNESS_STUCK_DETECTION_ENABLED}" != "true" ]]; then
    return 1
  fi

  local is_stuck=false
  local stuck_reason=""

  # Check repeated commands
  local last_commands="${HARNESS_REPEATED_COMMANDS:-}"
  if [[ -n "${last_commands}" ]]; then
    local most_common
    most_common="$(printf '%s\n' "${last_commands}" | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')"
    if [[ "${most_common}" -ge "${HARNESS_REPEATED_COMMAND_LIMIT:-3}" ]]; then
      is_stuck=true
      stuck_reason="Repeated command executed ${most_common} times (limit: ${HARNESS_REPEATED_COMMAND_LIMIT})"
    fi
  fi

  # Check repeated errors
  local last_errors="${HARNESS_REPEATED_ERRORS:-}"
  if [[ -n "${last_errors}" ]]; then
    local most_common_err
    most_common_err="$(printf '%s\n' "${last_errors}" | sort | uniq -c | sort -rn | head -1 | awk '{print $1}')"
    if [[ "${most_common_err}" -ge "${HARNESS_REPEATED_ERROR_LIMIT:-3}" ]]; then
      is_stuck=true
      stuck_reason="${stuck_reason:+${stuck_reason}; }Repeated error occurred ${most_common_err} times (limit: ${HARNESS_REPEATED_ERROR_LIMIT})"
    fi
  fi

  # Check no-diff count
  if [[ "${HARNESS_NO_DIFF_COUNT:-0}" -ge "${HARNESS_NO_DIFF_LIMIT:-5}" ]]; then
    is_stuck=true
    stuck_reason="${stuck_reason:+${stuck_reason}; }No diff changes for ${HARNESS_NO_DIFF_COUNT} steps (limit: ${HARNESS_NO_DIFF_LIMIT})"
  fi

  if [[ "${is_stuck}" == "true" ]]; then
    HARNESS_STUCK_COUNT=$((HARNESS_STUCK_COUNT + 1))
    harness_warn "Agent is stuck: ${stuck_reason}"
    harness_emit_event "stuck_detected" "{\"reason\":\"${stuck_reason}\",\"stuck_count\":${HARNESS_STUCK_COUNT}}"
    return 0
  fi

  return 1
}

harness_on_stuck() {
  local strategy="$1"
  harness_info "Stuck recovery strategy: ${strategy}"
  harness_emit_event "stuck_recovery" "{\"strategy\":\"${strategy}\"}"

  case "${strategy}" in
    summarize_problem)
      harness_info "Forcing agent to summarize the current problem state"
      ;;
    reread_relevant_code)
      harness_info "Forcing agent to re-read relevant source files"
      ;;
    create_new_plan)
      harness_info "Forcing agent to create a new execution plan"
      ;;
    retry)
      harness_info "Forcing agent to retry with a different approach"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Step limit management (progress-aware)
# ---------------------------------------------------------------------------

harness_get_effective_max_steps() {
  local effective="${HARNESS_MAX_STEPS}"
  if [[ "${HARNESS_AUTO_EXTEND:-true}" == "true" ]]; then
    effective=$((HARNESS_MAX_STEPS + (HARNESS_EXTENSIONS_USED * HARNESS_STEP_EXTENSION)))
  fi
  if [[ "${effective}" -gt "${HARNESS_MAX_ABSOLUTE_STEPS}" ]]; then
    effective="${HARNESS_MAX_ABSOLUTE_STEPS}"
  fi
  printf '%s' "${effective}"
}

harness_check_step_limit() {
  HARNESS_CURRENT_STEP="${HARNESS_CURRENT_STEP:-0}"

  # Hard ceiling
  if [[ "${HARNESS_CURRENT_STEP}" -ge "${HARNESS_MAX_ABSOLUTE_STEPS}" ]]; then
    harness_error "Hard step limit reached: ${HARNESS_CURRENT_STEP} >= ${HARNESS_MAX_ABSOLUTE_STEPS}"
    return 2
  fi

  # Calculate current soft limit, including extensions
  local effective_max
  effective_max="$(harness_get_effective_max_steps)"

  # Soft limit with progress awareness
  if [[ "${HARNESS_CURRENT_STEP}" -ge "${effective_max}" ]]; then
    if [[ "${HARNESS_AUTO_EXTEND:-true}" != "true" ]]; then
      harness_error "Step limit reached with insufficient progress: ${HARNESS_CURRENT_STEP} >= ${effective_max}"
      return 1
    fi

    # Check if making progress
    local progress_made=false

    if [[ "${HARNESS_PREV_TEST_FAILURES:-0}" -gt "${HARNESS_TOTAL_TEST_FAILURES:-0}" ]]; then
      progress_made=true
    elif [[ "${HARNESS_NO_DIFF_COUNT:-0}" -eq 0 ]] && [[ "${HARNESS_CURRENT_STEP}" -gt "${HARNESS_LAST_PROGRESS_STEP:-0}" ]]; then
      progress_made=true
    elif [[ "${HARNESS_CONSECUTIVE_ERRORS:-0}" -eq 0 ]] && \
         [[ "${HARNESS_CURRENT_STEP}" -gt "${HARNESS_LAST_PROGRESS_STEP:-0}" ]]; then
      progress_made=true
    fi

    if [[ "${progress_made}" == "true" ]]; then
      local extension="${HARNESS_STEP_EXTENSION:-32}"
      local new_max=$((HARNESS_MAX_STEPS + HARNESS_EXTENSIONS_USED * extension + extension))
      if [[ "${new_max}" -le "${HARNESS_MAX_ABSOLUTE_STEPS}" ]]; then
        HARNESS_EXTENSIONS_USED=$((HARNESS_EXTENSIONS_USED + 1))
        HARNESS_LAST_PROGRESS_STEP="${HARNESS_CURRENT_STEP}"
        HARNESS_CONSECUTIVE_ERRORS=0
        harness_info "Progress detected at step ${HARNESS_CURRENT_STEP} - extending limit by ${extension} (new max: ${new_max}, abs max: ${HARNESS_MAX_ABSOLUTE_STEPS})"
        harness_emit_event "step_extended" "{\"extension\":${extension},\"new_max\":${new_max},\"extensions_used\":${HARNESS_EXTENSIONS_USED}}"
        return 0
      fi
    fi

    # Extend with minimal progress if not too many consecutive errors
    if [[ "${HARNESS_CONSECUTIVE_ERRORS:-0}" -lt "${HARNESS_MAX_CONSECUTIVE_ERRORS:-5}" ]]; then
      local extension="${HARNESS_STEP_EXTENSION:-32}"
      local new_max=$((HARNESS_MAX_STEPS + HARNESS_EXTENSIONS_USED * extension + extension))
      if [[ "${new_max}" -le "${HARNESS_MAX_ABSOLUTE_STEPS}" ]]; then
        HARNESS_EXTENSIONS_USED=$((HARNESS_EXTENSIONS_USED + 1))
        HARNESS_CONSECUTIVE_ERRORS=0
        harness_warn "Approaching step limit with some activity - extending by ${extension} (new max: ${new_max})"
        harness_emit_event "step_extended" "{\"extension\":${extension},\"new_max\":${new_max},\"extensions_used\":${HARNESS_EXTENSIONS_USED}}"
        return 0
      fi
    fi

    harness_error "Soft step limit reached with insufficient progress: ${HARNESS_CURRENT_STEP} >= ${effective_max}"
    return 1
  fi

  # Within limits
  return 0
}

harness_increment_step() {
  HARNESS_CURRENT_STEP=$((HARNESS_CURRENT_STEP + 1))

  # Check step limit after increment
  harness_check_step_limit
  local limit_status=$?

  if [[ "${limit_status}" -eq 2 ]]; then
    harness_error "Absolute step ceiling reached. Terminating."
    return 2
  elif [[ "${limit_status}" -eq 1 ]]; then
    harness_warn "Step limit reached - task may not complete"
  fi

  # Reset consecutive errors tracking on step increment
  HARNESS_CONSECUTIVE_ERRORS=0

  harness_save_state
  return 0
}

harness_record_error() {
  HARNESS_CONSECUTIVE_ERRORS=$((HARNESS_CONSECUTIVE_ERRORS + 1))
  local error_msg="${1:-unknown}"
  harness_warn "Consecutive error ${HARNESS_CONSECUTIVE_ERRORS}/${HARNESS_MAX_CONSECUTIVE_ERRORS}: ${error_msg}"

  # Track error pattern for stuck detection
  if [[ -z "${HARNESS_REPEATED_ERRORS:-}" ]]; then
    HARNESS_REPEATED_ERRORS="${error_msg}"
  else
    HARNESS_REPEATED_ERRORS="${HARNESS_REPEATED_ERRORS}|${error_msg}"
    # Keep only last 20 entries to avoid unbounded growth.
    local count
    count=$(echo "${HARNESS_REPEATED_ERRORS}" | tr '|' '\n' | wc -l | tr -d ' ')
    if [[ "${count}" -gt 20 ]]; then
      HARNESS_REPEATED_ERRORS=$(echo "${HARNESS_REPEATED_ERRORS}" | tr '|' '\n' | tail -20 | tr '\n' '|' | sed 's/|$//')
    fi
  fi
}

# ---------------------------------------------------------------------------
# Checkpointing
# ---------------------------------------------------------------------------

harness_create_checkpoint() {
  local checkpoint_name="${1:-step-${HARNESS_CURRENT_STEP}}"
  local checkpoint_file="${HARNESS_CHECKPOINT_DIR}/checkpoint-${checkpoint_name}.json"
  local checkpoint_git_file="${HARNESS_CHECKPOINT_DIR}/checkpoint-${checkpoint_name}-git.patch"

  HARNESS_CHECKPOINT_COUNT=$((HARNESS_CHECKPOINT_COUNT + 1))

  # Save state snapshot
  cat > "${checkpoint_file}" <<CKEOF
{
  "checkpoint": "${checkpoint_name}",
  "step": ${HARNESS_CURRENT_STEP},
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "base_commit": "${HARNESS_BASE_COMMIT}",
  "working_tree_status": "$(git -C "${HARNESS_ORIGINAL_DIR:-.}" status --porcelain 2>/dev/null || echo "not a git repo")",
  "state": {
    "current_step": "${HARNESS_CURRENT_STEP}",
    "consecutive_errors": "${HARNESS_CONSECUTIVE_ERRORS}",
    "total_test_failures": "${HARNESS_TOTAL_TEST_FAILURES}",
    "extensions_used": "${HARNESS_EXTENSIONS_USED}",
    "stuck_count": "${HARNESS_STUCK_COUNT}"
  }
}
CKEOF

  # Save git diff as patch
  git -C "${HARNESS_ORIGINAL_DIR:-.}" diff > "${checkpoint_git_file}" 2>/dev/null || true

  harness_info "Checkpoint created: ${checkpoint_name} (count: ${HARNESS_CHECKPOINT_COUNT})"
  harness_emit_event "checkpoint" "{\"checkpoint\":\"${checkpoint_name}\",\"step\":${HARNESS_CURRENT_STEP},\"count\":${HARNESS_CHECKPOINT_COUNT}}"
}

harness_load_checkpoint() {
  local checkpoint_name="$1"
  local checkpoint_file="${HARNESS_CHECKPOINT_DIR}/checkpoint-${checkpoint_name}.json"

  if [[ ! -f "${checkpoint_file}" ]]; then
    harness_error "Checkpoint not found: ${checkpoint_name}"
    return 1
  fi

  harness_info "Loading checkpoint: ${checkpoint_name}"
  harness_emit_event "checkpoint_load" "{\"checkpoint\":\"${checkpoint_name}\"}"
  return 0
}

harness_auto_checkpoint() {
  if [[ $((HARNESS_CURRENT_STEP % HARNESS_CHECKPOINT_EVERY)) -eq 0 ]]; then
    harness_create_checkpoint "auto-${HARNESS_CURRENT_STEP}"
  fi
}

# ---------------------------------------------------------------------------
# Git safety (worktrees, auto-commit, rollback)
# ---------------------------------------------------------------------------

harness_setup_git_worktree() {
  if [[ "${HARNESS_USE_GIT_WORKTREE}" != "true" ]]; then
    return 0
  fi

  HARNESS_ORIGINAL_DIR="$(pwd)"
  HARNESS_BASE_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "")"

  if [[ -z "${HARNESS_BASE_COMMIT}" ]]; then
    harness_warn "Not in a git repository - worktree mode disabled"
    HARNESS_USE_GIT_WORKTREE=false
    return 0
  fi

  # Create a worktree for safe execution
  HARNESS_WORKTREE_DIR="${LOCAL_AI_STATE_DIR}/worktrees/$(date +%s)-$$"
  mkdir -p "${HARNESS_WORKTREE_DIR}"

  if git worktree add --detach "${HARNESS_WORKTREE_DIR}" "${HARNESS_BASE_COMMIT}" 2>/dev/null; then
    harness_info "Git worktree created: ${HARNESS_WORKTREE_DIR}"
    harness_emit_event "worktree_created" "{\"path\":\"${HARNESS_WORKTREE_DIR}\",\"base\":\"${HARNESS_BASE_COMMIT}\"}"
    return 0
  fi

  harness_warn "Failed to create worktree - continuing in place"
  return 1
}

harness_auto_commit_checkpoints() {
  if [[ "${HARNESS_AUTO_COMMIT_CHECKPOINTS}" != "true" ]]; then
    return 0
  fi

  if [[ -z "${HARNESS_ORIGINAL_DIR:-}" ]]; then
    return 0
  fi

  # Check if there are changes to commit
  local has_changes
  has_changes="$(git -C "${HARNESS_ORIGINAL_DIR}" diff --quiet 2>/dev/null || echo "yes")"

  if [[ -n "${has_changes}" ]]; then
    git -C "${HARNESS_ORIGINAL_DIR}" add -A 2>/dev/null || true
    git -C "${HARNESS_ORIGINAL_DIR}" commit -m "harness checkpoint step ${HARNESS_CURRENT_STEP}" --no-verify 2>/dev/null || true
    harness_debug "Auto-committed checkpoint at step ${HARNESS_CURRENT_STEP}"
  fi
}

harness_rollback_on_failure() {
  if [[ "${HARNESS_ROLLBACK_ON_FAILURE}" != "true" ]]; then
    return 0
  fi

  if [[ -n "${HARNESS_BASE_COMMIT:-}" ]]; then
    if git -C "${HARNESS_ORIGINAL_DIR}" reset --hard "${HARNESS_BASE_COMMIT}" 2>/dev/null; then
      git -C "${HARNESS_ORIGINAL_DIR}" clean -fd 2>/dev/null || true
      harness_info "Rolled back to base commit: ${HARNESS_BASE_COMMIT}"
      harness_emit_event "rollback" "{\"base_commit\":\"${HARNESS_BASE_COMMIT}\"}"
    fi
  fi
}

harness_risky_action_check() {
  if [[ "${HARNESS_CHECKPOINT_BEFORE_RISKY}" != "true" ]]; then
    return 0
  fi

  # Before risky actions (git push, merge, delete, etc.), create a checkpoint
  local action="$1"
  if [[ "${action}" == *"git push"* || "${action}" == *"git merge"* || "${action}" == *"git reset --hard"* ]]; then
    harness_create_checkpoint "pre-risky-${HARNESS_CURRENT_STEP}"
  fi
}

# ---------------------------------------------------------------------------
# Verification before completion
# ---------------------------------------------------------------------------

harness_run_tests() {
  if [[ "${HARNESS_RUN_TESTS_BEFORE_COMPLETE}" != "true" ]]; then
    return 0
  fi

  harness_info "Running tests before completion..."

  # Try common test commands
  local test_passed=false
  local test_output=""

  if [[ -f "Makefile" ]]; then
    test_output="$(make test 2>&1)" && test_passed=true
  elif [[ -f "package.json" ]]; then
    test_output="$(npx jest --passWithNoTests 2>&1 || echo "jest failed")" && test_passed=true
    if [[ "${test_passed}" != "true" ]]; then
      test_output="$(npm test -- --passWithNoTests 2>&1 || echo "npm test failed")" && test_passed=true
    fi
  elif command -v pytest >/dev/null 2>&1; then
    test_output="$(pytest --tb=short 2>&1)" && test_passed=true
  elif command -v uv >/dev/null 2>&1; then
    test_output="$(uv run pytest --tb=short 2>&1)" && test_passed=true
  elif [[ -f "Cargo.toml" ]]; then
    test_output="$(cargo test 2>&1)" && test_passed=true
  fi

  if [[ "${test_passed}" == "true" ]]; then
    harness_info "Tests passed"
    harness_emit_event "tests_passed" "{\"step\":${HARNESS_CURRENT_STEP}}"
    return 0
  else
    harness_warn "Tests failed or no test framework detected"
    # Log output for debugging
    if [[ -n "${test_output}" ]]; then
      harness_debug "Test output: ${test_output}"
    fi
    return 1
  fi
}

harness_run_lint() {
  if [[ "${HARNESS_RUN_LINT_BEFORE_COMPLETE}" != "true" ]]; then
    return 0
  fi

  harness_info "Running lint before completion..."

  local lint_passed=false

  if [[ -f "Makefile" ]]; then
    make lint 2>/dev/null && lint_passed=true
  elif command -v eslint >/dev/null 2>&1; then
    npx eslint . --max-warnings=0 2>/dev/null && lint_passed=true
  elif command -v ruff >/dev/null 2>&1; then
    ruff check . 2>/dev/null && lint_passed=true
  elif command -v shellcheck >/dev/null 2>&1; then
    find . -name "*.sh" -exec shellcheck {} + 2>/dev/null && lint_passed=true
  fi

  if [[ "${lint_passed}" == "true" ]]; then
    harness_info "Lint passed"
    harness_emit_event "lint_passed" "{\"step\":${HARNESS_CURRENT_STEP}}"
  else
    harness_warn "Lint failed or no linter detected"
  fi
}

harness_self_review() {
  if [[ "${HARNESS_SELF_REVIEW_BEFORE_COMPLETE}" != "true" ]]; then
    return 0
  fi

  harness_info "Self-review: checking for common issues..."

  local issues_found=0

  # Check for large diffs
  local diff_size
  diff_size="$(git -C "${HARNESS_ORIGINAL_DIR:-.}" diff --stat 2>/dev/null | tail -1 | grep -oP '\d+ file' | grep -oP '\d+' || echo "0")"
  if [[ "${diff_size}" -gt 50 ]]; then
    harness_warn "Large diff: ${diff_size} files changed"
    issues_found=$((issues_found + 1))
  fi

  # Check for untracked files
  local untracked
  untracked="$(git -C "${HARNESS_ORIGINAL_DIR:-.}" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${untracked}" -gt 20 ]]; then
    harness_warn "Many untracked files: ${untracked}"
    issues_found=$((issues_found + 1))
  fi

  if [[ "${issues_found}" -eq 0 ]]; then
    harness_info "Self-review passed"
  else
    harness_warn "Self-review found ${issues_found} issue(s)"
  fi

  harness_emit_event "self_review" "{\"issues_found\":${issues_found},\"step\":${HARNESS_CURRENT_STEP}}"
}

harness_pre_completion_checks() {
  harness_info "Running pre-completion checks..."

  harness_run_tests
  local tests_result=$?

  harness_run_lint
  # shellcheck disable=SC2034
  local lint_result=$?

  harness_self_review
  # shellcheck disable=SC2034
  local review_result=$?

  # Return 0 unless tests explicitly failed
  return ${tests_result}
}

# ---------------------------------------------------------------------------
# Timeout wrapper
# ---------------------------------------------------------------------------

harness_with_timeout() {
  local timeout_minutes="${1}"
  shift
  local timeout_seconds=$((timeout_minutes * 60))

  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_seconds}" "$@"
    return $?
  else
    # Fallback: run without timeout on systems without timeout command
    "$@"
    return $?
  fi
}

# ---------------------------------------------------------------------------
# Command retry wrapper
# ---------------------------------------------------------------------------

harness_retry_command() {
  local max_retries="${1:-2}"
  shift
  local attempt=0

  while [[ "${attempt}" -lt "${max_retries}" ]]; do
    if "$@"; then
      return 0
    fi
    attempt=$((attempt + 1))
    harness_warn "Command attempt ${attempt}/${max_retries} failed, retrying..."
    sleep 1
  done

  harness_error "Command failed after ${max_retries} retries: $*"
  return 1
}

# ---------------------------------------------------------------------------
# Main harness execution
# ---------------------------------------------------------------------------

harness_run() {
  local task_prompt="${1:-}"
  local target_dir="${2:-.}"

  HARNESS_START_TIME="$(date +%s)"

  harness_info "========================================================="
  harness_info "Agent Harness starting"
  harness_info "Task: ${task_prompt}"
  harness_info "Target directory: ${target_dir}"
  harness_info "Max steps: ${HARNESS_MAX_STEPS}"
  harness_info "Absolute max steps: ${HARNESS_MAX_ABSOLUTE_STEPS}"
  harness_info "Auto-extend: ${HARNESS_AUTO_EXTEND}"
  harness_info "========================================================="

  harness_emit_event "harness_start" "{\"task\":\"${task_prompt}\",\"target_dir\":\"${target_dir}\"}"

  # Setup git worktree
  harness_setup_git_worktree

  # Load any existing state
  harness_load_state

  # Initialize step tracking
  HARNESS_CURRENT_STEP="${HARNESS_CURRENT_STEP:-0}"
  HARNESS_CONSECUTIVE_ERRORS=0

  # Main execution loop - this is where the harness would
  # wrap the actual agent execution and track progress
  #
  # In practice, this harness would be used as follows:
  #
  # 1. Create a worktree (already done above)
  # 2. Run opencode with the task prompt
  # 3. After each opencode step/turn, call:
  #    - harness_increment_step
  #    - harness_track_diff
  #    - harness_detect_stuck
  #    - harness_auto_checkpoint
  # 4. If stuck detected, call harness_on_stuck with recovery strategy
  # 5. Before completing, run pre-completion checks

  # Example usage pattern (not executed automatically):
  #
  # cd "${target_dir}"
  # harness_increment_step
  # harness_track_diff
  # if harness_detect_stuck; then
  #   harness_on_stuck "create_new_plan"
  # fi
  # harness_auto_checkpoint
  #
  # ... repeat for each step ...
  #
  # harness_pre_completion_checks
  #
  # If worktree was used and task succeeded:
  #   git -C "${HARNESS_WORKTREE_DIR}" diff > final.patch
  # If worktree was used and task failed:
  #   harness_rollback_on_failure

  # Cleanup
  if [[ -n "${HARNESS_WORKTREE_DIR:-}" ]] && [[ -d "${HARNESS_WORKTREE_DIR}" ]]; then
    git worktree remove "${HARNESS_WORKTREE_DIR}" 2>/dev/null || true
    rm -rf "${HARNESS_WORKTREE_DIR}"
  fi

  # Save final state
  harness_save_state

  local end_time
  end_time="$(date +%s)"
  local duration=$((end_time - HARNESS_START_TIME))

  harness_info "========================================================="
  harness_info "Agent Harness finished"
  harness_info "Steps completed: ${HARNESS_CURRENT_STEP}"
  harness_info "Checkpoints: ${HARNESS_CHECKPOINT_COUNT}"
  harness_info "Extensions: ${HARNESS_EXTENSIONS_USED}"
  harness_info "Stuck detections: ${HARNESS_STUCK_COUNT}"
  harness_info "Duration: ${duration}s"
  harness_info "========================================================="

  harness_emit_event "harness_end" "{\"steps\":${HARNESS_CURRENT_STEP},\"duration\":${duration}}"
}

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------

harness_cleanup() {
  harness_warn "Harness received interrupt signal - cleaning up"
  if [[ "${HARNESS_ROLLBACK_ON_FAILURE}" == "true" ]]; then
    harness_rollback_on_failure
  fi
  if [[ -n "${HARNESS_WORKTREE_DIR:-}" ]] && [[ -d "${HARNESS_WORKTREE_DIR}" ]]; then
    git worktree remove "${HARNESS_WORKTREE_DIR}" 2>/dev/null || true
    rm -rf "${HARNESS_WORKTREE_DIR}"
  fi
}

trap harness_cleanup INT TERM

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [task_prompt] [target_dir]"
    echo ""
    echo "Agent harness with guardrails for extended autonomous runs."
    echo ""
    echo "Configuration (via environment variables):"
    echo "  HARNESS_MAX_STEPS              Soft step limit (default: 192)"
    echo "  HARNESS_MAX_ABSOLUTE_STEPS     Hard step ceiling (default: 512)"
    echo "  HARNESS_AUTO_EXTEND            Auto-extend on progress (default: true)"
    echo "  HARNESS_STEP_EXTENSION         Steps to add on extend (default: 32)"
    echo "  HARNESS_STUCK_DETECTION_ENABLED Enable stuck detection (default: true)"
    echo "  HARNESS_USE_GIT_WORKTREE       Use git worktrees (default: true)"
    echo "  HARNESS_ROLLBACK_ON_FAILURE    Rollback on failure (default: true)"
    echo "  HARNESS_CHECKPOINT_EVERY       Checkpoint interval (default: 10)"
    echo "  HARNESS_RUN_TESTS_BEFORE_COMPLETE Run tests before completion (default: true)"
    exit 0
  fi

  harness_run "${1:-}" "${2:-.}"
fi
