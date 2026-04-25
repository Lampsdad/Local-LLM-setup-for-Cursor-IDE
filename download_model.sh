#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

REPO="bartowski/Qwen_Qwen3.6-35B-A3B-GGUF"
FILE="Qwen_Qwen3.6-35B-A3B-Q6_K_L.gguf"
DEST="models/$FILE"

echo "============================================================"
echo " Download model: Qwen_Qwen3.6-35B-A3B-Q6_K_L (~30 GB)"
echo "============================================================"
echo

if [ -f "$DEST" ]; then
    echo "[OK] Model already present at $DEST"
    exit 0
fi

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found. Install Python 3.8+ first."
    exit 1
fi

echo "[*] Installing huggingface_hub..."
python3 -m pip install -q "huggingface_hub>=0.22"

echo "[*] Downloading $FILE from $REPO..."
echo "    This is ~30 GB. Grab a coffee."
echo

python3 - <<EOF
from huggingface_hub import hf_hub_download
import os

path = hf_hub_download(
    repo_id="$REPO",
    filename="$FILE",
    local_dir="models",
)
print(f"Done: {path} ({os.path.getsize(path)/1e9:.1f} GB)")
EOF

echo
echo "Run ./start_linux.sh to launch the server."
