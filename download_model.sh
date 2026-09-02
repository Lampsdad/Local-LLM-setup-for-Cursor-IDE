#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# ============================================================
#  Download Qwen3.8-27B (released 2026-08-05).
#
#  Three files make a full install:
#    weights  -- per variant, see lib_variants.sh
#    MTP head -- ggml-org/Qwen3.8-27B-GGUF  (speculative decoding)
#    mmproj   -- unsloth/Qwen3.8-27B-GGUF   (vision encoder)
#
#  The MTP head and the vision projector are shared by both
#  variants and fetched once: huihui-ai ablates the language
#  layers of unsloth's own UD quants and leaves those two
#  untouched.
#
#  Override with QUANT=... and VARIANT=..., e.g.
#    QUANT=UD-Q4_K_XL ./download_model.sh
#    VARIANT=ablit ./download_model.sh
# ============================================================

. ./lib_variants.sh

BASE_REPO="$V_REPO"
MTP_REPO="ggml-org/Qwen3.8-27B-GGUF"
VISION_REPO="unsloth/Qwen3.8-27B-GGUF"

QUANT="${QUANT:-UD-Q5_K_XL}"
FILE="${V_PREFIX}-${QUANT}.gguf"
MMPROJ="mmproj-F16.gguf"
MTP="mtp-Qwen3.8-27B-Q8_0.gguf"

echo "============================================================"
echo " Download: ${V_LABEL} (${QUANT})"
echo " Source: ${BASE_REPO}"
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
fetch "$VISION_REPO" "$MMPROJ"
fetch "$MTP_REPO"  "$MTP"

echo
echo "Done. Launch with VARIANT=${V_ID} ./start_linux.sh (or start_mac.sh / start_fedora.sh)."
