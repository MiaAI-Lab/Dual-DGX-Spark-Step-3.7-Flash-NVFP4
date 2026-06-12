#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

clean_cache() {
  local host_label="$1"
  local is_remote="$2"

  # Compute HF_HOME inside the target context (local or remote)
  local hf_home
  if [[ "$is_remote" == "true" ]]; then
    # Use a quoted SSH heredoc so the worker expands $HOME
    hf_home=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
      'echo "${HF_HOME:-$HOME/.cache/huggingface}"')
  else
    hf_home="${HF_HOME:-$HOME/.cache/huggingface}"
  fi

  local model_cache="$hf_home/hub/models--stepfun-ai--Step-3.7-Flash-NVFP4"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local backup_dir="$hf_home/hub/backups/models--stepfun-ai--Step-3.7-Flash-NVFP4-$timestamp"

  if [[ "$is_remote" == "true" ]]; then
    # Run entire cleanup on worker via a single SSH command
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
      "hf_home=\"\${HF_HOME:-\$HOME/.cache/huggingface}\"; \
       model_cache=\"\$hf_home/hub/models--stepfun-ai--Step-3.7-Flash-NVFP4\"; \
       if [[ ! -d \"\$model_cache\" ]]; then \
         echo \"[$host_label] Model cache not found at \$model_cache\"; \
         exit 0; \
       fi; \
       timestamp=\"\$(date +%Y%m%d-%H%M%S)\"; \
       backup_dir=\"\$hf_home/hub/backups/models--stepfun-ai--Step-3.7-Flash-NVFP4-\$timestamp\"; \
       echo \"[$host_label] Moving model cache to backup: \$backup_dir\"; \
       mkdir -p \"\$hf_home/hub/backups\"; \
       mv \"\$model_cache\" \"\$backup_dir\"; \
       echo \"[$host_label] Done. Re-run ./download-model.sh to re-download.\""
  else
    if [[ ! -d "$model_cache" ]]; then
      echo "[$host_label] Model cache not found at $model_cache"
      return
    fi
    echo "[$host_label] Moving model cache to backup: $backup_dir"
    mkdir -p "$hf_home/hub/backups"
    mv "$model_cache" "$backup_dir"
    echo "[$host_label] Done. Re-run ./download-model.sh to re-download."
  fi
}

clean_cache "$(hostname)" "false"

if [[ -n "${WORKER_IP:-}" ]]; then
  clean_cache "$WORKER_IP" "true"
fi
