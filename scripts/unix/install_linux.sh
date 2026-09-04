#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

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
import re, sys, json
rel = json.load(sys.stdin)
assets = rel.get('assets', [])
# New releases ship .tar.gz (not .zip). Prefer Vulkan on NVIDIA Linux when no CUDA tarball.
patterns = [
    (r'bin-ubuntu-vulkan-x64\.tar\.gz$', 'vulkan'),
    (r'bin-ubuntu-x64\.tar\.gz$', 'cpu'),
]
for pat, _ in patterns:
    for a in assets:
        name = a.get('name', '')
        if re.search(pat, name, re.IGNORECASE):
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
    tar -xzf "llama-bin/$FILENAME" -C llama-bin
    rm "llama-bin/$FILENAME"
    # Flatten: releases unpack to llama-<tag>/ with binaries inside
    SUBDIR=$(find llama-bin -maxdepth 1 -type d -name 'llama-*' | head -1)
    if [ -n "$SUBDIR" ] && [ -f "$SUBDIR/llama-server" ]; then
        ln -sf "$(basename "$SUBDIR")/llama-server" llama-bin/llama-server
        ln -sf "$(basename "$SUBDIR")/llama-cli" llama-bin/llama-cli
    fi
    chmod +x llama-bin/llama-server llama-bin/llama-cli 2>/dev/null || true
    find llama-bin -name 'llama-server' -type f -exec chmod +x {} \;
    echo "[OK] llama.cpp binaries extracted."
fi

# ── cloudflared ──────────────────────────────────────────────
if command -v cloudflared &>/dev/null; then
    echo "[OK] cloudflared already installed."
else
    echo "[*] Installing cloudflared..."
    CF_BIN="${HOME}/.local/bin/cloudflared"
    mkdir -p "$(dirname "$CF_BIN")"
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
        -o "$CF_BIN"
    chmod +x "$CF_BIN"
    echo "[OK] cloudflared installed to $CF_BIN (ensure ~/.local/bin is on PATH)"
fi

# ── models dir ───────────────────────────────────────────────
mkdir -p models
echo "[OK] models/ directory ready."

echo
echo "============================================================"
echo " Setup complete! Next steps:"
echo "   1. ./kiln.sh get     -- downloads the ~30 GB model"
echo "   2. ./kiln.sh start   -- launches server + tunnel"
echo "============================================================"
