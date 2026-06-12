#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

check_local_image

echo "Copying image $IMAGE to worker $WORKER_IP ..."
docker save "$IMAGE" | ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" docker load

echo "Copy complete."
