# Local Model Launcher

Runs large GGUF models locally via llama.cpp and exposes them through a Cloudflare quick tunnel as an OpenAI-compatible API for running local models with Cursor.

**Current default model:** `Qwen_Qwen3.6-35B-A3B-Q6_K_L` (~30 GB, Q6_K_L quantization)

---

## Quick Start

### Windows

```bat
install_windows.bat    :: one-time setup
download_model.bat     :: download the default model (~30 GB)
start_windows.bat      :: start server + tunnel
```

### macOS

```bash
bash install_mac.sh      # one-time setup
bash download_model.sh   # download the default model (~30 GB)
bash start_mac.sh        # start server + tunnel
```

### Linux

```bash
bash install_linux.sh    # one-time setup
bash download_model.sh   # download the default model (~30 GB)
bash start_linux.sh      # start server + tunnel
```

---

## Scripts

### `install_windows.bat` / `install_mac.sh` / `install_linux.sh`

One-time setup. Does **not** download models.

| Step | What it does |
|---|---|
| llama-bin check | If `llama-bin/llama-server` is missing, downloads the latest llama.cpp release from GitHub and extracts it |
| cloudflared check | If cloudflared is missing, downloads it from the Cloudflare GitHub release (macOS prefers Homebrew if available) |
| models/ | Creates the `models/` directory if absent |

Run this once on a fresh machine. Re-running is safe — each step is skipped if already done.

**macOS note:** The install script auto-detects Apple Silicon (`arm64`) vs Intel (`x86_64`) and downloads the matching binary. The macOS build uses Metal for GPU acceleration — no CUDA needed.

---

### `download_model.bat` / `download_model.sh`

Downloads the default model from Hugging Face into `models/`. Requires Python 3.8+.

- Installs `huggingface_hub` via pip if needed
- Skips the download if the file already exists
- Shows progress and final file size

---

### `start_windows.bat` / `start_mac.sh` / `start_linux.sh`

Launches the server and exposes it via Cloudflare tunnel. Run this every time you want to use the model.

| Step | What it does |
|---|---|
| Kill old processes | Stops any running `llama-server` / `cloudflared` |
| Start server | Launches `llama-server` on `localhost:8080` with 128K context, KV cache quantized to Q4_0, all layers on GPU |
| Health poll | Waits until the server responds at `/health` (takes 1–2 min to load; 2–4 min on Apple Silicon) |
| Cloudflare tunnel | Starts a quick tunnel (no account needed) pointing to `localhost:8080` |
| Print URL | Prints the public `trycloudflare.com` URL |

Once running, set your client's **OpenAI base URL** to the printed URL + `/v1`, e.g.:

```
https://example-words-here.trycloudflare.com/v1
```

On macOS and Linux, press **Ctrl+C** to stop both the server and tunnel cleanly.

---

## Using with Cursor

### One-time setup

**1. Open Cursor Settings**

`Ctrl+Shift+J` (Windows/Linux) or `Cmd+Shift+J` (macOS), then navigate to the **Models** tab.

**2. Enter a dummy API key**

Cursor requires a non-empty OpenAI API key even when talking to a local server. Scroll to the **OpenAI API Key** field and enter any placeholder value (e.g. `local`). The local server ignores it entirely.

**3. Set the base URL**

Check the **Override OpenAI Base URL** box and paste the URL printed by the start script, with `/v1` appended:

```
https://example-words-here.trycloudflare.com/v1
```

**4. Disable built-in models**

Scroll through the model list and uncheck all OpenAI (and other provider) models you don't want to accidentally use or pay for.

**5. Add your model**

In the **Add Model** field at the bottom of the model list, type the model alias exactly as it appears in the start script and press Enter:

```
qwen3.6-35b-a3b
```

Click **Verify** — Cursor will call `/v1/models` on your server to confirm the connection. It should show a green checkmark.

### Starting a session

1. Run the start script and wait for the tunnel URL to print
2. Update the base URL in Cursor Settings → Models (see step 3 above) — **the URL changes every restart**
3. Open a new chat (`Ctrl+L` / `Cmd+L`), click the model name in the bottom-left of the chat panel, and select `qwen3.6-35b-a3b`

