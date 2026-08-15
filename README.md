# Local LLM setup for Cursor IDE

Run **Qwen3.8-27B** on your own GPU and use it inside Cursor as a drop-in
OpenAI-compatible model — with MTP speculative decoding, vision, and a
131K context window on a single 32 GB card.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
![llama.cpp](https://img.shields.io/badge/llama.cpp-b9180%2B-orange)
![Model](https://img.shields.io/badge/model-Qwen3.8--27B-purple)

```bat
run.bat
```

One command on Windows. It works out which step you are on — install,
upgrade, download, or launch — and runs it. macOS and Linux are a
three-script equivalent, shown below.

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
- **Context sized to your actual GPU.** `probe_hardware.ps1` reads your
  VRAM and the weight files on disk and computes the window that fits,
  rather than assuming a card you may not own.
- **A measurement path, not just claims.** `benchmark_qwen3.8.*` and
  `measure_quant_quality.*` let you check every tuning decision here
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
run.bat
```

Or drive the steps yourself:

```bat
install_windows.bat         :: one-time: llama.cpp, cloudflared, models\
update_llama_bin.bat        :: get a build with MTP support (b9180+)
download_qwen3.8_27b.bat    :: weights + MTP head + vision projector
start_qwen3.8_27b.bat       :: launch server + tunnel
```

### macOS

```bash
./install_mac.sh
./download_model.sh          # QUANT=UD-Q4_K_XL ./download_model.sh to override
./start_mac.sh
```

### Linux

```bash
./install_linux.sh           # or ./install_fedora.sh
./download_model.sh
./start_linux.sh             # or ./start_fedora.sh
```

All three shell paths support MTP, vision, and the generated API key,
and size context with `--fit on`. `slurm-llama.sh` runs the same server
as a Slurm batch job so the GPU shows as allocated in `squeue`.

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
`measure_quant_quality.bat` (or `.sh`) — it scores each quant you have
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
   **Verify**.
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
key into `api_key.txt` (gitignored, `chmod 600` on Unix) and passes it via
`--api-key-file`. Requests without it are rejected.

Cursor makes you fill in an API-key field anyway, so this costs nothing.

To rotate the key, delete `api_key.txt` and restart — a new one is
generated. Note that the server also binds `0.0.0.0`, so the key is what
protects you on any shared network, not just over the tunnel.

---

## Scripts

| Script | Purpose |
|---|---|
| `run.bat` | Windows entry point. Detects your state and runs the right step. |
| `install_windows.bat` | One-time setup: llama.cpp binaries, cloudflared, `models/`. Pinned to the CUDA 13.3 x64 asset. |
| `install_mac.sh` / `install_linux.sh` / `install_fedora.sh` | Same, per platform. |
| `update_llama_bin.bat` | Upgrade llama.cpp to the latest release, backing up the old build. Verifies MTP support afterward. |
| `download_qwen3.8_27b.bat` / `download_model.sh` | Weights + MTP head + vision projector. Resumable. |
| `start_qwen3.8_27b.bat` | Tuned Windows launcher. Auto-detects quant, MTP, vision, VRAM, and cores. |
| `start_mac.sh` / `start_linux.sh` / `start_fedora.sh` | Same, per platform, using `--fit on`. |
| `slurm-llama.sh` | Run the server as a Slurm job so the GPU shows as allocated. |
| `probe_hardware.ps1` | Reads VRAM/cores and computes the context window that fits. |
| `benchmark_qwen3.8.bat` / `.sh` | Quant speed, ubatch sweep, KV precision, throughput vs depth. |
| `measure_quant_quality.bat` / `.sh` | KL-divergence of each quant against Q8_0. |
| `cleanup_disk.bat` / `.sh` | Reclaim space from superseded GGUFs. Requires typing `DELETE`. |

`start_windows.bat` and `download_model.bat` forward to the Qwen3.8
scripts.

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
was rejected, your llama.cpp predates b9180; run `update_llama_bin.bat`.

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
