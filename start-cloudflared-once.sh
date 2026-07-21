#!/usr/bin/env bash
# Start cloudflared once; persist URL to cloudflared.url. Do not restart if already running.
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
ROOT="${HOME}/research/Local-LLM-setup-for-cursor"
cd "$ROOT"
PORT=8081
CF_LOG="./cloudflared.log"
URL_FILE="./cloudflared.url"

if pgrep -f "cloudflared tunnel --url http://127.0.0.1:${PORT}" >/dev/null 2>&1; then
  if [ -f "$URL_FILE" ]; then
    cat "$URL_FILE"
    exit 0
  fi
fi

: >>"$CF_LOG"
nohup cloudflared tunnel --url "http://127.0.0.1:${PORT}" >>"$CF_LOG" 2>&1 &
for _ in $(seq 1 40); do
  url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$CF_LOG" | tail -1)
  if [ -n "$url" ]; then
    echo "${url}/v1" | tee "$URL_FILE"
    exit 0
  fi
  sleep 2
done
echo "ERROR: could not read tunnel URL from $CF_LOG" >&2
exit 1