#!/bin/bash
set -euo pipefail

find_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$(dirname "$script_dir")"
}

load_config() {
  local config_file
  config_file="$(find_repo_root)/config.env"
  if [[ ! -f "$config_file" ]]; then
    echo "Error: config.env not found at $config_file"
    echo "Please run: cp config.env.example config.env && nano config.env"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$config_file"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found in PATH"
    exit 1
  fi
}

run_worker_ssh() {
  local cmd="$1"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" "$cmd"
}

check_local_image() {
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Error: Docker image '$IMAGE' not found locally. Run ./build-image.sh"
    exit 1
  fi
}

check_worker_image() {
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
    "docker image inspect '$IMAGE' >/dev/null 2>&1" 2>/dev/null; then
    echo "Error: Docker image '$IMAGE' not found on worker $WORKER_IP. Run ./copy-image-to-worker.sh"
    exit 1
  fi
}

stop_containers() {
  local label
  label="$(hostname)"
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  echo "[$label] Stopped container '$CONTAINER_NAME' (if running)"

  if [[ -n "${WORKER_IP:-}" ]]; then
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$WORKER_IP" \
      "docker rm -f '$CONTAINER_NAME' >/dev/null 2>&1 || true"
    echo "[$WORKER_IP] Stopped container '$CONTAINER_NAME' (if running)"
  fi
}

print_config() {
  echo "=== Step-3.7 DGX Spark Config ==="
  echo "Head IP:      ${HEAD_IP:-unset}"
  echo "Worker IP:    ${WORKER_IP:-unset}"
  echo "ETH IF:       ${ETH_IF:-unset}"
  echo "IB IF:        ${IB_IF:-unset}"
  echo "Model:        ${MODEL:-unset}"
  echo "Image:        ${IMAGE:-unset}"
  echo "Container:    ${CONTAINER_NAME:-unset}"
  echo "TP Size:      ${TP_SIZE:-unset}"
  echo "Max Seq:      ${MAX_NUM_SEQS:-unset}"
  echo "Port:         ${PORT:-unset}"
  echo "MTP Tokens:   ${MTP_NUM_SPECULATIVE_TOKENS:-unset}"
  echo "Master Port:  ${MASTER_PORT:-29501}"
  echo "=================================="
}
