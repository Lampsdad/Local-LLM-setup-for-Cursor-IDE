# Sourced by the download / start scripts. Shell twin of
# lib_variants.bat -- see that file for why the two variants
# share their MTP head and vision projector.
#
#   VARIANT=ablit ./start_linux.sh
#
# Sets: V_ID V_LABEL V_REPO V_PREFIX V_ALIAS V_UNCENSORED

case "${VARIANT:-base}" in
    base|stock)
        V_ID="base"
        V_LABEL="Qwen3.8-27B"
        V_REPO="unsloth/Qwen3.8-27B-GGUF"
        V_PREFIX="Qwen3.8-27B"
        V_ALIAS="qwen3.8-27b"
        V_UNCENSORED=0
        ;;
    ablit|abliterated)
        V_ID="ablit"
        V_LABEL="Qwen3.8-27B abliterated"
        V_REPO="huihui-ai/Huihui-Qwen3.8-27B-abliterated-GGUF"
        V_PREFIX="Huihui-Qwen3.8-27B-abliterated"
        V_ALIAS="qwen3.8-27b-abliterated"
        V_UNCENSORED=1
        ;;
    *)
        echo "ERROR: unknown VARIANT '${VARIANT}'. Use 'base' or 'ablit'." >&2
        exit 1
        ;;
esac
