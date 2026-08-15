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

`start_qwen3.8_27b.bat` no longer hardcodes any of this — it reads VRAM
and physical core count via `probe_hardware.ps1` at launch. The numbers
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

## Disk

This machine runs a single ~1.86 TB volume, so it fills up. Two things
worth knowing:

- `~/.cache/huggingface` holds ~180 GB from *other* research projects.
  `cleanup_disk.bat` deliberately does not touch it.
- The KL-divergence reference logits (`models/kld-base-qwen3.8.dat`)
  produced by `measure_quant_quality` are large. Delete them once you
  have settled on a quant.

## Slurm

`slurm-llama.sh` hardcodes `${HOME}/research/Local-LLM-setup-for-cursor`
as its working directory and requests `--gres=gpu:rtx5090:1` on the
`debug` partition. Both are site-specific; edit them for your cluster.

Do not start it while a manual `llama-server` is already running — they
will double-book the GPU.

## Superseded

Qwen3.6-35B-A3B was the previous default. It was replaced by Qwen3.8-27B
in August 2026: better coding scores, native MTP, and a hybrid-attention
stack that makes long context far cheaper. The Qwen3.6 scripts have been
removed; `cleanup_disk` will offer to delete the old weights.
