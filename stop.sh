#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

echo "Stopping containers ..."
stop_containers

# Kill any lingering log-tail or docker exec background processes for this container
pkill -f "docker logs.*$CONTAINER_NAME" 2>/dev/null || true
pkill -f "docker exec.*$CONTAINER_NAME" 2>/dev/null || true

echo "Stop complete."
