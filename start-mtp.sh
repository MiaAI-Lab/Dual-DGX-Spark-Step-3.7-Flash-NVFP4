#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

print_config

# Stop any existing run
stop_containers

# Check images exist
check_local_image
check_worker_image

# Generate runtime scripts
RUNTIME_DIR="$REPO_ROOT/runtime"
mkdir -p "$RUNTIME_DIR"

make_node_script() {
  local src="$1"
  local dest="$2"
  local nnodes="$3"
  local node_rank="$4"
  local master_addr="$5"

  cp "$src" "$dest"

  # Replace config placeholders
  sed -i \
    -e "s|__MODEL__|${MODEL}|g" \
    -e "s|__SERVED_MODEL_NAME__|${SERVED_MODEL_NAME}|g" \
    -e "s|__PORT__|${PORT}|g" \
    -e "s|__TP_SIZE__|${TP_SIZE}|g" \
    -e "s|__MAX_MODEL_LEN__|${MAX_MODEL_LEN}|g" \
    -e "s|__MAX_NUM_BATCHED_TOKENS__|${MAX_NUM_BATCHED_TOKENS}|g" \
    -e "s|__MAX_NUM_SEQS__|${MAX_NUM_SEQS}|g" \
    -e "s|__GPU_MEMORY_UTILIZATION__|${GPU_MEMORY_UTILIZATION}|g" \
    -e "s|__MTP_NUM_SPECULATIVE_TOKENS__|${MTP_NUM_SPECULATIVE_TOKENS}|g" \
    "$dest"

  # Remove empty/backslash-only lines, strip trailing backslash, append multi-node flags
  local extra="--nnodes $nnodes --node-rank $node_rank --master-addr $master_addr --master-port $MASTER_PORT"
  if [[ "$node_rank" -gt 0 ]]; then
    extra="$extra --headless"
  fi

  sed -i \
    -e '/^[[:space:]\\]*$/d' \
    -e '$ s/[[:space:]]*\\[[:space:]]*$//' \
    -e "\$ s/$/ $extra/" \
    "$dest"
}

HEAD_SCRIPT="$RUNTIME_DIR/launch-head.sh"
WORKER_SCRIPT="$RUNTIME_DIR/launch-worker.sh"

NNODES="${NNODES:-2}"
make_node_script "$REPO_ROOT/templates/launch-mtp.sh" "$HEAD_SCRIPT" "$NNODES" 0 "$HEAD_IP"
make_node_script "$REPO_ROOT/templates/launch-mtp.sh" "$WORKER_SCRIPT" "$NNODES" 1 "$HEAD_IP"

if [[ "${DEBUG:-0}" == "1" ]]; then
  echo "=== Generated head launch script ==="
  sed -n '1,220p' "$HEAD_SCRIPT"
  echo "=== Generated worker launch script ==="
  sed -n '1,220p' "$WORKER_SCRIPT"
fi

# Start containers on both nodes
echo "Starting container on head ($HEAD_IP) ..."
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d \
  --gpus all \
  --privileged \
  --ipc=host \
  --network host \
  --name "$CONTAINER_NAME" \
  -e "NCCL_SOCKET_IFNAME=$ETH_IF" \
  -e "NCCL_IB_HCA=$IB_IF" \
  -e "NCCL_IGNORE_CPU_AFFINITY=1" \
  -e "NCCL_IB_GID_INDEX=${NCCL_IB_GID_INDEX:-0}" \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  --entrypoint= \
  "$IMAGE" \
  sleep infinity

echo "Starting container on worker ($WORKER_IP) ..."
ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
  "docker rm -f '$CONTAINER_NAME' >/dev/null 2>&1 || true && \
   docker run -d \
     --gpus all \
     --privileged \
     --ipc=host \
     --network host \
     --name '$CONTAINER_NAME' \
     -e 'NCCL_SOCKET_IFNAME=$ETH_IF' \
     -e 'NCCL_IB_HCA=$IB_IF' \
     -e 'NCCL_IGNORE_CPU_AFFINITY=1' \
     -e 'NCCL_IB_GID_INDEX=\${NCCL_IB_GID_INDEX:-0}' \
     -v '\$HOME/.cache/huggingface:/root/.cache/huggingface' \
     --entrypoint= \
     '$IMAGE' \
     sleep infinity"

# Copy launch scripts to containers
echo "Copying launch script to head ..."
docker cp "$HEAD_SCRIPT" "$CONTAINER_NAME:/workspace/launch.sh"
docker exec "$CONTAINER_NAME" chmod +x /workspace/launch.sh

echo "Copying launch script to worker ..."
scp -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_SCRIPT" "$WORKER_IP:/tmp/launch-worker.sh"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
  "docker cp /tmp/launch-worker.sh $CONTAINER_NAME:/workspace/launch.sh && \
   docker exec $CONTAINER_NAME chmod +x /workspace/launch.sh && \
   rm -f /tmp/launch-worker.sh"

# Launch worker vLLM in background
echo "Starting worker vLLM (rank 1) ..."
ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
  "docker exec -d $CONTAINER_NAME bash -c 'bash /workspace/launch.sh >> /proc/1/fd/1 2>&1'"

sleep 5

# Launch head vLLM in background and show live logs until ready
LOGFILE="$REPO_ROOT/logs/start-mtp-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$REPO_ROOT/logs"

echo "Starting head vLLM (rank 0) ..."
docker exec -d "$CONTAINER_NAME" bash -c "bash /workspace/launch.sh >> /proc/1/fd/1 2>&1"

sleep 3

echo "Waiting for API at http://127.0.0.1:$PORT/v1/models (logs follow) ..."
(
  docker logs -f --tail 0 "$CONTAINER_NAME" 2>&1
) | tee "$LOGFILE" &
LOGS_PID=$!
echo "$LOGS_PID" > "$REPO_ROOT/logs/start-mtp.pid"

READY=false
for i in $(seq 1 120); do
  if curl -sS --max-time 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 3
done

# Stop log tailing
if ps -p "$LOGS_PID" >/dev/null 2>&1; then
  kill "$LOGS_PID" 2>/dev/null || true
  wait "$LOGS_PID" 2>/dev/null || true
fi

if [[ "$READY" == "true" ]]; then
  echo ""
  echo "Server is ready!"
  echo "  API:  http://$HEAD_IP:$PORT"
  echo "  Logs: ./logs.sh"
  echo "  Stop: ./stop.sh"
else
  echo ""
  echo "Timeout waiting for server to become ready."
  echo "Check logs: ./logs.sh"
  exit 1
fi
