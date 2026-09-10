---
name: agent-step-config
description: "Agent step limits configuration and tuning history for local AI coding agent."
---

# Agent Step Limits Configuration

## Current Configuration (doubled from initial values)

### opencode.json (`config/opencode.json`)
- `agent.build.steps`: 192 (build agent max iterations)
- `agent.max_steps`: 640 (soft step ceiling, auto-extends on progress)
- `agent.max_absolute_steps`: 512 (hard step ceiling, never exceeded)
- `agent.step_extension`: 64 (steps added per progress-based extension)
- `agent.auto_extend_steps`: true (enable automatic extension on progress)

### scripts/harness.sh
- `HARNESS_MAX_STEPS`: 192 (default soft limit)
- `HARNESS_MAX_ABSOLUTE_STEPS`: 512 (default hard ceiling)
- `HARNESS_STEP_EXTENSION`: 64 (extension increment)
- `HARNESS_AUTO_EXTEND`: true
- `HARNESS_MAX_CONSECUTIVE_ERRORS`: 5
- `HARNESS_MAX_NO_PROGRESS`: 8

## Extension Logic (harness.sh)
When `auto_extend_steps` is enabled:
1. Agent reaches soft limit (max_steps = 640)
2. Progress check: test failures decreasing, diffs changing, or errors low
3. If progress detected: extend by step_extension (64), reset error counter
4. If some activity but not strong progress: still extend if errors < max_consecutive_errors
5. Absolute ceiling (max_absolute_steps = 512) is a hard stop, no extensions past this

## History
- Initial values: build.steps=96, max_steps=320, max_absolute_steps=256, step_extension=32
- Doubled on: 2026-09-10 (to address max step counter hitting limits)
- Previous commits show context doubling progression: 16K → 32K → 64K → 128K → 256K

## Validation
Run `make test` to verify step configuration matches assertions in `scripts/test.sh`.

## Key Files
- `config/opencode.json` - OpenCode agent configuration
- `scripts/harness.sh` - Agent harness with step tracking, stuck detection, checkpointing
- `scripts/test.sh` - Static checks including step count validation assertions
