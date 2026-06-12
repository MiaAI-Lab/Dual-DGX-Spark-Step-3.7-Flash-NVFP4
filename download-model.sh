#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

download_model() {
  local host_label="$1"
  local is_remote="$2"
  local cmd_prefix=""

  if [[ "$is_remote" == "true" ]]; then
    cmd_prefix="ssh -o BatchMode=yes -o StrictHostKeyChecking=no $WORKER_IP"
  fi

  echo "[$host_label] Checking model cache for $MODEL ..."

  # Check if model is already cached
  local cached
  cached=$($cmd_prefix python3 -c "
import sys
try:
    from huggingface_hub import try_to_load_from_cache
    p = try_to_load_from_cache('$MODEL', 'config.json')
    print('CACHED' if p else 'MISSING')
except Exception as e:
    print('ERROR', e)
" 2>/dev/null || echo "ERROR")

  if [[ "$cached" == "CACHED" ]]; then
    echo "[$host_label] Model already cached."
    return
  fi

  echo "[$host_label] Downloading model $MODEL ..."

  if ! $cmd_prefix command -v huggingface-cli >/dev/null 2>&1; then
    echo "[$host_label] huggingface-cli not found. Installing huggingface_hub..."
    $cmd_prefix python3 -m pip install -U huggingface_hub
  fi

  $cmd_prefix huggingface-cli download "$MODEL"
  echo "[$host_label] Download complete."
}

download_model "$(hostname)" "false"

if [[ -n "${WORKER_IP:-}" ]]; then
  download_model "$WORKER_IP" "true"
fi
