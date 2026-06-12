#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

require_command docker
require_command rsync
require_command scp

check_local_image

HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"
REPO_DIR="$HF_HOME/hub/models--stepfun-ai--Step-3.7-Flash-NVFP4"

if [[ ! -d "$REPO_DIR/snapshots" ]]; then
  echo "Error: Step-3.7-Flash-NVFP4 not found in HF cache."
  echo "Run first: ./download-model.sh"
  exit 1
fi

# Resolve the snapshot referenced by refs/main (the current revision) so every
# cluster node grafts the same one; fall back to the newest snapshot.
REF_FILE="$REPO_DIR/refs/main"
REV="$([ -f "$REF_FILE" ] && cat "$REF_FILE" || true)"
if [[ -n "$REV" ]] && [[ -d "$REPO_DIR/snapshots/$REV" ]]; then
  SNAP_HOST="$REPO_DIR/snapshots/$REV/"
else
  SNAP_HOST="$(ls -dt "$REPO_DIR"/snapshots/*/ 2>/dev/null | head -1)"
fi
if [[ -z "${SNAP_HOST:-}" ]] || [[ ! -d "$SNAP_HOST" ]]; then
  echo "Error: no snapshot found under $REPO_DIR/snapshots"
  exit 1
fi
SNAP_NAME="$(basename "$SNAP_HOST")"
SNAP_CTR="/root/.cache/huggingface/hub/models--stepfun-ai--Step-3.7-Flash-NVFP4/snapshots/$SNAP_NAME"

echo "[graft] Snapshot: $SNAP_NAME"

graft_local() {
  echo "[graft] Running graft locally ..."
  docker run --rm --network host \
    -v "$HF_HOME:/root/.cache/huggingface" \
    -v "$REPO_ROOT/lib:/mod:ro" \
    --entrypoint python3 "$IMAGE" /mod/graft_mtp.py "$SNAP_CTR"
}

verify_graft() {
  local host_label="$1"
  local is_remote="$2"
  local cmd_prefix=""
  local remote_tmp="/tmp/graft_mtp.py"

  if [[ "$is_remote" == "true" ]]; then
    cmd_prefix="ssh -o BatchMode=yes -o StrictHostKeyChecking=no $WORKER_IP"
    $cmd_prefix mkdir -p /tmp
    scp -o BatchMode=yes -o StrictHostKeyChecking=no "$REPO_ROOT/lib/graft_mtp.py" "$WORKER_IP:$remote_tmp"
  fi

  echo "[$host_label] Verifying graft ..."
  local result=""
  local status=0

  if [[ "$is_remote" == "true" ]]; then
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
      "docker run --rm --network host \
        -v '\$HOME/.cache/huggingface:/root/.cache/huggingface' \
        -v '$remote_tmp:/mod/graft_mtp.py:ro' \
        --entrypoint python3 '$IMAGE' /mod/graft_mtp.py '$SNAP_CTR'" \
        >/dev/null 2>&1 && result="OK" || status=$?
  else
    docker run --rm --network host \
      -v "$HF_HOME:/root/.cache/huggingface" \
      -v "$REPO_ROOT/lib:/mod:ro" \
      --entrypoint python3 "$IMAGE" /mod/graft_mtp.py "$SNAP_CTR" \
      >/dev/null 2>&1 && result="OK" || status=$?
  fi

  if [[ "$is_remote" == "true" ]]; then
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" rm -f "$remote_tmp"
  fi

  if [[ "$result" == "OK" ]]; then
    echo "[$host_label] OK: graft verified."
  else
    echo "[$host_label] ERROR: grafting failed with exit status $status"
    exit 1
  fi
}

# Run grafting locally
graft_local
verify_graft "$(hostname)" "false"

# Copy graft script and run on worker
echo "[graft] Copying graft script to worker ..."
scp -o BatchMode=yes -o StrictHostKeyChecking=no "$REPO_ROOT/lib/graft_mtp.py" "$WORKER_IP:/tmp/graft_mtp.py"

echo "[graft] Running graft on worker ..."
ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
  "docker run --rm --network host \
    -v '\$HOME/.cache/huggingface:/root/.cache/huggingface' \
    -v /tmp/graft_mtp.py:/mod/graft_mtp.py:ro \
    --entrypoint python3 $IMAGE /mod/graft_mtp.py '$SNAP_CTR'"

verify_graft "$WORKER_IP" "true"

echo "[graft] Done. Both nodes now have grafted MTP weights."
