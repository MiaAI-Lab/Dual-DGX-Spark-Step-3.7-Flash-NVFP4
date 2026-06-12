#!/bin/bash
set -euo pipefail

# NCCL load-order fix for official vLLM containers on DGX Spark
fix_nccl_load_order() {
  echo "[launch] Checking NCCL load order ..."

  local system_nccl=""
  for candidate in \
    "/usr/lib/$(gcc -print-multiarch 2>/dev/null || true)/libnccl.so.2" \
    "/usr/lib/aarch64-linux-gnu/libnccl.so.2" \
    "/usr/lib/x86_64-linux-gnu/libnccl.so.2"; do
    if [[ -e "$candidate" ]] || [[ -L "$candidate" ]]; then
      system_nccl="$candidate"
      break
    fi
  done
  [[ -z "$system_nccl" ]] && system_nccl=$(ldconfig -p 2>/dev/null | awk '/libnccl\.so\.2/ && $NF ~ /^\/usr\/lib\//{print $NF;exit}' || true)

  if [[ -z "$system_nccl" ]]; then
    echo "[launch] No system libnccl.so.2 found; skipping."
    return
  fi
  echo "[launch] System NCCL: $system_nccl"

  local py_nccl=""
  for candidate in \
    "/usr/local/lib/python3.12/dist-packages/nvidia/nccl/lib/libnccl.so.2" \
    "/usr/local/lib/python3.12/site-packages/nvidia/nccl/lib/libnccl.so.2" \
    "/opt/venv/lib/python3.12/site-packages/nvidia/nccl/lib/libnccl.so.2" \
    "/opt/env/lib/python3.12/site-packages/nvidia/nccl/lib/libnccl.so.2"; do
    if [[ -e "$candidate" ]] || [[ -L "$candidate" ]]; then
      py_nccl="$candidate"
      break
    fi
  done

  if [[ -z "$py_nccl" ]]; then
    echo "[launch] No pip-installed NCCL found; skipping."
    return
  fi

  local system_real py_real
  system_real=$(readlink -f "$system_nccl" 2>/dev/null || echo "$system_nccl")
  py_real=$(readlink -f "$py_nccl" 2>/dev/null || echo "$py_nccl")

  if [[ "$system_real" == "$py_real" ]]; then
    echo "[launch] NCCL already points to system library."
    return
  fi

  echo "[launch] Patching NCCL symlink ..."
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo mv "$py_nccl" "${py_nccl}.spark-vllm-backup"
    sudo ln -s "$system_nccl" "$py_nccl"
  else
    mv "$py_nccl" "${py_nccl}.spark-vllm-backup"
    ln -s "$system_nccl" "$py_nccl"
  fi
  echo "[launch] NCCL patch applied."
}

fix_nccl_load_order

exec vllm serve "__MODEL__" \
  --served-model-name "__SERVED_MODEL_NAME__" \
  --trust-remote-code \
  --host 0.0.0.0 \
  --port __PORT__ \
  --tensor-parallel-size __TP_SIZE__ \
  --max-model-len __MAX_MODEL_LEN__ \
  --max-num-batched-tokens __MAX_NUM_BATCHED_TOKENS__ \
  --max-num-seqs __MAX_NUM_SEQS__ \
  --gpu-memory-utilization __GPU_MEMORY_UTILIZATION__ \
  --quantization modelopt \
  --kv-cache-dtype fp8 \
  --disable-cascade-attn \
  --disable-custom-all-reduce \
  --no-enable-flashinfer-autotune \
  --enable-auto-tool-choice \
  --reasoning-parser step3p5 \
  --tool-call-parser step3p5
