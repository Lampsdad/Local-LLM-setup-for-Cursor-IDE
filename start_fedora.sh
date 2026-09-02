#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# VARIANT=base (stock) or VARIANT=ablit (abliterated).
# Both share the MTP head and the vision projector below.
. ./lib_variants.sh

QUANT="${QUANT:-UD-Q5_K_XL}"
MODEL="./models/${V_PREFIX}-${QUANT}.gguf"
MMPROJ="./models/mmproj-F16.gguf"
MTP="./models/mtp-Qwen3.8-27B-Q8_0.gguf"
BINARY="./llama-bin/llama-server"
PORT=8080
LOG="./server.log"
CF_LOG="./cloudflared.log"

# ── pre-flight checks ────────────────────────────────────────
if [ ! -f "$BINARY" ]; then
    echo "ERROR: $BINARY not found. Run ./install_fedora.sh first."
    exit 1
fi
if [ ! -f "$MODEL" ]; then
    echo "ERROR: $MODEL not found. Run VARIANT=${V_ID} ./download_model.sh first."
    exit 1
fi

# ── API key (the tunnel URL is public — see lib_api_key.sh) ──
. ./lib_api_key.sh

# ── stop any running instances ───────────────────────────────
echo "Stopping any existing instances..."
pkill -x llama-server 2>/dev/null || true
pkill -x cloudflared  2>/dev/null || true
sleep 1

# ── start llama-server ───────────────────────────────────────
EXTRA=()
if [ -f "$MTP" ] && "$BINARY" --help 2>&1 | grep -q 'draft-mtp'; then
    EXTRA+=(--spec-type draft-mtp --spec-draft-model "$MTP" \
            --spec-draft-ngl 99 --spec-draft-n-max 3)
    echo "MTP speculative decoding: enabled"
fi
[ -f "$MMPROJ" ] && EXTRA+=(--mmproj "$MMPROJ")

echo "Starting llama-server..."
"$BINARY" \
    --model        "$MODEL" \
    --fit          on \
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
echo "Waiting for server to load (1-2 min for a 30 GB model)..."
until curl -sf -H "Authorization: Bearer $API_KEY" \
        "http://localhost:$PORT/health" >/dev/null 2>&1; do
    sleep 5
    # abort if server process died
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
