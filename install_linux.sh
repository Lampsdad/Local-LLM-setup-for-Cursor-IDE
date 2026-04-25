#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "============================================================"
echo " Local Model Runtime - Linux Install (NVIDIA CUDA)"
echo "============================================================"
echo

# ── CUDA check ───────────────────────────────────────────────
if ! command -v nvidia-smi &>/dev/null; then
    echo "WARNING: nvidia-smi not found. Install the NVIDIA driver and CUDA toolkit first."
    echo "         Continuing, but the server will run on CPU only."
else
    echo "[OK] NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
fi

# ── llama-bin ────────────────────────────────────────────────
if [ -f "llama-bin/llama-server" ]; then
    echo "[OK] llama-bin/ already populated, skipping download."
else
    echo "[*] Fetching latest llama.cpp release from GitHub..."
    mkdir -p llama-bin

    ASSET_URL=$(curl -fsSL https://api.github.com/repos/ggml-org/llama.cpp/releases/latest \
        | python3 -c "
import sys, json
rel = json.load(sys.stdin)
assets = rel['assets']
# prefer CUDA Ubuntu x64 build; fall back to plain Ubuntu x64
for pat in ['ubuntu.*cuda.*x64', 'linux.*cuda.*x64', 'ubuntu.*x64']:
    import re
    for a in assets:
        if re.search(pat, a['name'], re.IGNORECASE) and a['name'].endswith('.zip'):
            print(a['browser_download_url']); sys.exit(0)
print('NOT_FOUND'); sys.exit(1)
")

    if [ "$ASSET_URL" = "NOT_FOUND" ]; then
        echo "ERROR: Could not find a Linux x64 asset in the latest release."
        echo "Download manually from: https://github.com/ggml-org/llama.cpp/releases/latest"
        echo "Extract into llama-bin/"
        exit 1
    fi

    FILENAME=$(basename "$ASSET_URL")
    echo "Downloading $FILENAME..."
    curl -fL "$ASSET_URL" -o "llama-bin/$FILENAME"
    unzip -q "llama-bin/$FILENAME" -d llama-bin
    rm "llama-bin/$FILENAME"
    chmod +x llama-bin/llama-server llama-bin/llama-cli 2>/dev/null || true
    echo "[OK] llama.cpp binaries extracted."
fi

# ── cloudflared ──────────────────────────────────────────────
if command -v cloudflared &>/dev/null; then
    echo "[OK] cloudflared already installed."
else
    echo "[*] Installing cloudflared..."
    CF_BIN="/usr/local/bin/cloudflared"
    if [ -w "$(dirname "$CF_BIN")" ]; then
        curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
            -o "$CF_BIN"
        chmod +x "$CF_BIN"
        echo "[OK] cloudflared installed to $CF_BIN"
    else
        echo "[*] Need sudo to install to /usr/local/bin..."
        sudo curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
            -o "$CF_BIN"
        sudo chmod +x "$CF_BIN"
        echo "[OK] cloudflared installed to $CF_BIN"
    fi
fi

# ── models dir ───────────────────────────────────────────────
mkdir -p models
echo "[OK] models/ directory ready."

echo
echo "============================================================"
echo " Setup complete! Next steps:"
echo "   1. bash download_model.sh   -- downloads the ~30 GB model"
echo "   2. bash start_linux.sh      -- launches server + tunnel"
echo "============================================================"
