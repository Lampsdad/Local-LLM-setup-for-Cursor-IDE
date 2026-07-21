#!/usr/bin/env bash
#SBATCH --job-name=local-llm
#SBATCH --partition=debug
#SBATCH --gres=gpu:rtx5090:1
#SBATCH --cpus-per-task=6
#SBATCH --mem=48G
#SBATCH --time=7-00:00:00
#SBATCH --output=slurm-llama-%j.out
# Run the 35B API under Slurm so the GPU shows as allocated in squeue/sinfo.
# Other jobs without --gres=gpu can still use remaining CPUs/RAM on the node.
# Do NOT start this while a manual llama-server is already running (GPU double-book).

set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH}"
cd "${HOME}/research/Local-LLM-setup-for-cursor"

PORT=8081
MODEL="./models/Qwen_Qwen3.6-35B-A3B-Q6_K_L.gguf"
BINARY="./llama-bin/llama-server"
LOG="./server.log"
CF_LOG="./cloudflared.log"

pkill -x cloudflared 2>/dev/null || true

exec "$BINARY" \
  --model "$MODEL" \
  --n-gpu-layers 99 \
  --ctx-size 200000 \
  --flash-attn auto \
  --port "$PORT" \
  --host 0.0.0.0 \
  --alias "qwen3.6-35b-a3b" \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --log-file "$LOG"