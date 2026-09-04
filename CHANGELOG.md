# Changelog

Notable changes to the scripts. Dates are the commit dates on `main`.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
