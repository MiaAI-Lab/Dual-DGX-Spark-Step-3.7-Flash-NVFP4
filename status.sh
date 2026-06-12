#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

echo "=== Container Status ==="

echo "[HEAD] $(hostname):"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "  Container '$CONTAINER_NAME': RUNNING"
else
  echo "  Container '$CONTAINER_NAME': NOT RUNNING"
fi

echo ""
echo "[WORKER] $WORKER_IP:"
if ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
  "docker ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}$'" 2>/dev/null; then
  echo "  Container '$CONTAINER_NAME': RUNNING"
else
  echo "  Container '$CONTAINER_NAME': NOT RUNNING"
fi

echo ""
echo "=== Port Check ==="
if ss -tln 2>/dev/null | grep -qE ":${PORT}\b" || netstat -tln 2>/dev/null | grep -qE ":${PORT}\b"; then
  echo "Port $PORT: LISTENING"
else
  echo "Port $PORT: NOT LISTENING"
fi

echo ""
echo "=== API Check ==="
if curl -sS --max-time 5 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
  echo "API reachable at http://127.0.0.1:$PORT"
  curl -sS --max-time 5 "http://127.0.0.1:$PORT/v1/models" | jq .
else
  echo "API NOT reachable at http://127.0.0.1:$PORT"
fi
