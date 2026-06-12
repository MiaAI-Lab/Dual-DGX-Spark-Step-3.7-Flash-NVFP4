#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
SKIP_CONFIG_LOAD=1 source "$REPO_ROOT/lib/common.sh"

echo "Checking required commands..."
for cmd in docker ssh rsync curl jq; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  [OK] $cmd"
  else
    echo "Error: required command '$cmd' not found in PATH"
    exit 1
  fi
done

if [[ ! -f "$REPO_ROOT/config.env" ]]; then
  echo "Creating config.env from config.env.example..."
  cp "$REPO_ROOT/config.env.example" "$REPO_ROOT/config.env"
  echo ""
  echo "Next steps:"
  echo "  1. Edit config.env:   nano $REPO_ROOT/config.env"
  echo "  2. Build image:      ./build-image.sh"
  echo "  3. Copy to worker:   ./copy-image-to-worker.sh"
  echo "  4. Download model:   ./download-model.sh"
  echo "  5. Start serving:    ./start.sh no-mtp"
else
  echo "config.env already exists."
  echo ""
  echo "Next steps:"
  echo "  - Build image:      ./build-image.sh"
  echo "  - Copy to worker:   ./copy-image-to-worker.sh"
  echo "  - Download model:   ./download-model.sh"
  echo "  - Start serving:    ./start.sh no-mtp"
fi
