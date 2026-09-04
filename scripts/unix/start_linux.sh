#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../.."
export PATH="${HOME}/.local/bin:${PATH}"

# VARIANT=base (stock) or VARIANT=ablit (abliterated).
# Both share the MTP head and the vision projector below.
. "$SCRIPT_DIR/lib_variants.sh"

QUANT="${QUANT:-UD-Q5_K_XL}"
MODEL="./models/${V_PREFIX}-${QUANT}.gguf"
MMPROJ="./models/mmproj-F16.gguf"
MTP="./models/mtp-Qwen3.8-27B-Q8_0.gguf"
BINARY="./llama-bin/llama-server"
PORT=8081
LOG="./server.log"
CF_LOG="./cloudflared.log"
# Distinct per variant so Cursor cannot silently show the wrong one.
ALIAS="$V_ALIAS"

# ── pre-flight checks ────────────────────────────────────────
if [ ! -f "$BINARY" ]; then
    echo "ERROR: $BINARY not found. Run ./install_linux.sh first."
    exit 1
fi
if [ ! -f "$MODEL" ]; then
    echo "ERROR: $MODEL not found. Run: VARIANT=${V_ID} ./kiln.sh get"
    exit 1
fi

# ── API key (the tunnel URL is public — see lib_api_key.sh) ──
. "$SCRIPT_DIR/lib_api_key.sh"

# ── optional features, enabled only if the pieces are present ─
# MTP speculative decoding merged into llama.cpp in b9180
# (2026-05-16). Older builds reject --spec-type draft-mtp, so
# probe for it rather than assuming.
EXTRA=()
if [ -f "$MTP" ] && "$BINARY" --help 2>&1 | grep -q 'draft-mtp'; then
    EXTRA+=(--spec-type draft-mtp
            --spec-draft-model "$MTP"
            --spec-draft-ngl 99
            --spec-draft-n-max 3)
    echo "MTP speculative decoding: enabled"
else
    echo "MTP speculative decoding: unavailable (need llama.cpp b9180+ and $MTP)"
fi
if [ -f "$MMPROJ" ]; then
    EXTRA+=(--mmproj "$MMPROJ")
    echo "Vision: enabled"
fi

# ── stop any running instances ───────────────────────────────
echo "Stopping any existing llama-server (cloudflared left running for stable URL)..."
pkill -x llama-server 2>/dev/null || true
sleep 1

# ── start llama-server ───────────────────────────────────────
echo "Starting llama-server..."
# --fit on lets llama.cpp size any argument we leave unset to the
# GPU actually present, so --ctx-size is deliberately omitted here
# (this script runs on several different machines).
# q8_0 KV, not q4_0: 48 of Qwen3.8's 64 layers are recurrent, and
# quantization error accumulates along the sequence in those rather
# than being re-anchored each token.
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
    --alias        "$ALIAS" \
    --api-key-file "$API_KEY_FILE" \
    "${EXTRA[@]}" \
    --log-file     "$LOG" &
SERVER_PID=$!

# ── wait for server to be ready (health poll) ────────────────
echo "Waiting for server to load (1-2 min for a 30 GB model)..."
# The key goes to curl through a config on stdin rather than -H:
# argv is world-readable in /proc, and slurm-llama.sh runs this same
# poll on a shared cluster node. printf is a shell builtin, so the
# key never reaches another process's command line.
until printf 'header = "Authorization: Bearer %s"\n' "$API_KEY" \
        | curl -sf -K - "http://localhost:$PORT/health" >/dev/null 2>&1; do
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

echo "Starting Cloudflare tunnel (skip if already running — see start-cloudflared-once.sh)..."
if pgrep -f "cloudflared tunnel --url http://127.0.0.1:${PORT}" >/dev/null 2>&1; then
    echo "cloudflared already running; URL unchanged."
    if [ -f "./cloudflared.url" ]; then cat "./cloudflared.url"; fi
    CF_PID=""
else
# 127.0.0.1, not localhost: the pgrep above and
# start-cloudflared-once.sh both match on that literal string, so a
# mismatch here meant this script never recognised its own tunnel --
# every run started a second one and the URL changed anyway.
cloudflared tunnel --url "http://127.0.0.1:$PORT" >"$CF_LOG" 2>&1 &
CF_PID=$!
sleep 12
grep -o 'https://[^ ]*trycloudflare\.com' "$CF_LOG" | head -1 | tee cloudflared.url.tmp | xargs -I{} echo "{}/v1" | tee ./cloudflared.url
fi

echo
echo "============================================================"
echo "  API key (paste into Cursor's OpenAI API Key field):"
echo
echo "    $API_KEY"
echo
echo "  The tunnel URL is public. Requests without this key are"
echo "  rejected."
echo "============================================================"
echo
echo "Press Ctrl+C to stop everything."

# ── keep running until interrupted ───────────────────────────
trap 'echo; echo Shutting down...; kill $SERVER_PID 2>/dev/null; [ -n "${CF_PID:-}" ] && kill $CF_PID 2>/dev/null; exit 0' INT TERM
wait $SERVER_PID
