#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/common.sh"

echo "Stopping containers ..."
stop_containers

# Clean up PID files created by start scripts, if any
if ls "$REPO_ROOT/logs/"*.pid >/dev/null 2>&1; then
  for pidfile in "$REPO_ROOT/logs/"*.pid; do
    pid=$(cat "$pidfile" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "Killed process $pid (from $(basename "$pidfile"))"
    fi
    rm -f "$pidfile"
  done
fi

echo "Stop complete."
