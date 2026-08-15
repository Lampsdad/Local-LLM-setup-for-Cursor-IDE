#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# ============================================================
#  Free disk space before downloading Qwen3.8-27B.
#
#  Qwen3.8-27B needs ~22-25 GB (weights + MTP head + vision
#  projector), so superseded GGUFs are the obvious thing to
#  reclaim.
#
#  DELETION IS PERMANENT. Every file listed can be re-downloaded
#  from Hugging Face, but that is a multi-hour round trip.
# ============================================================

# Superseded weight files, paired with why they are safe to drop.
CANDIDATES=(
    "models/Qwen_Qwen3.6-35B-A3B-Q6_K_L.gguf|previous default server model"
    "models/Qwen3.6-27B-UD-Q4_K_XL.gguf|direct predecessor being replaced"
    "models/Qwen3-Coder-Next-UD-Q3_K_M.gguf|superseded coder model"
    "models/Qwen3-Coder-Next-UD-TQ3_25bpw.gguf|superseded coder model"
)

free_gb() {
    # -k is POSIX; -BG and --output are GNU-only and absent on macOS.
    df -k . | awk 'NR==2 {printf "%.1f", $4/1048576}'
}

size_gb() {
    # stat's flags differ between GNU and BSD; try both.
    local bytes
    bytes=$(stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0)
    awk -v b="$bytes" 'BEGIN {printf "%.1f", b/1073741824}'
}

echo "============================================================"
echo " Reclaim disk space"
echo "============================================================"
echo
FREE_BEFORE=$(free_gb)
echo " Free space here: ${FREE_BEFORE} GB"
echo
echo " Candidates for deletion (superseded by Qwen3.8-27B):"
echo

FOUND=()
INDEX=0
for entry in "${CANDIDATES[@]}"; do
    path="${entry%%|*}"
    why="${entry##*|}"
    if [ -f "$path" ]; then
        INDEX=$((INDEX + 1))
        FOUND+=("$path")
        printf '    [%d] %s  --  %s GB  (%s)\n' \
            "$INDEX" "$(basename "$path")" "$(size_gb "$path")" "$why"
    fi
done

if [ "$INDEX" -eq 0 ]; then
    echo " Nothing to reclaim -- none of the listed files are present."
    exit 0
fi

if [ -f "server.log" ]; then
    echo
    echo " Also reclaimable:"
    printf '    server.log  (%s GB, runaway verbose log)\n' "$(size_gb server.log)"
fi

echo
echo "------------------------------------------------------------"
echo " Type DELETE to permanently remove the files listed above."
echo " Anything else cancels."
echo "------------------------------------------------------------"
printf '> '
read -r CONFIRM

if [ "$CONFIRM" != "DELETE" ]; then
    echo
    echo " Cancelled. Nothing was deleted."
    exit 0
fi

echo
for path in "${FOUND[@]}"; do
    if rm -f "$path" && [ ! -f "$path" ]; then
        echo " [deleted] $(basename "$path")"
    else
        echo " [FAIL] $(basename "$path") is still present -- is the server running?"
    fi
done

# Truncate the verbose log rather than deleting it, so an already-open
# file handle keeps working.
if [ -f "server.log" ]; then
    : > server.log
    echo " [truncated] server.log"
fi

echo
echo "============================================================"
echo " Free space here: $(free_gb) GB  (was ${FREE_BEFORE} GB)"
echo
echo " Next: ./download_model.sh"
echo "============================================================"
