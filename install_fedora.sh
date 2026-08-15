#!/usr/bin/env bash
# install_fedora.sh — installs llama.cpp (Vulkan prebuilt) + cloudflared on Fedora
#
# One-time Vulkan setup (if not already done):
#   sudo dnf install vulkan-tools mesa-vulkan-drivers
#   NVIDIA users: the proprietary driver already exposes Vulkan; the mesa package
#   adds the open-source loader and is optional but recommended for diagnostics.
set -euo pipefail
cd "$(dirname "$0")"

echo "============================================================"
echo " Local Model Runtime - Fedora Install (Vulkan)"
echo "============================================================"
echo

# ── GPU / Vulkan check ────────────────────────────────────────
if ! command -v nvidia-smi &>/dev/null; then
    echo "WARNING: nvidia-smi not found. Install the NVIDIA driver first."
    echo "         Continuing, but the server will run on CPU only."
else
    echo "[OK] NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
fi

if command -v vulkaninfo &>/dev/null; then
    VULKAN_DEV=$(vulkaninfo --summary 2>/dev/null | grep "deviceName" | head -1 | sed 's/.*= //' || true)
    echo "[OK] Vulkan available${VULKAN_DEV:+: $VULKAN_DEV}"
else
    echo "INFO: vulkaninfo not found — run: sudo dnf install vulkan-tools"
fi

# ── llama-bin ────────────────────────────────────────────────
if [ -f "llama-bin/llama-server" ]; then
    echo "[OK] llama-bin/ already populated, skipping download."
else
    echo "[*] Fetching latest llama.cpp release from GitHub..."
    mkdir -p llama-bin

    ASSET_URL=$(curl -fsSL https://api.github.com/repos/ggml-org/llama.cpp/releases/latest \
        | python3 -c "
import sys, json, re
rel = json.load(sys.stdin)
assets = rel['assets']
# Prefer Vulkan Ubuntu x64; fall back to generic Ubuntu x64
for pat in ['ubuntu.*vulkan.*x64', 'vulkan.*x64', 'ubuntu.*x64']:
    for a in assets:
        if re.search(pat, a['name'], re.IGNORECASE) and \
           (a['name'].endswith('.tar.gz') or a['name'].endswith('.zip')):
            print(a['browser_download_url']); sys.exit(0)
print('NOT_FOUND'); sys.exit(1)
")

    if [ "$ASSET_URL" = "NOT_FOUND" ]; then
        echo "ERROR: Could not find a Linux x64 Vulkan asset in the latest release."
        echo "Download manually from: https://github.com/ggml-org/llama.cpp/releases/latest"
        echo "Extract into llama-bin/"
        exit 1
    fi

    FILENAME=$(basename "$ASSET_URL")
    ARCHIVE="llama-bin/$FILENAME"
    echo "Downloading $FILENAME..."
    curl -fL "$ASSET_URL" -o "$ARCHIVE"

    # Extract — handle both .tar.gz (current default) and .zip
    if [[ "$FILENAME" == *.tar.gz ]]; then
        tar -xzf "$ARCHIVE" -C llama-bin
    else
        unzip -q "$ARCHIVE" -d llama-bin
    fi
    rm "$ARCHIVE"

    # Some releases extract into a subdirectory; flatten one level if needed
    if [ ! -f "llama-bin/llama-server" ]; then
        FOUND=$(find llama-bin -maxdepth 3 -name "llama-server" -type f | head -1)
        if [ -n "$FOUND" ]; then
            SUBDIR=$(dirname "$FOUND")
            mv "$SUBDIR"/* llama-bin/
            find llama-bin -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
        else
            echo "ERROR: llama-server not found after extraction. Check llama-bin/ manually."
            exit 1
        fi
    fi

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
echo "   1. bash download_model.sh    -- downloads the ~30 GB model"
echo "   2. bash start_fedora.sh      -- launches server + tunnel"
echo "============================================================"
