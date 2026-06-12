#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

clean_cache() {
  local host_label="$1"
  local is_remote="$2"
  local cmd_prefix=""

  if [[ "$is_remote" == "true" ]]; then
    cmd_prefix="ssh -o BatchMode=yes -o StrictHostKeyChecking=no $WORKER_IP"
  fi

  HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"
  MODEL_CACHE="$HF_HOME/hub/models--stepfun-ai--Step-3.7-Flash-NVFP4"

  if [[ ! -d "$MODEL_CACHE" ]]; then
    echo "[$host_label] Model cache not found at $MODEL_CACHE"
    return
  fi

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_DIR="$HF_HOME/hub/backups/models--stepfun-ai--Step-3.7-Flash-NVFP4-$TIMESTAMP"

  echo "[$host_label] Moving model cache to backup: $BACKUP_DIR"
  $cmd_prefix mkdir -p "$HF_HOME/hub"
  $cmd_prefix mv "$MODEL_CACHE" "$BACKUP_DIR"

  echo "[$host_label] Done. Re-run ./download-model.sh to re-download."
}

clean_cache "$(hostname)" "false"
clean_cache "$WORKER_IP" "true"
