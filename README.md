# Local AI coding agent for Apple Silicon

This repository turns a 32 GB Apple Silicon Mac into a private local coding-agent test bed:

```text
OpenCode -> OpenAI-compatible localhost API -> llama.cpp/Metal -> Qwen3.6
```

The default is tuned for this MacBook Pro (M1 Pro, 32 GB): Qwen3.6-35B-A3B
`IQ4_XS`, a 16K context, one inference slot, quantized KV cache, and a 2 GB
prompt-cache cap. The API binds only to `127.0.0.1`.

## Quick start

```bash
make setup
make start
make health
make tool-test
make agent-smoke
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
file before replacing it.

## What was installed

- `llama.cpp` from Homebrew, with its native Metal backend.
- OpenCode from the vendor's Homebrew tap.
- Qwen3.6-35B-A3B `IQ4_XS` from Hugging Face. Model weights remain in the
  llama.cpp cache and are never committed to Git.
- Text-only inference for the coding-agent baseline; the optional multimodal
  projector is not loaded into the already-tight unified-memory budget.
- A localhost-only server controller, API health check, real structured
  tool-call check, and repeatable benchmark.

The selected model is a mixture-of-experts model: all 35B parameters occupy
memory, while about 3B are active for each token. `IQ4_XS` is roughly 19.7 GB,
leaving working room for macOS, the KV cache, OpenCode, and development tools.

## Configuration and tuning

Defaults live in `scripts/common.sh`. Override them for one run without editing
the repository:

```bash
LOCAL_AI_CONTEXT=32768 ./scripts/local-ai start
LOCAL_AI_PORT=8081 ./scripts/local-ai foreground
LOCAL_AI_MODEL='bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q4_K_S' \
  ./scripts/local-ai foreground
```

When changing the context or port, update `config/opencode.json` and rerun
`make setup` so OpenCode advertises the same limits and endpoint.

Recommended progression:

| Stage | Context | Use |
|---|---:|---|
| Baseline | 16K | Prove stability and tool calling |
| Target | 24K-32K | Larger repositories if memory pressure stays green |
| Experimental | 48K+ | Only after measuring swap and latency |

Do not raise `iogpu.wired_limit_mb` initially. The baseline is designed to fit
the default macOS GPU memory ceiling. Raising the ceiling requires an
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
  Review permissions, work on a branch, and keep secrets out of accessible
  plaintext files.
- No MCP servers are enabled. Prove native filesystem, shell, Git, compiler,
  and test tools first; MCP tool definitions consume scarce context.
- The baseline also disables OpenCode's global skill catalog, subagents, web
  tools, and LSP tool. This machine has a large global skill collection whose
  descriptions alone overflow a 16K context. Core read/search/edit/shell tools
  remain available, with edits and shell commands requiring confirmation.
- The transient launchd job survives the launching terminal but does not start
  at login. A 20+ GB resident model should be an intentional workload on a
  32 GB laptop.

## Verification

```bash
make test       # shell syntax, JSON, dependencies, Apple Silicon
make health     # live API, model alias, deterministic completion
make tool-test  # structured function call with validated arguments
make agent-smoke # OpenCode reads this repo through its file tool
make benchmark  # timestamped response and llama.cpp timing data
```

See [the validation record](docs/VALIDATION.md) for the exact host, versions,
live tool-call proof, OpenCode proof, and observed throughput from this install.

## Sources

- [llama.cpp installation](https://github.com/ggml-org/llama.cpp/blob/master/docs/install.md)
- [llama.cpp server and tool-use documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [OpenCode llama.cpp provider configuration](https://opencode.ai/docs/providers#llama.cpp)
- [Qwen3.6-35B-A3B model](https://huggingface.co/Qwen/Qwen3.6-35B-A3B)
- [IQ4_XS GGUF and quantization sizes](https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF)
- [M1 Pro/32 GB measurements and methodology](https://github.com/marcofariasmx/local-llm-apple-silicon)
