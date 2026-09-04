## What this changes

<!-- One or two sentences. -->

## Why

<!-- If it changes a tuned value (context formula, KV precision, batch
     sizes, sampling), say what you measured. NOTES.md explains which
     constants are load-bearing and why. -->

## Tested on

- **Platform:** <!-- Windows 11 / Ubuntu 24.04 / macOS 15 -->
- **GPU:** <!-- RTX 4090, 24 GB -->
- **llama.cpp build:** <!-- b9431 -->
- **Variant and quant:** <!-- stock, UD-Q5_K_XL -->

## Checklist

- [ ] Shell scripts still pass `bash -n` and ShellCheck
- [ ] `.sh` files are LF; `.bat` and `.ps1` are CRLF (CI enforces this)
- [ ] No weights, binaries, logs or `api_key.txt` added
- [ ] Changes touching cmd.exe follow the traps listed in `NOTES.md`
- [ ] README updated if a script, flag or default changed
