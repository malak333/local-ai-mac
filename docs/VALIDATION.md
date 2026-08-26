# Validation record

Validated locally on August 26, 2026 (America/New_York).

## Host

| Item | Observed value |
|---|---|
| Model | MacBook Pro (`MacBookPro18,1`) |
| Chip | Apple M1 Pro |
| CPU | 10 cores (8 performance, 2 efficiency) |
| GPU | 16 cores, Metal 4 |
| Unified memory | 32 GB |
| macOS | 26.5.2 (`25F84`) |

## Installed software

| Component | Observed version |
|---|---|
| llama.cpp | 0.3.0, build 10621 (`c1d0e7a00`) |
| OpenCode | 1.18.23 |
| ShellCheck | 0.11.0 |

The running model reported 35,505,251,456 parameters, a 262,144-token training
context, a 16,384-token runtime context, and a 19,688,563,200-byte IQ4_XS
weight file.

## Passed checks

1. `make test` passed Bash syntax, ShellCheck, JSON parsing, dependency, and
   Apple Silicon checks.
2. The transient launchd job remained alive after its launching shell exited.
3. `/health` returned `{"status":"ok"}` and `/v1/models` returned the
   `qwen36-local` alias with the expected runtime context.
4. `make health` returned exactly `LOCAL_AI_OK` with thinking disabled.
5. `make tool-test` produced a structured `calculator` function call with
   arguments `{"a":1234,"b":5678}`.
6. `make agent-smoke` exercised the complete OpenCode path: OpenCode used its
   `read` tool on `README.md`, then returned `LOCAL_OPENCODE_OK`. Its second
   turn reused 6,030 cached tokens.

The first OpenCode attempt exposed that this account's large global skill
catalog added roughly 131K tokens to the tool description, overflowing the
16K local context. The committed baseline disables the skill catalog,
subagents, web tools, and LSP while retaining core repository read, search,
edit, and shell tools. The end-to-end check passed after that change.

## Measured inference

The deterministic health prompt generated about 20.0 tokens/second. The
repeatable Rust LRU benchmark generated 1,024 tokens at 35.3 tokens/second,
with prompt processing at 91.9 tokens/second for its 30-token prompt. These are
single observations, not a controlled performance study.

At the final idle observation, the llama.cpp process had approximately 11.6
GiB resident according to `ps`; system-wide encrypted swap usage was 1.66 GiB.
That swap figure includes the rest of the running Mac and is not attributed
solely to llama.cpp.

## Current operating boundary

- API: `http://127.0.0.1:8080`
- Context: 16K
- Parallel slots: one
- Vision projector: disabled
- MCP: disabled
- Autostart at login: disabled
- OpenCode edits and shell commands: confirmation required
