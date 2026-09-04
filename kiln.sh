#!/usr/bin/env bash
# ============================================================
#  kiln -- macOS / Linux front door.
#
#    ./kiln.sh                status board
#    ./kiln.sh setup          llama.cpp + cloudflared + models/
#    ./kiln.sh get [base|ablit|both]
#    ./kiln.sh start [base|ablit]
#    ./kiln.sh stop           stop server and tunnel
#    ./kiln.sh key [show|rotate]
#    ./kiln.sh bench | quality | clean | help
#
#  This dispatches to the per-platform scripts in scripts/unix/.
#  It deliberately holds no launch logic of its own -- those
#  scripts stay the single source of truth.
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
UNIX="$ROOT/scripts/unix"
cd "$ROOT"

# ---- platform ----------------------------------------------
case "$(uname -s)" in
    Darwin) PLATFORM=mac ;;
    Linux)
        # Fedora/RHEL need dnf and a different CUDA package path,
        # which install_fedora.sh handles.
        if [ -r /etc/os-release ] &&
           grep -qiE '^(ID|ID_LIKE)=.*(fedora|rhel|centos)' /etc/os-release; then
            PLATFORM=fedora
        else
            PLATFORM=linux
        fi
        ;;
    *)
        echo "kiln.sh supports macOS and Linux. On Windows use:  kiln" >&2
        exit 1
        ;;
esac

INSTALL="$UNIX/install_${PLATFORM}.sh"
START="$UNIX/start_${PLATFORM}.sh"

have() { command -v "$1" >/dev/null 2>&1; }

# ---- status board ------------------------------------------
status() {
    local bin="./llama-bin/llama-server"
    printf '\n'
    sed 's/^/  /' "$ROOT/assets/banner.txt" 2>/dev/null || true
    printf '\n'
    printf ' %s\n' '------------------------------------------------------------'

    if [ -x "$bin" ]; then
        printf '  %-14s %s\n' "llama.cpp" "installed"
        if "$bin" --help 2>&1 | grep -q 'draft-mtp'; then
            printf '  %-14s %s\n' "MTP support" "available"
        else
            printf '  %-14s %s\n' "MTP support" "unavailable  build predates b9180"
        fi
    else
        printf '  %-14s %s\n' "llama.cpp" "not installed    ./kiln.sh setup"
    fi

    if have cloudflared; then
        printf '  %-14s %s\n' "cloudflared" "installed"
    else
        printf '  %-14s %s\n' "cloudflared" "not installed"
    fi

    if have nvidia-smi; then
        printf '  %-14s %s\n' "GPU" \
            "$(nvidia-smi "--query-gpu=name,memory.total" --format=csv,noheader 2>/dev/null | head -1)"
    elif [ "$PLATFORM" = mac ]; then
        printf '  %-14s %s\n' "GPU" "Apple $(sysctl -n machdep.cpu.brand_string 2>/dev/null) (Metal)"
    fi

    printf ' %s\n' '------------------------------------------------------------'
    local found=0
    for f in ./models/Qwen3.8-27B-*.gguf; do
        [ -e "$f" ] || continue
        printf '  %-14s %s\n' "Qwen3.8-27B" "$(basename "$f")"; found=1
    done
    for f in ./models/Huihui-Qwen3.8-27B-abliterated-*.gguf; do
        [ -e "$f" ] || continue
        printf '  %-14s %s\n' " abliterated" "$(basename "$f")"; found=1
    done
    [ "$found" = 0 ] && printf '  %-14s %s\n' "weights" "none         ./kiln.sh get"

    printf ' %s\n' '------------------------------------------------------------'
    if pgrep -x llama-server >/dev/null 2>&1; then
        printf '  %-14s %s\n' "server" "running"
    else
        printf '  %-14s %s\n' "server" "stopped"
    fi
    if [ -f ./api_key.txt ]; then
        local k; k="$(tr -d '\r\n' < ./api_key.txt)"
        printf '  %-14s %s...%s   ./kiln.sh key show\n' "API key" \
            "${k:0:6}" "${k: -4}"
    else
        printf '  %-14s %s\n' "API key" "not generated yet"
    fi
    printf ' %s\n\n' '------------------------------------------------------------'

    # The first unmet dependency, so following it repeatedly walks
    # an empty checkout all the way to a served model.
    if   [ ! -x "$bin" ];   then echo " Next:  ./kiln.sh setup    install llama.cpp"
    elif [ "$found" = 0 ];  then echo " Next:  ./kiln.sh get      download the weights"
    elif ! pgrep -x llama-server >/dev/null 2>&1; then
                                 echo " Next:  ./kiln.sh start    serve a model to Cursor"
    else                         echo " Server is up. Point Cursor at the URL it printed."
    fi
    printf '\n'
}

usage() {
    cat <<'USAGE'

 Usage:  ./kiln.sh COMMAND [ARGUMENT]

   status            what is installed, downloaded and running
   setup             llama.cpp, cloudflared and models/
   get [base|ablit|both]
                     download weights (default: base)
   start [base|ablit]
                     serve a model to Cursor
   stop              stop llama-server and cloudflared
   key [show|rotate] the API key Cursor needs
   bench             speed benchmarks
   quality           KL-divergence of each quant vs Q8_0
   clean             reclaim space from superseded GGUFs
   help              this text

 With no command, kiln prints the status board.

USAGE
}

CMD="${1:-status}"
ARG="${2:-}"

case "$CMD" in
    status|"")  status ;;
    setup)      exec "$INSTALL" ;;
    get)
        case "$ARG" in
            both)
                # Stock first: it brings down the MTP head and the
                # vision projector, which the abliterated run then
                # finds present and skips.
                VARIANT=base  "$UNIX/download.sh" || exit $?
                VARIANT=ablit exec "$UNIX/download.sh"
                ;;
            ablit|base) exec env VARIANT="$ARG" "$UNIX/download.sh" ;;
            "")         exec "$UNIX/download.sh" ;;
            *)          echo "kiln: unknown variant '$ARG' (use base, ablit or both)" >&2; exit 1 ;;
        esac
        ;;
    start)
        case "$ARG" in
            ablit|base) exec env VARIANT="$ARG" "$START" ;;
            "")         exec "$START" ;;
            *)          echo "kiln: unknown variant '$ARG' (use base or ablit)" >&2; exit 1 ;;
        esac
        ;;
    stop)
        pkill -x llama-server 2>/dev/null && echo " stopped llama-server" || echo " llama-server was not running"
        pkill -x cloudflared  2>/dev/null && echo " stopped cloudflared"  || true
        ;;
    key)
        [ "$ARG" = rotate ] && rm -f ./api_key.txt
        # shellcheck source=scripts/unix/lib_api_key.sh
        . "$UNIX/lib_api_key.sh"
        echo
        echo " API key -- paste into Cursor's OpenAI API Key field"
        echo
        echo "   $API_KEY"
        echo
        echo " Stored in api_key.txt, readable only by you."
        echo
        ;;
    bench)    exec "$UNIX/benchmark.sh" ;;
    quality)  exec "$UNIX/quality.sh" ;;
    clean)    exec "$UNIX/cleanup.sh" ;;
    help|-h|--help) usage ;;
    *)  echo "kiln: unknown command '$CMD'" >&2; usage; exit 1 ;;
esac
