# shellcheck shell=bash
# ============================================================
#  Resolve what to load and how big to size it.
#
#  Sourced by start_linux.sh / start_mac.sh / start_fedora.sh
#  AFTER lib_variants.sh, which supplies V_PREFIX / V_QUANTS /
#  V_MTP / V_VISION.
#
#  Sets:
#    MODEL      path to the weights that will be loaded
#    MTP        path to the MTP head, or empty
#    MMPROJ     path to the vision projector, or empty
#    FIT_ARGS   array: either (--ctx-size N) or (--fit on)
#    CTX        the context that was computed, or 0
#
#  Why this exists: the three start scripts each carried their own
#  copy of this preamble, hardcoded to UD-Q5_K_XL and one MTP
#  filename. Three copies meant three places to forget when a quant
#  was added, and all three assumed the 32 GB card this repo was
#  tuned on.
#
#  On --fit vs an explicit --ctx-size: llama.cpp's --fit on sizes
#  the window against free VRAM at load time and does it well. It
#  is kept as the fallback, and it is still what runs when Python
#  or nvidia-smi is unavailable. But it cannot know that this repo
#  wants ONE slot at a large window rather than a merely safe one,
#  and on Apple Silicon it sees the whole unified pool rather than
#  what Metal will actually hand a single process. Where
#  hardware.py can compute a number, that number is used.
# ============================================================

_sel_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_sel_root="$(cd "$_sel_dir/../.." && pwd)"
# KILN_PY, not `command -v python3` -- see lib_python.sh for why.
. "$_sel_dir/lib_python.sh"
_sel_py="$KILN_PY"
_sel_hw="$_sel_root/scripts/hardware.py"

MODEL=""
MTP=""
MMPROJ=""
CTX=0
FIT_ARGS=()

# ── weights ─────────────────────────────────────────────────
# An explicit QUANT wins. Otherwise take the best one present, in
# registry order -- V_QUANTS is ordered best quality first, so the
# first hit is the one you would have chosen by hand.
if [ -n "${QUANT:-}" ]; then
    MODEL="./models/${V_PREFIX}-${QUANT}.gguf"
else
    for _q in ${V_QUANTS}; do
        if [ -f "./models/${V_PREFIX}-${_q}.gguf" ]; then
            MODEL="./models/${V_PREFIX}-${_q}.gguf"
            QUANT="$_q"
            break
        fi
    done
    # Nothing on disk: name the historical default so the
    # "not found" message below points somewhere real.
    if [ -z "$MODEL" ]; then
        case "$V_ID" in
            9b|4b) QUANT="Q5_K_M" ;;
            *)     QUANT="UD-Q5_K_XL" ;;
        esac
        MODEL="./models/${V_PREFIX}-${QUANT}.gguf"
    fi
fi

# ── MTP head and vision projector ───────────────────────────
# 27B families only, and each comes in two precisions. Better
# first; kiln get downloads whichever the card had room for.
#
# These are plain ifs rather than `[ -f x ] && VAR=y`: under
# set -e a failing test makes the list non-zero and aborts the
# script, which is how a missing mmproj used to kill start_mac.sh
# before it printed anything.
if [ "${V_MTP:-0}" = "1" ]; then
    if [ -f "./models/mtp-Qwen3.8-27B-Q8_0.gguf" ]; then
        MTP="./models/mtp-Qwen3.8-27B-Q8_0.gguf"
    elif [ -f "./models/mtp-Qwen3.8-27B-Q4_0.gguf" ]; then
        MTP="./models/mtp-Qwen3.8-27B-Q4_0.gguf"
    fi
fi
if [ "${V_VISION:-0}" = "1" ]; then
    if [ -f "./models/mmproj-F16.gguf" ]; then
        MMPROJ="./models/mmproj-F16.gguf"
    elif [ -f "./models/mmproj-Qwen3.8-27B-Q8_0.gguf" ]; then
        MMPROJ="./models/mmproj-Qwen3.8-27B-Q8_0.gguf"
    fi
fi

# ── context ─────────────────────────────────────────────────
REC_SAME=1
REC_FAMILY=""
REC_QUANT=""
REC_CTX=0
TIER_LABEL=""

if [ -n "$_sel_py" ] && [ -f "$_sel_hw" ] && [ -f "$MODEL" ]; then
    while IFS='=' read -r _k _v; do
        case "$_k" in
            CTX)        CTX="$_v" ;;
            TIER_LABEL) TIER_LABEL="$_v" ;;
            REC_SAME)   REC_SAME="$_v" ;;
            REC_FAMILY) REC_FAMILY="$_v" ;;
            REC_QUANT)  REC_QUANT="$_v" ;;
            REC_CTX)    REC_CTX="$_v" ;;
        esac
    done < <("$_sel_py" "$_sel_hw" --size-model "$MODEL" \
                 --mtp "$MTP" --mmproj "$MMPROJ" 2>/dev/null \
                 | kiln_strip_cr || true)
fi

if [ "${CTX:-0}" -gt 0 ] 2>/dev/null; then
    FIT_ARGS=(--ctx-size "$CTX")
else
    # No GPU information, or no Python. llama.cpp sizes it itself.
    CTX=0
    FIT_ARGS=(--fit on)
fi

# ── say what was chosen, and what would have been ───────────
echo "  weights : $MODEL"
if [ -n "$TIER_LABEL" ]; then
    echo "  hardware: $TIER_LABEL"
fi
if [ "$CTX" -gt 0 ]; then
    echo "  context : $CTX  ($((CTX / 1024))K)"
else
    echo "  context : sized by llama.cpp (--fit on)"
fi
if [ -n "$MTP" ]; then
    echo "  MTP     : $(basename "$MTP")"
else
    echo "  MTP     : none"
fi
if [ -n "$MMPROJ" ]; then
    echo "  vision  : $(basename "$MMPROJ")"
fi

# What is on disk always wins -- re-picking behind the user's back
# would be worse than knowingly running the wrong file. Just say so.
if [ "$REC_SAME" = "0" ] && [ -n "$REC_QUANT" ]; then
    echo
    echo "  [note] on this GPU kiln would pick ${REC_FAMILY} ${REC_QUANT}"
    echo "         at $((REC_CTX / 1024))K context:  ./kiln.sh get ${REC_FAMILY}"
fi
echo

unset _sel_dir _sel_root _sel_py _sel_hw _q _k _v
