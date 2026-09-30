# Maintainer notes

Machine-specific context that used to live in the README. None of this is
needed to use the repo — it is here so the tuning decisions stay
reproducible.

## Reference machine

The defaults in this repo were developed and validated on:

| | |
|---|---|
| GPU | RTX 5090, 32,607 MiB VRAM, Blackwell sm_120 |
| CPU | Ryzen 9 9900X3D, 12C/24T (split CCDs) |
| RAM | 61.6 GB |
| Disk | single ~1.86 TB volume |
| OS | Windows 11 Home |

`scripts/windows/start.bat` no longer hardcodes any of this — it reads
VRAM and physical core count via `probe_hardware.ps1` at launch. The numbers
above are what the hand-validated 131K context figure was measured
against.

## Context-sizing formula

`probe_hardware.ps1` computes:

```
free = VRAM - 1536 (driver) - weights - MTP - mmproj
            - 2048 (compute buffer) - 512 (draft KV) - 160 (DeltaNet state)

ctx  = floor( free * 0.85 * 1 MiB / 34,816 bytes-per-token / 4096 ) * 4096
```

The `0.85` covers allocation slack: buffers fragment, the compute buffer
grows with batch shape, and the driver footprint moves. Aiming at 100% of
the arithmetic budget reliably OOMs.

On the reference machine with `UD-Q5_K_XL` + MTP + vision this yields
exactly **131,072**, matching the value measured by hand before the
formula existed. That agreement is the reason for the specific constants;
if you change one, re-check that case.

`34,816 bytes/token` is `16 cached layers × 4 KV heads × 256 head-dim × 2
(K+V) = 32,768 elements`, at q8_0's 34 bytes per 32-element block.

## Model variants

`lib_variants.bat` / `lib_variants.sh` (in `scripts/windows/` and
`scripts/unix/`) are the only files that know what a
build *is*. A third variant means adding a branch there — the download,
start and launch scripts read repo, filename prefix and Cursor alias out
of it and are otherwise variant-blind.

**Why huihui-ai for the abliterated build.** There are on the order of
thirty abliterated Qwen3.8-27B GGUF repos. This one was picked because
its `UD-*` files are re-ablations of
`unsloth/Qwen3.8-27B-GGUF` — the exact quants this repo already targeted.
That makes the two builds directly comparable: same quant names, sizes
within 3%, so `probe_hardware.ps1` and the README context table need no
per-variant special-casing.

**The shared MTP head is an inherited claim, not a measurement.** Both
builds load `ggml-org`'s `mtp-Qwen3.8-27B-Q8_0.gguf` and unsloth's
`mmproj-F16.gguf`, on the strength of huihui's model card saying "MTP and
visual has not been modified". It is very likely fine — abliteration
changes weight values, not tensor shapes, and speculative decoding is
lossless regardless of how good the draft is, since the abliterated model
is still the verifier. The realistic failure mode is a *lower draft
acceptance rate*, showing up as reduced tok/s rather than wrong output.
If the abliterated build is unexpectedly slow, benchmark it with and
without the `--spec-type` block before looking anywhere else.

**Ablation depth.** huihui's `UD-*` series ablates layers 18–51 and
leaves 0–17 untouched, which is what keeps coding and tool-calling near
stock. They also publish a `UD-DW-*` series ablating only 23–51 (less
thorough, warns more); it is not wired up here.

**The size columns** in `scripts/windows/download.bat` are the actual byte
sizes from the Hugging Face file listings on 2026-09-01, and only feed the
free-space check. The stock column was previously off by up to 1 GB in
both directions; re-check both if either publisher reuploads.

## cmd.exe traps found the hard way

An audit pass on 2026-09-01 turned these up. All were latent in shipped
scripts; the scanner for the first one is worth re-running after edits.

- **Unescaped parentheses in an `echo` inside a `( )` block.** The `)` in
  `echo ... (merged b9180).` closed the block early and cmd printed
  `. was unexpected at this time.` on every launch on a pre-b9180 build.
  Hit `start.bat`, `install.bat` and `cleanup.bat`. Escape as
  `^(` / `^)`.
- **`::` comments inside a `( )` block.** Labels are not valid there;
  use `rem`.
- **`for /f` splits backquoted commands on commas.** `nvidia-smi
  --query-gpu=name,memory.total` reaches the exe as two unknown options.
  Quote each option whole: `nvidia-smi "--query-gpu=name,memory.total"`.
  Only inside `for /f` — a direct invocation is fine.
- **`llama-server --version` prints `version: 8679 (...)`, not "build".**
  `findstr /C:"build"` matches the *`built with Clang`* line instead and
  yields the word `with`.
- **`timeout /t` refuses to run when stdin is redirected**, returning
  instantly with `ERROR: Input redirection is not supported`. Any wait
  loop built on it spins when the script is driven from another script or
  a pipe. `:sleep` in `start.bat` falls back to `ping`.
- **Bare `call foo.bat` depends on cmd searching the current directory**,
  which `NoDefaultCurrentDirectoryInExePath=1` disables. Use
  `call "%~dp0foo.bat"`.
- **`%~` inside a `::` comment is still expanded.** cmd substitutes
  parameters before it knows the line is a comment, so a comment that
  mentions `%~1` by name aborts the whole script with `The following
  usage of the path operator in batch-parameter substitution is
  invalid`. Describe it in words.
- **`if COND set A & set B` runs `set B` unconditionally.** This made the
  download script's free-space check always assume the largest quant.

## Disk

This machine runs a single ~1.86 TB volume, so it fills up. Two things
worth knowing:

- `~/.cache/huggingface` holds ~180 GB from *other* research projects.
  `cleanup.bat` deliberately does not touch it.
- The KL-divergence reference logits (`models/kld-base-qwen3.8.dat`)
  produced by `measure_quant_quality` are large. Delete them once you
  have settled on a quant.

## Slurm

`scripts/unix/slurm-llama.sh` hardcodes `${HOME}/research/Local-LLM-setup-for-cursor`
as its working directory and requests `--gres=gpu:rtx5090:1` on the
`debug` partition. Both are site-specific; edit them for your cluster.

Do not start it while a manual `llama-server` is already running — they
will double-book the GPU.

## Superseded

Qwen3.6-35B-A3B was the previous default. It was replaced by Qwen3.8-27B
in August 2026: better coding scores, native MTP, and a hybrid-attention
stack that makes long context far cheaper. The Qwen3.6 scripts have been
removed; `cleanup_disk` will offer to delete the old weights.
