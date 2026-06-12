#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

echo "Building wrapper image: $IMAGE"
docker build \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  -t "$IMAGE" \
  -f "$REPO_ROOT/Dockerfile.stepfun37-workspace" \
  "$REPO_ROOT"

echo "Build complete."
