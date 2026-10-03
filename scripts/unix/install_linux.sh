#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../.."

echo "============================================================"
echo " Local Model Runtime - Linux Install (Vulkan)"
echo "============================================================"
echo

# ── CUDA check ───────────────────────────────────────────────
if ! command -v nvidia-smi &>/dev/null; then
    echo "WARNING: nvidia-smi not found. The Vulkan build can still use an NVIDIA driver."
    echo "         Without one, this install falls through to the CPU build."
else
    echo "[OK] NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
fi

# ── llama-bin ────────────────────────────────────────────────
# Vulkan, not the CUDA tarball. This script is the WSL path, and the
# Ubuntu CUDA build is the wrong package there. The tag lookup is
# shared with Fedora: /releases/latest no longer ships binaries.
# shellcheck source=lib_llama_bin.sh
. "$SCRIPT_DIR/lib_llama_bin.sh"
kiln_install_llama_bin vulkan

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

# ── kiln on PATH ─────────────────────────────────────────────
# Symlink, not a copy: kiln.sh walks the link back to this checkout,
# so `kiln` works from any directory. ~/.local/bin, no sudo.
mkdir -p "${HOME}/.local/bin"
ln -sfn "$(pwd -P)/kiln.sh" "${HOME}/.local/bin/kiln"
echo "[OK] kiln command: ~/.local/bin/kiln"

echo
echo "============================================================"
echo " Setup complete! Next steps:"
echo "   1. ./kiln.sh get     -- downloads the ~30 GB model"
echo "   2. ./kiln.sh start   -- launches server + tunnel"
echo "============================================================"
