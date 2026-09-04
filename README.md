# Local LLM setup for Cursor IDE

**Run Qwen3.8-27B locally on your own GPU and use it inside Cursor as a
free, private, drop-in replacement for GPT and Claude.** A self-hosted,
OpenAI-compatible llama.cpp server with MTP speculative decoding, vision,
and a 131K context window on a single 32 GB card — no subscription, no
code leaving your machine. Stock or abliterated, picked at launch.

[![CI](https://github.com/Lampsdad/Local-LLM-setup-for-Cursor-IDE/actions/workflows/ci.yml/badge.svg)](https://github.com/Lampsdad/Local-LLM-setup-for-Cursor-IDE/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Stars](https://img.shields.io/github/stars/Lampsdad/Local-LLM-setup-for-Cursor-IDE?style=flat)](https://github.com/Lampsdad/Local-LLM-setup-for-Cursor-IDE/stargazers)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![llama.cpp](https://img.shields.io/badge/llama.cpp-b9180%2B-orange)
![Model](https://img.shields.io/badge/model-Qwen3.8--27B-purple)

```bat
kiln
```

One command on Windows. It prints what is installed, downloaded and
running, tells you the one thing to do next, and gives you a menu.
macOS and Linux are a three-script equivalent, shown below.

**Contents** — [Why not Ollama?](#why-not-just-use-ollama-or-lm-studio) ·
[Will this run on my GPU?](#will-this-run-on-my-gpu) ·
[Quick start](#quick-start) ·
[Why Qwen3.8 is different](#what-makes-qwen38-27b-different) ·
[Choosing a build](#choosing-a-build) ·
[Choosing a quant](#choosing-a-quant) ·
[Using with Cursor](#using-with-cursor) ·
[Security](#security) ·
[Scripts](#scripts) ·
[Tuned settings](#tuned-server-settings) ·
[Troubleshooting](#troubleshooting) ·
[FAQ](#faq)

---

## Why not just use Ollama or LM Studio?

Use those if you want any model running in two minutes. Use this if you
want *this* model running *well*:

- **MTP speculative decoding, actually wired up.** Qwen trains
  multi-token-prediction heads into Qwen3.8 and ships them as a separate
  GGUF. Loaded as a draft model, it is the single largest generation
  speedup available for this architecture. Most front-ends do not expose
  `--spec-type draft-mtp` at all.
- **Settings derived from the architecture, not copied from a 7B guide.**
  Qwen3.8 is 75% linear attention, which changes what KV precision and
  context sizing should be. The reasoning is written down below.
- **Context sized to your actual GPU.** `kiln` reads your
  VRAM and the weight files on disk and computes the window that fits,
  rather than assuming a card you may not own.
- **A measurement path, not just claims.** `benchmark_qwen3.8.*` and
  `quality` let you check every tuning decision here
  against your own hardware and your own copies of the files.
- **Remote access built in.** A Cloudflare tunnel plus a generated API
  key, so you can point Cursor at your desktop GPU from a laptop.

---

## Will this run on my GPU?

Context window that fits, by card and quant. Computed with the same
formula the launcher uses; `--` means it will not load.

**With MTP + vision enabled** (the default, and what you want):

| Quant | 16 GB | 24 GB | 32 GB | 48 GB |
|---|---|---|---|---|
| `UD-IQ3_XXS` | — | 128K | 256K | 256K |
| `UD-Q4_K_XL` | — | — | 184K | 256K |
| **`UD-Q5_K_XL`** | — | — | **131K** | 256K |
| `UD-Q6_K_XL` | — | — | — | 256K |
| `Q8_0` | — | — | — | 256K |

**Without the MTP head** (frees ~3.5 GB, costs you the speedup):

| Quant | 16 GB | 24 GB | 32 GB | 48 GB |
|---|---|---|---|---|
| `UD-IQ3_XXS` | 12K | 216K | 256K | 256K |
| `UD-Q4_K_XL` | — | 72K | 256K | 256K |
| `UD-Q5_K_XL` | — | 16K | 216K | 256K |
| `UD-Q6_K_XL` | — | — | 84K | 256K |
| `Q8_0` | — | — | — | 256K |

**Reading this table:**

- **32 GB (5090 / 4090 48GB mod / A6000)** — the target. `UD-Q5_K_XL`
  with MTP and vision at 131K is the default and needs no configuration.
- **24 GB (3090 / 4090 / 7900 XTX)** — you must choose. `UD-IQ3_XXS`
  keeps MTP and a large window but is weak at agentic tool-calling;
  `UD-Q4_K_XL` without MTP is the better coding model at 72K. Delete the
  MTP GGUF to take the second path.
- **16 GB** — 27B is the wrong size for this card. Qwen3.8's smaller
  siblings will serve you far better.
- **48 GB+** — everything fits at the model's full 256K.

Apple Silicon and Linux use `--fit on`, which lets llama.cpp size the
window against unified/GPU memory at load time, so no table lookup is
needed there.

---

## Quick start

### Windows

```bat
git clone https://github.com/Lampsdad/Local-LLM-setup-for-Cursor-IDE
cd Local-LLM-setup-for-Cursor-IDE
kiln
```

That is the whole install. `kiln` prints a status board, tells you the
one thing to do next, and gives you a menu:

```
  _     _  _        
 | | __(_)| | _ __  
 | |/ /| || || '_ \ 
 |   < | || || | | |
 |_|\_\|_||_||_| |_|  local models, fired on your own GPU

 ------------------------------------------------------------
  llama.cpp      installed  build 9431
  MTP support    available
  cloudflared    installed
  GPU            NVIDIA GeForce RTX 5090, 32607 MiB
  disk free      392 GB
 ------------------------------------------------------------
  Qwen3.8-27B    UD-Q5_K_XL
   abliterated   UD-Q5_K_XL
  shared files   MTP head   vision
 ------------------------------------------------------------
  server         stopped
  API key        xxxxxx...xxxx   kiln key show
  tunnel         none
 ------------------------------------------------------------

 Next:  kiln start    serve a model to Cursor
```

The `Next:` line is the first unmet dependency, so following it
repeatedly walks you from an empty checkout to a served model. Colour is
automatic and honours `NO_COLOR`.

Every step is also a verb, if you would rather drive it yourself:

```bat
kiln status       :: just the board
kiln setup        :: llama.cpp, cloudflared, modelskiln update       :: upgrade llama.cpp (needed for MTP)
kiln get both     :: download the stock and abliterated weights
kiln start        :: pick a build and serve it
kiln start ablit  :: skip the picker
kiln stop         :: stop the server and the tunnel
kiln key show     :: print the API key for Cursor
kiln bench        :: quant speed and throughput sweep
kiln clean        :: reclaim disk from superseded GGUFs
```

### macOS and Linux

```bash
git clone https://github.com/Lampsdad/Local-LLM-setup-for-Cursor-IDE
cd Local-LLM-setup-for-Cursor-IDE
./kiln.sh
```

Same verbs, same order. `kiln.sh` detects macOS, Debian/Ubuntu or
Fedora/RHEL and calls the right platform script for you:

```bash
./kiln.sh setup           # llama.cpp, cloudflared, models/
./kiln.sh get both        # download the stock and abliterated weights
./kiln.sh start           # serve a model to Cursor
./kiln.sh start ablit     # or the abliterated build
./kiln.sh stop
./kiln.sh key show
```

Override the quant with an environment variable:

```bash
QUANT=UD-Q4_K_XL ./kiln.sh get
```

All platforms support MTP, vision, both builds and the generated API
key. The shell path sizes context with llama.cpp's `--fit on` rather
than the Windows probe, so no table lookup is needed there.
`scripts/unix/slurm-llama.sh` runs the same server as a Slurm batch job
so the GPU shows as allocated in `squeue`.

---

## What makes Qwen3.8-27B different

Three architectural facts drive nearly every setting in this repo.

**1. It is 75% linear attention.** The layer stack is
`16 × (3 × GatedDeltaNet → 1 × GatedAttention)` — 64 layers total, of
which only **16 hold a KV cache**. The other 48 carry a small fixed-size
recurrent state.

Two consequences:

- **Long context is unusually cheap.** KV cost is
  `16 layers × 4 KV heads × 256 head-dim × 2 (K+V)` = 32,768
  elements/token → **64 KiB/token at f16, 34 KiB at q8_0**. A comparable
  dense transformer with all 64 layers cached would cost four times as
  much. This is why the table above shows 131K where a normal 27B would
  give you 16K.
- **Low-bit KV hurts more than usual.** In recurrent layers, error
  accumulates *along the sequence* instead of being re-anchored against a
  cache each token. This repo uses `q8_0` KV, not the `q4_0` that older
  Qwen3.6 setups used.

**2. MTP is trained into the weights but ships as a separate file.**
Qwen trains multi-token-prediction heads directly into the model. In
llama.cpp these load as a *draft model* for speculative decoding:

```
--spec-type draft-mtp --spec-draft-model models/mtp-Qwen3.8-27B-Q8_0.gguf --spec-draft-n-max 3
```

This needs **llama.cpp b9180 or newer**
([PR #22673](https://github.com/ggml-org/llama.cpp/pull/22673), merged
2026-05-16). Older builds reject the flag outright. The MTP head is only
published by `ggml-org/Qwen3.8-27B-GGUF`, so it is paired with unsloth
weights — both are conversions of the same upstream checkpoint, so vocab
and hidden dims match.

**3. The vocab is enormous — 248,320 tokens, untied embeddings.** That is
`248320 × 5120` for the input embedding *and* again for the output head:
roughly 2.5B params, ~9% of the model, concentrated in two tensors. Naive
quants crush them.

> **Use Unsloth `UD-*_XL` quants.** The `_XL` suffix means embed/output
> are kept at higher precision. This is why `UD-Q4_K_XL` (17.9 GB) is
> *larger* than plain `Q4_K_M` (17.1 GB) — and on a vocab this size, that
> difference does real work.

It is also a native VLM (images and video), so `--mmproj` is wired up by
default.

---

## Choosing a build

Two variants are wired up. `kiln start` shows both, marks which are on
disk, and downloads the one you pick.

| | Stock | Abliterated |
|---|---|---|
| Weights | [`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF) | [`huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF`](https://huggingface.co/huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF) |
| Cursor model name | `qwen3.8-27b` | `qwen3.8-27b-abliterated` |
| Refusal behaviour | as Qwen shipped it | ablated |
| Weights on disk | ~20 GB | ~21 GB |
| `kiln start` argument | `base` | `ablit` |

**They cost less together than apart.** huihui-ai's `UD-*` quants are
re-ablations of the same unsloth GGUFs this repo already used, with the
ablation confined to layers 18–51 and the MTP head and vision tower left
alone. So both builds share one copy of `mtp-Qwen3.8-27B-Q8_0.gguf`
(3.2 GB) and `mmproj-F16.gguf` (0.93 GB) — the second build you download
is weights-only. It also means the quant names, the file sizes, and the
context table above apply unchanged to both.

**Only one runs at a time.** They share port 8080, and the start script
stops any running server before starting the next, so `kiln start` is a
switch rather than a way to serve both at once. The distinct `--alias`
values are what keep them apart in Cursor's model list — you will not
silently be talking to the other one.

**What abliteration actually costs.** It is refusal-direction ablation,
not fine-tuning: the refusal direction is projected out of the residual
stream. Keeping layers 0–17 untouched is what preserves most of the
coding and tool-calling ability, but this is still a modified model with
no published evaluation of its behaviour, and it will answer things the
stock build declines. If you expose it through the Cloudflare tunnel,
the generated API key is the only thing between it and the open
internet — see [Security](#security).

Reach for the stock build unless you have a specific reason not to; it is
what the tuning numbers below were measured on.

---

## Choosing a quant

| Quant | Size | Est. KLD vs BF16 | Notes |
|---|---|---|---|
| `Q8_0` | 29.0 GB | ~0.01% | reference for benchmarking only |
| `UD-Q6_K_XL` | 25.9 GB | ~0.05% | needs 48 GB to keep the MTP head |
| **`UD-Q5_K_XL`** | **20.2 GB** | **~0.2%** | **default — best quality that keeps MTP on 32 GB** |
| `UD-Q4_K_XL` | 17.9 GB | ~0.7% | best coding model that fits 24 GB, MTP off |
| `UD-IQ3_XXS` | 11.9 GB | ~3% | keeps MTP on 24 GB; weak on agentic tool-calling |

The KLD column is a **general pattern for 27B-class dense models, not a
measurement of Qwen3.8**. To measure it on your own files, run
`kiln quality` (`./kiln.sh quality` on Unix) — it scores each quant you have
against Q8_0 by KL-divergence.

Why KL-divergence rather than perplexity: for agentic coding the failure
mode is not worse prose, it is **malformed tool-call JSON and dropped
instructions on step 12 of a 20-step task**. Perplexity can look fine
while the argmax token flips; KLD and the "same top token" rate catch
that.

### VRAM budget at the default (UD-Q5_K_XL, 131K ctx, 32 GB card)

```
weights  UD-Q5_K_XL        18.83 GiB
MTP head Q8_0               2.95 GiB
mmproj   F16                0.86 GiB
KV @131K q8_0 (16 layers)   4.25 GiB
MTP draft KV                0.50 GiB
DeltaNet recurrent state    0.15 GiB
compute buffer             ~2.00 GiB
─────────────────────────────────────
total                     ~29.5 GiB   of ~30.3 GiB usable
```

---

## Using with Cursor

**One-time setup** — Settings (`Ctrl+Shift+J`) → Models:

1. **Base URL** — check *Override OpenAI Base URL*, paste the URL the
   start script prints, with `/v1` appended.
2. **API key** — paste the key the start script prints (from
   `api_key.txt`). Requests without it are rejected.
3. **Add model** — type `qwen3.8-27b` in *Add Model*, press Enter, click
   **Verify**. If you also run the abliterated build, add
   `qwen3.8-27b-abliterated` as a second model; the launcher prints which
   name the running server answers to.
4. Uncheck provider models you don't want to hit by accident.

**Every session:** the quick-tunnel URL changes on restart, so update the
Base URL each time. To stop that, see below.

| Cursor feature | Works? |
|---|---|
| Chat (`Ctrl+L`) | Yes |
| Inline edit (`Ctrl+K`) | Yes |
| Composer / multi-file | Yes |
| `@Codebase` | Yes |
| Tab autocomplete | No — requires a Cursor-hosted model |

### Getting a URL that does not change

The quick tunnel is zero-setup but rotates its hostname on every restart.
For a stable address, register a
[named Cloudflare tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/):
you get a fixed subdomain on a domain you control, and can put a
Cloudflare Access policy in front of it instead of relying on the API key
alone. Worth the fifteen minutes if you use this daily.

---

## Security

The quick-tunnel URL is **public** — anyone who guesses or scrapes the
hostname can reach it. Every start script therefore generates a random
key into `api_key.txt` and passes it via `--api-key-file`. Requests
without it are rejected. Cursor makes you fill in an API-key field
anyway, so this costs nothing.

The key is 24 bytes from the platform CSPRNG, and the file is locked to
your account on both platforms — `chmod 600` on Unix, and on Windows
`icacls /inheritance:r /grant:r` so other accounts on the machine cannot
read it. That lockdown is reapplied on every launch, so a key written
before this existed gets fixed the next time you start the server.

```bat
kiln key show           :: print it (also generates it the first time)
kiln key rotate         :: throw it away and make a new one
kiln key set MY-SECRET  :: use a passphrase you choose instead
```

`kiln key set` accepts anything on one line — llama-server compares it
verbatim. Rotating or setting takes effect on the next server start, and
you have to paste the new value into Cursor.

The server also binds `0.0.0.0`, so the key is what protects you on any
shared network, not just over the tunnel.

---

## Scripts

You only ever type `kiln` (or `./kiln.sh`). Everything below sits in
`scripts/` and is dispatched for you — this table is a map for people
who want to read or change it.

```
kiln.bat / kiln.sh     the front door you type
scripts/windows/       everything cmd.exe runs
scripts/unix/          everything macOS and Linux run
assets/banner.txt      the wordmark
NOTES.md               why the tuned constants are what they are
```

**The CLI**

| Script | Purpose |
|---|---|
| `kiln.bat` | Windows front door. A shim onto `scripts/windows/kiln.bat`. |
| `kiln.sh` | macOS/Linux front door. Detects the platform and dispatches to `scripts/unix/`. |
| `scripts/windows/kiln.bat` | The real CLI: status board, menu, and a verb for every step. |

**Windows** (`scripts/windows/`)

| Script | Purpose |
|---|---|
| `install.bat` | One-time setup: llama.cpp binaries, cloudflared, `models/`. Pinned to the CUDA 13.3 x64 asset. |
| `update.bat` | Upgrade llama.cpp to the latest release, backing up the old build. Verifies MTP support afterward. |
| `download.bat` | Weights + MTP head + vision projector, for one build. Resumable. |
| `launch.bat` | Model picker: stock or abliterated, downloading first if needed. Takes `base` / `ablit` to skip the menu. |
| `start.bat` | Tuned launcher. Auto-detects build, quant, MTP, vision, VRAM and cores. |
| `probe_hardware.ps1` | Reads VRAM/cores and computes the context window that fits. |
| `benchmark.bat` | Quant speed, ubatch sweep, KV precision, throughput vs depth. |
| `quality.bat` | KL-divergence of each quant against Q8_0. |
| `cleanup.bat` | Reclaim space from superseded GGUFs. Requires typing `DELETE`. |
| `lib_variants.bat` | Definition of each build — repo, filename prefix, Cursor alias. Add a third variant here. |
| `lib_api_key.bat` | Generates the API key, locks the file to your account, hands back `API_KEY`. |
| `lib_ui.bat` | ANSI palette for the CLI. Degrades to empty strings under `NO_COLOR`. |

**macOS and Linux** (`scripts/unix/`)

| Script | Purpose |
|---|---|
| `install_mac.sh` / `install_linux.sh` / `install_fedora.sh` | One-time setup, per platform. |
| `download.sh` | Weights + MTP head + vision projector. `QUANT=` and `VARIANT=` override. |
| `start_mac.sh` / `start_linux.sh` / `start_fedora.sh` | Tuned launchers, sizing context with `--fit on`. |
| `slurm-llama.sh` | Run the server as a Slurm job so the GPU shows as allocated. |
| `start-cloudflared-once.sh` | Bring up the tunnel on its own. |
| `benchmark.sh` / `quality.sh` / `cleanup.sh` | Shell twins of the Windows tools. |
| `lib_variants.sh` / `lib_api_key.sh` | Shell twins of the Windows libraries. |

---

## Tuned server settings

| Flag | Value | Why |
|---|---|---|
| `--n-gpu-layers` | 99 | all 64 layers on GPU |
| `--ctx-size` | detected | computed from your VRAM by `probe_hardware.ps1`; `--fit on` does the same job on Unix |
| `--flash-attn` | `auto` | not `on` — gated attention at 256 head-dim falls back cleanly instead of erroring |
| `--cache-type-k/v` | `q8_0` | halves KV vs f16; **not** `q4_0`, see the recurrent-layer note above |
| `--parallel` | `1` | **the easy win.** The default (`-1` = auto) splits the KV cache across slots, so each request gets `ctx/N`. Single-user Cursor wants the whole window in one slot. |
| `--batch-size` / `--ubatch-size` | 4096 / 1024 | larger prefill batches; a 32 GB card has the bandwidth and headroom |
| `--threads` | detected | physical cores only — with everything on GPU, counting SMT siblings just adds contention |
| `--jinja` | on | correct tool-call parsing for agentic use |
| `--reasoning-format` | `deepseek` | puts chain-of-thought in `message.reasoning_content` so thinking tokens stay out of code output |
| sampling | `temp 1.0, top-p 0.95, top-k 20, min-p 0.0` | Qwen's published thinking-mode values |
| `--api-key-file` | `api_key.txt` | see Security |

The batch sizes and KV precision are reasoned from the architecture,
**not measured**. `benchmark_qwen3.8.*` measures them so you can confirm
or override.

---

## Troubleshooting

**Model loads but generation is slow.** Check that MTP actually engaged —
`server.log` should mention the draft model. If `--spec-type draft-mtp`
was rejected, your llama.cpp predates b9180; run `kiln update`.

**Out of memory at load.** The launcher sizes context to your card, but
its estimate is not exact. Drop to the next quant down, or delete the MTP
GGUF to free ~3.5 GB. See the GPU table above.

**"these weights do not leave room for any context".** The fixed costs
alone exceed your VRAM. Take a smaller quant.

**Sudden catastrophic slowdown on Windows.** When VRAM is exceeded, the
NVIDIA driver silently spills to system RAM instead of failing. Set
*NVIDIA Control Panel → Manage 3D Settings → CUDA - Sysmem Fallback
Policy* to **Prefer No Sysmem Fallback** for `llama-server.exe` so you get
a clean OOM instead of a 50× slowdown.

**Cursor says the model is unreachable.** The tunnel URL rotates on every
restart — re-paste it. If it still fails, confirm the API key in Cursor
matches `api_key.txt`.

---

## FAQ

**Can I use a local LLM with Cursor?** Yes. Cursor lets you override the
OpenAI base URL and add a custom model name, which is all an
OpenAI-compatible server needs. That is what this repo sets up.

**Do I still need a Cursor subscription?** You still need a Cursor
account, and some Cursor features are gated by your plan no matter which
model serves the tokens. But chat, inline edit, Composer and `@Codebase`
run against your own GPU here, so they do not consume request quota.

**Does my code leave my machine?** The model runs locally, so prompts and
completions stay on your GPU. Cursor itself still talks to Cursor's
servers for editor features and, if you use the quick tunnel, your traffic
is proxied through Cloudflare. For a fully local path, skip the tunnel —
see the next question.

**Can I run it without a tunnel?** The scripts support it: if `cloudflared`
is not installed they serve on `http://localhost:8080/v1` and say so.
Cursor's *Verify* step generally wants a URL it can reach from outside,
which is why the tunnel exists — but any other OpenAI-compatible client
works against localhost directly.

**Does Tab autocomplete work?** No. Cursor's Tab model is hosted by Cursor
and cannot be pointed at a custom endpoint. Chat, `Ctrl+K`, Composer and
`@Codebase` all work.

**Will it run on a 3090, 4090 or 7900 XTX (24 GB)?** Yes, but you have to
choose between MTP and quant quality — see
[the table above](#will-this-run-on-my-gpu). On 16 GB, pick a smaller
model instead.

**Does this work with VS Code, Continue, Cline, Roo Code, Zed or Aider?**
Yes. The server is a plain OpenAI-compatible endpoint, so anything that
accepts a base URL, an API key and a model name will talk to it. Only the
Cursor-specific setup steps differ.

**How fast is it?** That depends on your card, quant and draft acceptance
rate, so this repo ships a measurement path rather than a number:
`kiln bench` (`./kiln.sh bench` on Unix). MTP speculative decoding is the single
largest lever — confirm it engaged before comparing anything.

**Why Qwen3.8-27B and not a bigger model?** 27B at `UD-Q5_K_XL` is the
largest capable coding model that fits a 32 GB card *while keeping the MTP
head resident*. See [what makes it
different](#what-makes-qwen38-27b-different).

**Is the abliterated build safe to expose?** It has had its refusal
behaviour removed and no published evaluation of its behaviour. If you
tunnel it, your API key is the only control in front of it. Read
[SECURITY.md](SECURITY.md) first.

---

## Contributing

Hardware reports are the most useful contribution — the GPU table is
computed, and only the RTX 5090 row is hand-validated. If you ran this on
a different card, [tell us what
loaded](../../issues/new?template=hardware_report.yml).

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions, and
[NOTES.md](NOTES.md) for the reasoning behind the tuned constants and a
list of cmd.exe traps already found the hard way.

---

## Requirements

**Windows:** Windows 10/11, NVIDIA GPU with a CUDA 13 driver, Python 3.8+.
**macOS:** macOS 12+, Apple Silicon or Intel (Metal), Python 3.8+, `curl`, `unzip`.
**Linux:** NVIDIA driver with `nvidia-smi`, Python 3.8+, `curl`, `unzip`.

Disk: 20–30 GB per quant, plus ~4 GB for the MTP head and vision
projector.

---

## License

MIT — see [LICENSE](LICENSE).

Model weights are governed by their own licenses:
[Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B).
