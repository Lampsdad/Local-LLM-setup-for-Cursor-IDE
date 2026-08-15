#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# ============================================================
#  Download Qwen3.8-27B (released 2026-08-05).
#
#  Three files make a full install:
#    weights  -- unsloth/Qwen3.8-27B-GGUF   (UD dynamic quants)
#    MTP head -- ggml-org/Qwen3.8-27B-GGUF  (speculative decoding)
#    mmproj   -- unsloth/Qwen3.8-27B-GGUF   (vision encoder)
#
#  Override the quant with QUANT=..., e.g.
#    QUANT=UD-Q4_K_XL ./download_model.sh
# ============================================================

BASE_REPO="unsloth/Qwen3.8-27B-GGUF"
MTP_REPO="ggml-org/Qwen3.8-27B-GGUF"

QUANT="${QUANT:-UD-Q5_K_XL}"
FILE="Qwen3.8-27B-${QUANT}.gguf"
MMPROJ="mmproj-F16.gguf"
MTP="mtp-Qwen3.8-27B-Q8_0.gguf"

echo "============================================================"
echo " Download: Qwen3.8-27B (${QUANT})"
echo "============================================================"
echo

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found. Install Python 3.8+ first."
    exit 1
fi

echo "[*] Installing huggingface_hub..."
python3 -m pip install -q "huggingface_hub>=0.22" hf_transfer

# hf_transfer materially speeds up multi-GB downloads on fast links.
export HF_HUB_ENABLE_HF_TRANSFER=1

mkdir -p models

fetch() {
    local repo="$1" name="$2"
    if [ -f "models/$name" ]; then
        echo "[OK] already present: $name"
        return 0
    fi
    echo "[*] Downloading $name from $repo ..."
    python3 - "$repo" "$name" <<'EOF'
import os, sys
from huggingface_hub import hf_hub_download
repo, name = sys.argv[1], sys.argv[2]
path = hf_hub_download(repo_id=repo, filename=name, local_dir="models")
print(f"    saved: {path} ({os.path.getsize(path)/1e9:.1f} GB)")
EOF
}

fetch "$BASE_REPO" "$FILE"
fetch "$BASE_REPO" "$MMPROJ"
fetch "$MTP_REPO"  "$MTP"

echo
echo "Done. Launch with ./start_linux.sh (or start_mac.sh / start_fedora.sh)."
