# Validation record

Initially validated locally on August 26, 2026 (America/New_York). The 32K,
64K, and 128K context activations were validated on August 28, 2026.

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

At the initial baseline, the running model reported 35,505,251,456 parameters,
a 262,144-token training context, a 16,384-token runtime context, and a
19,688,563,200-byte IQ4_XS weight file.

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
subagents, and LSP while retaining core repository read, search, edit, and
shell tools. Web tools were disabled in the initial baseline and enabled in the
later activation recorded below. The end-to-end check passed after the initial
reduction.

## Measured inference

The deterministic health prompt generated about 20.0 tokens/second. The
repeatable Rust LRU benchmark generated 1,024 tokens at 35.3 tokens/second,
with prompt processing at 91.9 tokens/second for its 30-token prompt. These are
single observations, not a controlled performance study.

At the final idle observation, the llama.cpp process had approximately 11.6
GiB resident according to `ps`; system-wide encrypted swap usage was 1.66 GiB.
That swap figure includes the rest of the running Mac and is not attributed
solely to llama.cpp.

## 32K context activation

On August 28, 2026, the committed server default and OpenCode provider limit
were raised together from 16,384 to 32,768 tokens. The setup was reapplied and
the transient launchd server was restarted. The live process command contained
`--ctx-size 32768`, and `/v1/models` reported `n_ctx: 32768`.

The static checks, deterministic completion check, structured tool-call check,
and OpenCode file-tool smoke test were rerun after the restart. This activation
establishes that the 32K configuration loads and completes those checks; it does
not supersede the 16K throughput measurements above or establish long-duration
memory-pressure stability.

## 64K context activation

Later on August 28, 2026, the committed server default and OpenCode provider
limit were doubled again from 32,768 to 65,536 tokens. The setup was reapplied
and the transient launchd server was restarted. The live process command
contained `--ctx-size 65536`, and `/v1/models` reported `n_ctx: 65536`.

The same static, completion, structured tool-call, and OpenCode file-tool checks
were rerun after this restart. The 64K configuration remains experimental on a
32 GB M1 Pro; successful startup and smoke checks do not establish sustained
memory-pressure stability or better task quality.

Immediately after the smoke checks, `ps` reported 19,791,696 KiB of resident
memory for the llama.cpp process. The system-wide memory snapshot reported 24%
free memory and 1,930.12 MiB of encrypted swap in use. These are point-in-time,
system-wide observations; the swap figure cannot be attributed solely to this
process or to the context increase.

## 128K context activation

Later on August 28, 2026, the committed server default and OpenCode provider
limit were doubled from 65,536 to 131,072 tokens. The setup was reapplied and
the transient launchd server was restarted. The live process command contained
`--ctx-size 131072`, the server log reported `n_ctx_slot = 131072`, and
`/v1/models` reported `n_ctx: 131072`. The installed OpenCode configuration
also advertised a 131,072-token context and a 4,096-token output limit.

`make test`, `make health`, `make tool-test`, and `make agent-smoke` all passed
after the restart. The checks proved a deterministic completion, a structured
tool call with validated arguments, and an end-to-end OpenCode repository read.
They did not submit a prompt larger than 64K, fill the 128K KV cache, or prove
long-duration stability, better task quality, or freedom from compaction.

Immediately after the smoke checks, `ps` reported 19,710,976 KiB of resident
memory for the llama.cpp process. The system-wide memory snapshot reported 23%
free memory and 1,890.12 MiB of encrypted swap in use. These are point-in-time,
system-wide observations; the swap figure cannot be attributed solely to this
process or to the context increase. A 128K slot is a maximum practical
experiment on this 32 GB machine and requires continued memory monitoring.

## Web access and auto-approval activation

Later on August 28, 2026, the installed OpenCode configuration enabled
`websearch` and `webfetch` and changed every enabled OpenCode permission from
interactive approval to `allow`. `opencode debug config` resolved repository
read/search/edit, shell, external-directory, web-search, web-fetch, question,
todo, and doom-loop permissions to `allow`; disabled skill, subagent, and LSP
tools remained denied and unavailable.

The installed `~/.local/bin/opencode` launcher exports
`OPENCODE_ENABLE_EXA=1`, which makes hosted Exa search available to this local
provider without an API key. It also exports
`OPENCODE_DISABLE_EXTERNAL_SKILLS=1`. The latter is necessary on this account:
the first live web test failed before a tool call because external Claude/agent
skill permission entries expanded the request to 131,740 tokens, beyond the
131,072-token server limit. With external discovery disabled, the serialized
build-agent definition fell from approximately 457 KB to 2.6 KB.

After reinstalling the launcher and configuration, `make web-smoke` completed
without an approval prompt. The model called `websearch`, found
`https://opencode.ai/docs/tools/`, called `webfetch` on that page, and returned
`LOCAL_WEB_TOOLS_OK`. This proves live use of both configured web tools through
the local-model/OpenCode path. It does not make retrieved content trustworthy,
prove factual synthesis quality, or keep search queries and fetched content on
the Mac.

## Current operating boundary

- API: `http://127.0.0.1:8080`
- Context: 128K, experimental
- Parallel slots: one
- Vision projector: disabled
- MCP: disabled
- Autostart at login: disabled
- OpenCode skills, subagents, and LSP tool: disabled
- OpenCode web search and fetch: enabled through hosted services
- OpenCode enabled actions: auto-approved; no confirmation prompt
