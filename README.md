# DGX-Spark-Step-3.7-Flash

Run [stepfun-ai/Step-3.7-Flash-NVFP4](https://huggingface.co/stepfun-ai/Step-3.7-Flash-NVFP4) on **2× NVIDIA DGX Spark** with vLLM.

Features:
- **Baseline (no-MTP)** serving
- **MTP speculative decoding** with grafted BF16 weights (`num_speculative_tokens=3`)
- Standalone repo — no dependency on the original `spark-vllm-docker` codebase
- PyTorch-native distributed (no-Ray) only

## Hardware Requirements

- 2× NVIDIA DGX Spark machines
- Passwordless SSH from head → worker
- Docker + NVIDIA Container Toolkit on both machines
- NVIDIA driver + NCCL on the host (DGX Spark default)
- Hugging Face access / outbound internet for model download

## Repository Structure

```
~/spark/DGX-Spark-Step-3.7-Flash/
├── .gitignore
├── config.env.example
├── Dockerfile.stepfun37-workspace
├── LICENSE
├── README.md
├── build-image.sh
├── clean-cache.sh
├── copy-image-to-worker.sh
├── download-model.sh
├── graft-mtp.sh
├── lib/
│   ├── common.sh
│   └── graft_mtp.py
├── logs/
├── logs.sh
├── setup.sh
├── start-mtp.sh
├── start-no-mtp.sh
├── start.sh
├── status.sh
├── stop.sh
├── templates/
│   ├── launch-mtp.sh
│   └── launch-no-mtp.sh
└── test.sh
```

> `templates/launch-*.sh` are internal container launch scripts. Users should not run them directly.

## Quick Start

Run all commands from the **head** DGX Spark. The head node must have passwordless SSH access to the worker.

Always verify `no-mtp` mode before grafting or starting MTP. If no-MTP does not produce normal text, fix the base image/model setup first before debugging MTP.

```bash
git clone <repo-url>
cd DGX-Spark-Step-3.7-Flash
cp config.env.example config.env
nano config.env
./setup.sh
./build-image.sh
./copy-image-to-worker.sh
./download-model.sh

# Run without MTP first
./start.sh no-mtp
./test.sh

# Stop
./stop.sh

# Graft MTP weights and run with MTP speculative decoding
./graft-mtp.sh
./start.sh mtp
./test.sh
```

## Background Behavior

- `start.sh` shows live container logs while the server boots.
- Once `http://<head-ip>:<port>/v1/models` responds, log streaming stops and your terminal returns.
- Docker containers keep running in the background until you run `./stop.sh`.

## Commands

| Command | Description |
|---|---|
| `./start.sh [no-mtp\|mtp]` | Start serving (default: `mtp`) |
| `./stop.sh` | Stop containers on both nodes |
| `./status.sh` | Show container, port, and API status |
| `./logs.sh` | Show latest startup log + both container logs |
| `./test.sh` | Send a test chat completion request |
| `./graft-mtp.sh` | Graft BF16 MTP weights into the HF cache on both nodes |
| `./download-model.sh` | Download the model on both nodes |
| `./clean-cache.sh` | Move the HF cache aside (backup) on both nodes |

## Configuration

Edit `config.env` to change IPs, ports, model, or vLLM flags.

### Key Settings

```text
HEAD_IP=169.254.109.196
WORKER_IP=169.254.122.228
ETH_IF=enp1s0f1np1
IB_IF=rocep1s0f1,roceP2p1s0f1
MODEL=stepfun-ai/Step-3.7-Flash-NVFP4
PORT=8888
IMAGE=stepfun37-workspace:latest
TP_SIZE=2
NNODES=2
MAX_MODEL_LEN=262144
MAX_NUM_BATCHED_TOKENS=8192
MAX_NUM_SEQS=8
GPU_MEMORY_UTILIZATION=0.85
MTP_NUM_SPECULATIVE_TOKENS=3
MASTER_PORT=29501
NCCL_IB_GID_INDEX=0
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `/workspace` missing in container | Rebuild the wrapper image: `./build-image.sh` |
| Ray timeout / cluster issues | This repo is Ray-free. Use the provided scripts only. |
| BOS loop / garbage output | Make sure you are using the official `vllm/vllm-openai:stepfun37` wrapper image, **not** the old `vllm-node` image. |
| `RuntimeError: The size of tensor a (2048) must match ... (4096)` | The MTP patch did not run. Re-run `./start.sh mtp` and check the head logs. |
| `num_speculative_tokens:4 must be divisible by n_predict=3` | The stepfun37 image expects values divisible by 3. Use `3`, `6`, or `9`. Default is `3`. Higher values are not guaranteed to be faster. `4` is invalid with this image because `num_speculative_tokens` must be divisible by `n_predict=3`. |
| `--spec-draft-p-min` unrecognized | `--spec-draft-p-min` is not supported by the validated `stepfun37` image. Do not add it unless you change vLLM images and verify support. |
| Worker container image missing | Run `./copy-image-to-worker.sh` |
| Model missing / cache not found | Run `./download-model.sh` |

## Known Working Command / Flags

The following flags were validated on 2× DGX Spark. The start scripts generate these commands dynamically (run with `DEBUG=1` to print them).

**Head (rank 0):**

```bash
vllm serve stepfun-ai/Step-3.7-Flash-NVFP4 \
  --served-model-name stepfun-ai/Step-3.7-Flash-NVFP4 \
  --trust-remote-code \
  --host 0.0.0.0 \
  --port 8888 \
  --tensor-parallel-size 2 \
  --max-model-len 262144 \
  --max-num-batched-tokens 8192 \
  --max-num-seqs 8 \
  --gpu-memory-utilization 0.85 \
  --quantization modelopt \
  --kv-cache-dtype fp8 \
  --disable-cascade-attn \
  --disable-custom-all-reduce \
  --no-enable-flashinfer-autotune \
  --enable-auto-tool-choice \
  --reasoning-parser step3p5 \
  --tool-call-parser step3p5 \
  --nnodes 2 \
  --node-rank 0 \
  --master-addr "$HEAD_IP" \
  --master-port "$MASTER_PORT"
```

**Worker (rank 1):** same plus `--headless`.

**With MTP:** add `--speculative-config '{"method":"mtp","num_speculative_tokens":3}'`.

This setup was validated with `vllm/vllm-openai:stepfun37` via the `stepfun37-workspace:latest` wrapper image. Other vLLM images may not work and may produce BOS loops, garbage output, unsupported flag errors, or startup failures.

With MTP `3`, observed throughput is approximately **31–32 tok/s**.

## MTP Grafting

The NVFP4 export from ModelOpt strips the next-n predict (MTP) layers. This repo grafts them back from the original BF16 checkpoint at `stepfun-ai/Step-3.7-Flash`.

Run once on the **head** DGX Spark:

```bash
./graft-mtp.sh
```

The script applies the graft locally and over SSH on the worker.

## MTP vLLM Patch

Grafted MTP tensors are BF16. The vLLM `step3p5_mtp.py` drafter normally inherits the model's NVFP4 `quant_config`, which creates packed drafter parameters of different shapes and raises:

```text
RuntimeError: The size of tensor a (2048) must match the size of tensor b (4096)
```

Set `DEBUG=1` before starting to print the generated vLLM commands before they run:

```bash
DEBUG=1 ./start.sh mtp
```

## MTP vLLM Patch

Grafted MTP tensors are BF16. The vLLM `step3p5_mtp.py` drafter normally inherits the model's NVFP4 `quant_config`, which creates packed drafter parameters of different shapes and raises:

```text
RuntimeError: The size of tensor a (2048) must match the size of tensor b (4096)
```

The MTP launch script patches `step3p5_mtp.py` inside the container before starting vLLM:

```python
# local_mtp_unquant_hack: grafted Step-3.7 MTP tensors are BF16,
# so do not create NVFP4-packed drafter params.
quant_config = None
```

This patch is **idempotent** (marked with `local_mtp_unquant_hack`) and does **not** mutate the global `vllm_config.quant_config`.

## Publishing Checklist

- [ ] Remove personal IPs from `config.env`
- [ ] Commit only `config.env.example` to the repo
- [ ] Verify `.gitignore` excludes `config.env`, `logs/`, `*.log`, `runtime/`, and `__pycache__/`
- [ ] Verify `config.env` is not committed
- [ ] Verify startup works with `./start.sh no-mtp`
- [ ] Verify MTP works with `./graft-mtp.sh` then `./start.sh mtp`
- [ ] Verify `./stop.sh` stops both nodes

## License

MIT — see [LICENSE](LICENSE).
