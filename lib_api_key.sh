#!/usr/bin/env bash
# ============================================================
#  Shared API-key handling for the start_*.sh scripts.
#
#  Sourced, not executed:  . ./lib_api_key.sh
#
#  Why this exists: the Cloudflare quick-tunnel URL is public.
#  Without a key, anyone who guesses or scrapes the hostname gets
#  a free OpenAI-compatible endpoint pointed at your GPU. Cursor
#  makes you fill in an API-key field anyway, so requiring one
#  costs nothing.
#
#  Sets:  API_KEY       the key itself
#         API_KEY_FILE  path to pass to --api-key-file
# ============================================================

API_KEY_FILE="./api_key.txt"

if [ ! -f "$API_KEY_FILE" ]; then
    echo "Generating an API key for this server (${API_KEY_FILE})..."
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16 | tr -d '\n' > "$API_KEY_FILE"
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr -d '\n-' | tr '[:upper:]' '[:lower:]' > "$API_KEY_FILE"
    elif [ -r /dev/urandom ]; then
        # od is in POSIX; xxd is not guaranteed to be installed.
        od -An -tx1 -N16 /dev/urandom | tr -d ' \n' > "$API_KEY_FILE"
    else
        echo "ERROR: no way to generate a random key (need openssl, uuidgen, or /dev/urandom)."
        echo "       Write one yourself:  echo mysecret > $API_KEY_FILE"
        exit 1
    fi
    # The key is a credential; keep it off other accounts on the box.
    chmod 600 "$API_KEY_FILE" 2>/dev/null || true
fi

API_KEY="$(tr -d '\r\n' < "$API_KEY_FILE")"

if [ -z "$API_KEY" ]; then
    echo "ERROR: $API_KEY_FILE is empty. Delete it and re-run to regenerate."
    exit 1
fi
