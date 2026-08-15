#!/usr/bin/env bash
#SBATCH --job-name=local-llm
#SBATCH --partition=debug
#SBATCH --gres=gpu:rtx5090:1
#SBATCH --cpus-per-task=6
#SBATCH --mem=48G
#SBATCH --time=7-00:00:00
#SBATCH --output=slurm-llama-%j.out
# Run the Qwen3.8-27B API under Slurm so the GPU shows as allocated in squeue/sinfo.
# Other jobs without --gres=gpu can still use remaining CPUs/RAM on the node.
# Do NOT start this while a manual llama-server is already running (GPU double-book).

set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "${HOME}/research/Local-LLM-setup-for-cursor"

PORT=8081
QUANT="${QUANT:-UD-Q5_K_XL}"
MODEL="./models/Qwen3.8-27B-${QUANT}.gguf"
MMPROJ="./models/mmproj-F16.gguf"
MTP="./models/mtp-Qwen3.8-27B-Q8_0.gguf"
BINARY="./llama-bin/llama-server"
LOG="./server.log"
CF_LOG="./cloudflared.log"

pkill -x cloudflared 2>/dev/null || true

# This binds 0.0.0.0 on a shared cluster node, so the key is not
# optional here — anyone who can reach the node can reach the API.
. ./lib_api_key.sh

# This job requests a single RTX 5090 (32 GB), so the sizing below
# matches start_qwen3.8_27b.bat: UD-Q5_K_XL weights + MTP head +
# vision leave room for 131K of q8_0 KV.
EXTRA=()
if [ -f "$MTP" ] && "$BINARY" --help 2>&1 | grep -q 'draft-mtp'; then
    EXTRA+=(--spec-type draft-mtp --spec-draft-model "$MTP" \
            --spec-draft-ngl 99 --spec-draft-n-max 3)
fi
[ -f "$MMPROJ" ] && EXTRA+=(--mmproj "$MMPROJ")

exec "$BINARY" \
  --model "$MODEL" \
  --n-gpu-layers 99 \
  --ctx-size 131072 \
  --flash-attn auto \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --parallel 1 \
  --batch-size 4096 \
  --ubatch-size 1024 \
  --threads 6 \
  --jinja \
  --reasoning-format deepseek \
  --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 \
  --port "$PORT" \
  --host 0.0.0.0 \
  --alias "qwen3.8-27b" \
  --api-key-file "$API_KEY_FILE" \
  "${EXTRA[@]}" \
  --log-file "$LOG"