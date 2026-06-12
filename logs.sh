#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

echo "=== Latest startup log ==="
LATEST=$(ls -t "$REPO_ROOT"/logs/start-*.log 2>/dev/null | head -n 1 || true)
if [[ -n "${LATEST:-}" ]]; then
  echo "File: $LATEST"
  tail -n 50 "$LATEST"
else
  echo "No startup logs found."
fi

echo ""
echo "=== Head container logs ==="
docker logs --tail 200 "$CONTAINER_NAME" 2>&1 || echo "Container not running."

echo ""
echo "=== Worker container logs ==="
ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
  "docker logs --tail 200 $CONTAINER_NAME 2>&1" || echo "Worker container not running."
