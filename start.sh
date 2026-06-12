#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-mtp}"

case "$MODE" in
  no-mtp|nomtp)
    "$REPO_ROOT/start-no-mtp.sh"
    ;;
  mtp)
    "$REPO_ROOT/start-mtp.sh"
    ;;
  *)
    echo "Usage: $0 [no-mtp|mtp] (default: mtp)"
    exit 1
    ;;
esac
