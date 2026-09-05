#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../.."

# VARIANT=base (stock) or VARIANT=ablit (abliterated).
# Both share the MTP head and the vision projector below.
# With no VARIANT set, resolve it from what is on disk -- see the
# KILN_PICK block in lib_variants.sh.
KILN_PICK=disk . "$SCRIPT_DIR/lib_variants.sh"

# Resolves MODEL / MTP / MMPROJ / FIT_ARGS against the weights
# actually on disk and the GPU actually present. QUANT= still
# overrides the choice of file.
echo "  build   : ${V_LABEL}"
. "$SCRIPT_DIR/lib_select.sh"
BINARY="./llama-bin/llama-server"
PORT=8080
LOG="./server.log"
CF_LOG="./cloudflared.log"

# ── pre-flight checks ────────────────────────────────────────
if [ ! -f "$BINARY" ]; then
    echo "ERROR: $BINARY not found. Run ./install_mac.sh first."
    exit 1
fi
if [ ! -f "$MODEL" ]; then
    echo "ERROR: $MODEL not found. Run: VARIANT=${V_ID} ./kiln.sh get"
    exit 1
fi

# ── API key (the tunnel URL is public — see lib_api_key.sh) ──
. "$SCRIPT_DIR/lib_api_key.sh"

# ── stop any running instances ───────────────────────────────
echo "Stopping any existing instances..."
pkill -x llama-server 2>/dev/null || true
pkill -x cloudflared  2>/dev/null || true
sleep 1

# ── start llama-server ───────────────────────────────────────
EXTRA=()
if [ -n "$MTP" ] && "$BINARY" --help 2>&1 | grep -q 'draft-mtp'; then
    EXTRA+=(--spec-type draft-mtp --spec-draft-model "$MTP" \
            --spec-draft-ngl 99 --spec-draft-n-max 3)
    echo "MTP speculative decoding: enabled"
fi
# Plain if: under set -e a failing `[ -f x ] && ...` aborts
# the script, which killed this before it printed anything
# whenever the vision projector was absent.
if [ -n "$MMPROJ" ]; then
    EXTRA+=(--mmproj "$MMPROJ")
fi

# FIT_ARGS carries either a computed --ctx-size or --fit on.
# On Apple Silicon the computed number budgets ~75% of unified
# memory, which is roughly what Metal's
# recommendedMaxWorkingSetSize hands a single process -- --fit
# alone sees the whole pool and can be optimistic about it.
echo "Starting llama-server (Metal)..."
"$BINARY" \
    --model        "$MODEL" \
    "${FIT_ARGS[@]}" \
    --n-gpu-layers 99 \
    --flash-attn   auto \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --parallel     1 \
    --jinja \
    --reasoning-format deepseek \
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 \
    --port         $PORT \
    --host         0.0.0.0 \
    --alias        "$V_ALIAS" \
    --api-key-file "$API_KEY_FILE" \
    "${EXTRA[@]}" \
    --log-file     "$LOG" &
SERVER_PID=$!

# ── wait for server to be ready (health poll) ────────────────
echo "Waiting for server to load (2-4 min for a 30 GB model on Apple Silicon)..."
# The key goes to curl through a config on stdin rather than -H:
# argv is world-readable in /proc, and slurm-llama.sh runs this same
# poll on a shared cluster node. printf is a shell builtin, so the
# key never reaches another process's command line.
until printf 'header = "Authorization: Bearer %s"\n' "$API_KEY" \
        | curl -sf -K - "http://localhost:$PORT/health" >/dev/null 2>&1; do
    sleep 5
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        echo "ERROR: llama-server exited unexpectedly. Check $LOG for details."
        exit 1
    fi
done
echo "Server is ready."

# ── start cloudflared tunnel ─────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
    echo "WARNING: cloudflared not found. Skipping tunnel."
    echo "The API is reachable at http://localhost:$PORT/v1"
    echo "API key: $API_KEY"
    echo "Press Ctrl+C to stop the server."
    wait $SERVER_PID
    exit 0
fi

echo "Starting Cloudflare tunnel..."
cloudflared tunnel --url "http://localhost:$PORT" >"$CF_LOG" 2>&1 &
CF_PID=$!
sleep 12

# ── print tunnel URL ─────────────────────────────────────────
echo
echo "============================================================"
grep -o 'https://[^ ]*trycloudflare\.com' "$CF_LOG" | head -1 | xargs -I{} echo " Base URL: {}/v1"
echo
echo " API key (paste into Cursor's OpenAI API Key field):"
echo "   $API_KEY"
echo
echo " The tunnel URL is public. Requests without the key are rejected."
echo "============================================================"
echo
echo "Press Ctrl+C to stop everything."

# ── keep running until interrupted ───────────────────────────
trap "echo; echo 'Shutting down...'; kill $SERVER_PID $CF_PID 2>/dev/null; exit 0" INT TERM
wait $SERVER_PID
