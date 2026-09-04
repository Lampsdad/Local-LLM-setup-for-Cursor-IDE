# Contributing

Thanks for looking. This repo has a deliberately narrow goal: run
**Qwen3.8-27B well** on a single consumer GPU and serve it to Cursor. It
is not trying to become a general model launcher — Ollama and LM Studio
already do that. Contributions that make *this* model faster, or that make
the setup work on hardware it currently fails on, are the ones that fit.

## The most useful thing you can send

**A hardware report.** The context-window table in the README is
*computed* from the sizing formula in [`NOTES.md`](NOTES.md), and only the
RTX 5090 row has been validated by hand. If you ran this on a 3090, a
4090, a 7900 XTX or an Apple Silicon machine, open a
[hardware report](../../issues/new?template=hardware_report.yml) with the
window that actually loaded. That is how the table stops being an
estimate.

## Ground rules for tuned values

Several constants here are load-bearing and were derived from the
architecture rather than guessed:

- the `0.85` allocation-slack factor and `34,816` bytes/token in
  `probe_hardware.ps1`
- `q8_0` KV cache precision (**not** `q4_0` — see the recurrent-layer note
  in the README)
- `--parallel 1`, and the 4096/1024 batch sizes

If you change one, say what you measured. `benchmark_qwen3.8.*` and
`measure_quant_quality.*` exist so that these can be checked rather than
argued about. A PR that changes a number with a reason beats one that
changes it with a preference.

## Shell and batch conventions

Both script families are maintained in parallel — a change to
`start_linux.sh` usually needs the matching change in
`start_qwen3.8_27b.bat`.

- **Line endings are enforced by CI.** `.sh` must be LF, `.bat` and `.ps1`
  must be CRLF. `.gitattributes` pins this regardless of your
  `core.autocrlf`; do not fight it.
- **cmd.exe has traps** that have already bitten this repo — unescaped
  parentheses inside `( )` blocks, `::` comments in blocks, `for /f`
  splitting on commas, `timeout /t` failing under redirected stdin. They
  are all written up in [`NOTES.md`](NOTES.md). Read that section before
  editing a `.bat`.
- Shell scripts must pass `bash -n` and
  `shellcheck --severity=error`.
- Call sibling scripts as `call "%~dp0foo.bat"`, never bare `call foo.bat`.

## Adding a model variant

`lib_variants.bat` / `lib_variants.sh` are the only files that know what a
build *is*. Everything else reads repo, filename prefix and Cursor alias
out of them and is otherwise variant-blind. A third variant should be a
branch there and nowhere else.

## What never gets committed

Weights, `llama-bin/`, logs, and `api_key.txt`. `.gitignore` covers them
and CI fails if any get tracked anyway.

## Running the checks locally

```bash
bash -n *.sh
shellcheck --severity=error *.sh
```

Open an issue before a large change so you do not build something that
does not fit the scope above.