> The URL rotates because these are Cloudflare *quick* tunnels — no account required, but no persistent URL. If updating it every session becomes annoying, see the [named tunnel option](#security) in the Security section.

### Cursor features that work with local models

| Feature | Works? | Notes |
|---|---|---|
| Chat (`Ctrl+L`) | Yes | Full conversation with the model |
| Inline edit (`Ctrl+K`) | Yes | Applies edits directly in the editor |
| Composer | Yes | Multi-file edits |
| Tab autocomplete | No | Requires a Cursor-hosted model; cannot be routed to a custom endpoint |
| `@Codebase` context | Yes | Cursor handles the indexing; model just sees the retrieved chunks |

---

## Downloading a Different Model

Any GGUF file can be used. The steps are:

**1. Find a model on Hugging Face**

Good sources:
- [bartowski](https://huggingface.co/bartowski) — wide selection of Q4–Q8 GGUF quants
- [unsloth](https://huggingface.co/unsloth) — efficient quants including newer formats
- [TheBloke](https://huggingface.co/TheBloke) — large archive of older models

Pick a quantization that fits your GPU memory (VRAM on Windows/Linux; unified memory on Apple Silicon):
| Quant | Quality | Memory (35B model) |
|---|---|---|
| Q8_0 | near-lossless | ~37 GB |
| Q6_K_L | excellent | ~30 GB |
| Q5_K_M | very good | ~24 GB |
| Q4_K_M | good | ~20 GB |

On Apple Silicon Macs, model weights and GPU compute share the same unified memory pool, so make sure your Mac has enough total RAM (e.g. a 30 GB model needs at least a 36 GB Mac to leave headroom for the OS).

**2. Download the file**

Using `huggingface-cli` (recommended):

```bash
pip install huggingface_hub
huggingface-cli download <repo-id> <filename> --local-dir models/
```

Example:

```bash
huggingface-cli download bartowski/Llama-3.3-70B-Instruct-GGUF \
    Llama-3.3-70B-Instruct-Q4_K_M.gguf \
    --local-dir models/
```

Or with direct curl if you have the URL:

```bash
curl -L -o models/mymodel.gguf "https://huggingface.co/..."
```

**3. Update the start script**

Open the start script for your platform and change the `MODEL=` line at the top:

```bat
:: start_windows.bat
set MODEL=models\your-new-model.gguf
```

```bash
# start_mac.sh / start_linux.sh
MODEL="./models/your-new-model.gguf"
```

You may also want to update `--alias` to a meaningful name for your API client.

**4. Adjust GPU layers if needed**

`--n-gpu-layers 99` offloads all layers to GPU. If the model is too large for your VRAM, lower this value (e.g. `40`) to spill the remainder to system RAM (slower but it works).

---

## Server Parameters

The start scripts use these settings by default:

| Flag | Value | Notes |
|---|---|---|
| `--n-gpu-layers` | 99 | All layers on GPU; lower if VRAM OOM |
| `--ctx-size` | 131072 | 128K context window |
| `--flash-attn` | auto | Enables Flash Attention when supported |
| `--cache-type-k/v` | q4_0 | KV cache quantization — reduces VRAM for long contexts |
| `--port` | 8080 | Local port; Cloudflare forwards this externally |
| `--host` | 0.0.0.0 | Listens on all interfaces |

---

## Security

The Cloudflare quick tunnel URL is **public and unauthenticated** — anyone who has the URL can send requests to your model. The URL changes every time you restart, so in practice access is limited to people you share it with during a session.

If you need persistent, access-controlled sharing, consider setting up a [named Cloudflare tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) with an Access policy instead of the quick tunnel used here.

---

## Requirements

### Windows
- Windows 10/11
- NVIDIA GPU with CUDA 12+ driver
- Python 3.8+ (for model downloads)

### macOS
- macOS 12 Monterey or later
- Apple Silicon (M1/M2/M3/M4) or Intel — Metal GPU acceleration is built into the macOS llama.cpp build
- Enough unified memory (Apple Silicon) or VRAM (Intel) to hold the model
- `curl`, `unzip`, Python 3.8+
- Homebrew optional but recommended (used to install cloudflared if present)

### Linux
- Ubuntu 20.04+ (or equivalent)
- NVIDIA GPU with CUDA 12+ driver and `nvidia-smi` accessible
- `curl`, `unzip`, Python 3.8+
