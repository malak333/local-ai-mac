# Local AI coding agent for Apple Silicon

This repository turns a 32 GB Apple Silicon Mac into a private local coding-agent test bed:

```text
OpenCode -> OpenAI-compatible localhost API -> llama.cpp/Metal -> Qwen3.6
```

The current experimental default for this MacBook Pro (M1 Pro, 32 GB) is
Qwen3.6-35B-A3B `IQ4_XS`, a 256K context, one inference slot, quantized KV
cache, and a 2 GB prompt-cache cap. The API binds only to `127.0.0.1`.

## Quick start

```bash
make setup
make start
make health
make tool-test
make agent-smoke
make web-smoke
```

The first `make start` downloads about 20 GB from Hugging Face. The controller
runs the server as a transient per-user launchd job and writes logs under:

```text
~/Library/Application Support/local-ai-mac/server.log
```

Useful commands:

```bash
make status
./scripts/local-ai logs
make benchmark
make stop
```

Once the health and tool tests pass, use the model as a coding agent from any
Git repository:

```bash
cd ~/path/to/a/project
opencode
```

OpenCode's global config is installed at
`~/.config/opencode/opencode.json`. `make setup` backs up a different existing
file before replacing it. It also installs `~/.local/bin/opencode`, a small
launcher that enables hosted Exa search and suppresses external skill discovery
so this Mac's large global skill catalog does not consume the model context.

## What was installed

- `llama.cpp` from Homebrew, with its native Metal backend.
- OpenCode from the vendor's Homebrew tap.
- Qwen3.6-35B-A3B `IQ4_XS` from Hugging Face. Model weights remain in the
  llama.cpp cache and are never committed to Git.
- Text-only inference for the coding-agent baseline; the optional multimodal
  projector is not loaded into the already-tight unified-memory budget.
- A localhost-only server controller, API health check, real structured
  tool-call check, live web-search/fetch check, and repeatable benchmark.

The selected model is a mixture-of-experts model: all 35B parameters occupy
memory, while about 3B are active for each token. `IQ4_XS` is roughly 19.7 GB,
leaving working room for macOS, the KV cache, OpenCode, and development tools.

## Configuration and tuning

Defaults live in `scripts/common.sh`. Override them for one run without editing
the repository:

```bash
LOCAL_AI_CONTEXT=65536 ./scripts/local-ai start
LOCAL_AI_PORT=8081 ./scripts/local-ai foreground
LOCAL_AI_MODEL='bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q4_K_S' \
  ./scripts/local-ai foreground
```

When changing the context or port, update `config/opencode.json` and rerun
`make setup` so OpenCode advertises the same limits and endpoint.

Recommended progression:

| Stage | Context | Use |
|---|---:|---|
| Initial baseline | 16K | Initial stability and tool-calling proof |
| Intermediate | 32K | First context-doubling validation |
| Intermediate | 64K | Second context-doubling validation |
| Prior experiment | 128K | First six-figure context activation |
| Current experiment | 256K | Training-context ceiling; extreme memory-pressure experiment |

The 256K setting starts and passes the smoke suite, but those checks do not fill
the context. Treat it as a ceiling experiment, not a proven long-session
capacity. Monitor memory pressure and stop the server when it is not in use.

Do not raise `iogpu.wired_limit_mb` initially. The current setup is designed to
fit the default macOS GPU memory ceiling. Raising the ceiling requires an
administrator password, resets on reboot, and should be treated as an explicit
later experiment.

## A meaningful first agent test

Create a branch in a repository that has a real test suite, then ask OpenCode:

> Analyze this repository before changing anything. Explain its architecture,
> identify how it is built and tested, and give me three concrete weaknesses.

Choose one finding and continue:

> Implement the first issue. Inspect all related files, make the change, run
> the relevant tests, diagnose failures, iterate until they pass, inspect the
> final diff, and summarize the result.

The useful signal is whether the agent inspects, tests, responds to failures,
and validates its own diff—not merely whether it produces code.

## Local-vs-cloud evaluation

Run 10-20 real tasks through both this setup and a frontier coding agent. Track:

- correct files and architecture understanding;
- implementation and test quality;
- recovery from tool or test failures;
- human interventions required;
- time to completion and whether you would accept the result.

The rescue/intervention count is more meaningful than tokens per second. This
M1 trial can prove the workflow; a larger Mac mainly buys stronger models, more
context, and concurrency.

## Security and operational notes

- The model API is localhost-only by default. Do not change the host to
  `0.0.0.0` without adding authentication and firewall controls.
- OpenCode can read, edit, and run commands in the repository where it starts.
  All enabled actions are auto-approved in this configuration, including file
  writes, external-directory access, and shell commands. There is no interactive
  confirmation barrier. Work in a disposable branch or worktree and keep
  credentials and secrets out of accessible files and process environments.
- `websearch` and `webfetch` are enabled. Search queries and fetched URLs/content
  leave the Mac for OpenCode's hosted search service and destination websites;
  do not include secrets or unnecessary personal information. Treat retrieved
  content as untrusted input.
- No MCP servers are enabled. Prove native filesystem, shell, Git, compiler,
  and test tools first; MCP tool definitions consume scarce context.
- The setup disables OpenCode's global skill catalog, subagents, and LSP tool.
  This machine has a large global skill collection whose discovered permission
  entries previously consumed essentially the full 128K context. Core
  repository and web tools remain available.
- The transient launchd job survives the launching terminal but does not start
  at login. A 20+ GB resident model should be an intentional workload on a
  32 GB laptop.

## Verification

```bash
make test       # shell syntax, JSON, dependencies, Apple Silicon
make health     # live API, model alias, deterministic completion
make tool-test  # structured function call with validated arguments
make agent-smoke # OpenCode reads this repo through its file tool
make web-smoke  # OpenCode performs both a hosted search and page fetch
make benchmark  # timestamped response and llama.cpp timing data
```

See [the validation record](docs/VALIDATION.md) for the exact host, versions,
live tool-call proof, OpenCode proof, and observed throughput from this install.

See [the local agent evaluation](docs/AGENT-EVALUATION.md) for the first
Assemblywright audits, observed failure modes, capability boundaries, and the
recommended design for a disposable agentic-workflow harness.

## Sources

- [llama.cpp installation](https://github.com/ggml-org/llama.cpp/blob/master/docs/install.md)
- [llama.cpp server and tool-use documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [OpenCode llama.cpp provider configuration](https://opencode.ai/docs/providers#llama.cpp)
- [Qwen3.6-35B-A3B model](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)
- [IQ4_XS GGUF and quantization sizes](https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF)
- [M1 Pro/32 GB measurements and methodology](https://github.com/marcofariasmx/local-llm-apple-silicon)
