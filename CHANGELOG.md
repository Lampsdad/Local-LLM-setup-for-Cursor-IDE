# Changelog

Notable changes to the scripts. Dates are the commit dates on `main`.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **`kiln hardware`** — reads the GPU and prints the model, quant, MTP
  head, vision projector and context window that fit it, which is exactly
  what `kiln get` will download. Available as `kiln hardware` and
  `./kiln.sh hardware`.
- **`scripts/hardware.py`** — the model registry and the sizing
  arithmetic, shared by every script on both platforms. Holds the repos,
  the quant ladders with exact byte counts, and the per-family KV-cache
  model. Also generates the context tables in `README.md`, so the docs
  cannot drift from the code.
- **Two smaller model families**, for cards a 27B has no business on:
  `9b` and `4b`, Empero's Apache-2.0 distillations of Qwen3.8-2.4T-A95B.
  Both are third-party rather than Qwen releases, and are labelled as such
  everywhere they are offered. Both are text-only — no MTP head, no vision.
- **Six more 27B quants.** The ladder is now the eleven `UD-*` names
  present in both the unsloth and huihui-ai repos, rather than five.
- **The q4_0 MTP head and the q8_0 vision projector.** 1.4 GB and 0.3 GB
  smaller than the ones used before, and the reason a 24 GB card can now
  keep speculative decoding.

### Changed

- **The default model and context window are chosen from your GPU, not
  assumed.** `kiln get` used to default to `UD-Q5_K_XL` on every machine —
  right on the 32 GB card this repo was tuned on, a guaranteed OOM on a
  12 GB one. Downloads, launches and menus now default to what fits, and
  say what they picked. An explicit `QUANT=` or `VARIANT=` still wins.
- **24 GB cards no longer have to choose between MTP and quant quality.**
  `UD-IQ4_XS` with the q4_0 head reaches ~104K with speculative decoding
  on. The README previously recommended giving up MTP for `UD-Q4_K_XL` at
  72K; that advice predated the smaller head.
- **`kiln start` prefers the tier's quant among the files on disk** and
  prints a one-line note when a better one exists, but never re-picks
  weights behind your back.
- The three Unix start scripts and `slurm-llama.sh` now share
  `lib_select.sh` instead of each carrying its own hardcoded quant, MTP
  filename and context.

### Fixed

- **The documented 131K context on a 32 GB card was never what the code
  produced.** The probe computes 114688 with `UD-Q5_K_XL` + the q8_0 head
  + f16 vision; 131072 is what loaded when tried by hand. The comment
  claiming the 0.85 safety factor reproduced 131072 was wrong, and every
  131K in the README has been corrected to the computed figure.
- **`start_mac.sh` and `start_fedora.sh` exited silently when the vision
  projector was absent.** `[ -f "$MMPROJ" ] && EXTRA+=(...)` returns
  non-zero under `set -euo pipefail`, killing the script before it printed
  anything. Same bug in `slurm-llama.sh`.
- **The Unix scripts could not find Python on Windows shells.** `command
  -v python3` resolves to the Microsoft Store alias stub, which exits 0
  and prints nothing, so every lookup silently fell back. `lib_python.sh`
  now verifies the interpreter answers, and strips the CR that Windows
  Python puts on each line — a trailing `` made `V_MTP` compare unequal
  to `1` while still printing as `1`.
- **The status board's "shared files" row** reported "no MTP head" on
  machines given the q4_0 head, because it matched the q8_0 filename only.

## [1.0.0] — 2026-09-03

First tagged release. The repo has been usable for months; this marks the
point where the Qwen3.8 path, the API key, and the `kiln` CLI are all in
place across every platform.

### Added

- **`kiln`, a single entry point on every platform.** Prints a status
  board of what is installed, downloaded and running, names the one thing
  to do next, and offers a menu. Verbs for every step: `status`, `setup`,
  `update`, `get`, `start`, `stop`, `key`, `bench`, `clean`. `kiln.bat` on
  Windows, `./kiln.sh` on macOS and Linux — the latter detects your
  distribution and dispatches to the right platform script.
- **A `scripts/` layout.** The repo root was 36 loose files; it is now the
  entry point plus documentation, with `scripts/windows/` and
  `scripts/unix/` holding the rest.
- **Shared libraries** — `lib_variants`, `lib_api_key`, `lib_ui` — so the
  Windows and shell script families no longer duplicate variant
  definitions or key handling.
- **Abliterated build** alongside the stock one, selectable at launch with
  `kiln start ablit` or `VARIANT=ablit`. Both builds share one copy of the
  MTP head and vision projector, so the second download is weights-only.
- **`scripts/unix/slurm-llama.sh`**, to run the server as a Slurm batch job so the GPU
  shows as allocated in `squeue`.
- **`kiln quality`**, scoring each quant against `Q8_0` by
  KL-divergence rather than perplexity.
- **`kiln bench`** — quant speed, ubatch sweep, KV precision and
  throughput vs. context depth.
- **`kiln clean`**, to reclaim space from superseded GGUFs. Requires
  typing `DELETE`.

### Changed

- **Default model is now Qwen3.8-27B**, replacing Qwen3.6-35B-A3B. Better
  coding scores, native MTP, and a hybrid-attention stack that makes long
  context far cheaper.
- **MTP speculative decoding is wired up by default** via
  `--spec-type draft-mtp`, which needs llama.cpp **b9180+**
  ([PR #22673](https://github.com/ggml-org/llama.cpp/pull/22673)).
- **Context is sized from your actual hardware.** `probe_hardware.ps1`
  reads VRAM and the weight files on disk and computes the window that
  fits; the shell scripts use llama.cpp's `--fit on`. No card is
  hardcoded any more.
- **KV cache precision raised to `q8_0`** from the `q4_0` used in the
  Qwen3.6 setup. In a 75%-linear-attention stack, low-bit KV error
  accumulates along the sequence instead of being re-anchored each token.
- **`--parallel 1`** rather than llama.cpp's auto default, which splits
  the KV cache across slots and hands a single-user Cursor session only
  `ctx/N` of its own context window.

### Removed

- **Legacy Windows forwarders** `run.bat`, `start_windows.bat` and
  `download_model.bat`. Use `kiln` instead.
- The `qwen` command is now `kiln`. It collided with Alibaba's official
  Qwen Code CLI and tied the tool to a single model family.

### Security

- **All platforms now generate an API key** into `api_key.txt` and serve
  with `--api-key-file`. The file is locked to the invoking account on
  every launch (`chmod 600`; `icacls /inheritance:r` on Windows). See
  [SECURITY.md](SECURITY.md).

### Fixed

- A batch of cmd.exe bugs that were latent in shipped scripts: unescaped
  parentheses inside `( )` blocks aborting the launcher, `::` comments
  inside blocks, `for /f` splitting `nvidia-smi` options on commas,
  `timeout /t` spinning when stdin is redirected, and
  `if COND set A & set B` running the second `set` unconditionally. All
  are written up in [NOTES.md](NOTES.md).
- Line endings pinned in `.gitattributes` — a `.sh` checked out with CRLF
  fails on Linux with `\r: command not found`.

## Earlier

- **2026-07-21** — Slurm launch path and a `cloudflared` helper.
- **2026-04-25** — Fedora support (thanks @EmeryJJ).
- **2026-04-24** — Initial local model setup, Windows start scripts, and
  Cursor instructions.

[1.0.0]: https://github.com/Lampsdad/Local-LLM-setup-for-Cursor-IDE/releases/tag/v1.0.0
