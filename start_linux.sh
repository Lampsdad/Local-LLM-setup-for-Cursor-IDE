#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export PATH="${HOME}/.local/bin:${PATH}"

MODEL="./models/Qwen_Qwen3.6-35B-A3B-Q6_K_L.gguf"
BINARY="./llama-bin/llama-server"
PORT=8081
LOG="./server.log"
CF_LOG="./cloudflared.log"

# ── pre-flight checks ────────────────────────────────────────
if [ ! -f "$BINARY" ]; then
    echo "ERROR: $BINARY not found. Run ./install_linux.sh first."
    exit 1
fi
if [ ! -f "$MODEL" ]; then
    echo "ERROR: $MODEL not found. Run ./download_model.sh first."
    exit 1
fi

# ── stop any running instances ───────────────────────────────
echo "Stopping any existing llama-server (cloudflared left running for stable URL)..."
pkill -x llama-server 2>/dev/null || true
sleep 1

# ── start llama-server ───────────────────────────────────────
echo "Starting llama-server..."
"$BINARY" \
    --model        "$MODEL" \
    --n-gpu-layers 99 \
    --ctx-size     200000 \
    --flash-attn   auto \
    --port         $PORT \
    --host         0.0.0.0 \
    --alias        "qwen3.6-35b-a3b" \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --log-file     "$LOG" &
SERVER_PID=$!

# ── wait for server to be ready (health poll) ────────────────
echo "Waiting for server to load (1-2 min for a 30 GB model)..."
until curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; do
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
cloudflared tunnel --url "http://localhost:$PORT" >"$CF_LOG" 2>&1 &
CF_PID=$!
sleep 12
grep -o 'https://[^ ]*trycloudflare\.com' "$CF_LOG" | head -1 | tee cloudflared.url.tmp | xargs -I{} echo "{}/v1" | tee ./cloudflared.url
fi
echo "Press Ctrl+C to stop everything."

# ── keep running until interrupted ───────────────────────────
trap 'echo; echo Shutting down...; kill $SERVER_PID 2>/dev/null; [ -n "${CF_PID:-}" ] && kill $CF_PID 2>/dev/null; exit 0' INT TERM
wait $SERVER_PID
