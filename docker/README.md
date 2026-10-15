# Container build

The image uses the public PyTorch 2.9.1 CUDA 12.8 development image and builds
FlashAttention 2.8.3 from source. It also installs Qwen TTS, the API runtime
dependencies and the repository test dependencies.

Build:

```bash
bash docker/build.sh
```

The default FlashAttention target is H100/Hopper (`FLASH_ATTN_CUDA_ARCHS=90`). To
build for another GPU, pick a profile with `BREEZE_GPU`:

| `BREEZE_GPU` | GPUs | `FLASH_ATTN_CUDA_ARCHS` |
| --- | --- | --- |
| `h100` (default) | H100 / Hopper | `90` |
| `a100` | A100 | `80` |
| `rtx30` | GeForce RTX 30 / Ampere | `80` |
| `rtx40` | GeForce RTX 40 / Ada | `80` |
| `rtx50` | GeForce RTX 50 / Blackwell | `120` |
| `rtx` | RTX 30, 40 and 50 in one image | `80;120` |

```bash
BREEZE_GPU=rtx40 bash docker/build.sh
```

Setting `FLASH_ATTN_CUDA_ARCHS` directly overrides the profile. FlashAttention
2.8.3 only accepts `80`, `90`, `100` and `120`; the script rejects anything else
(such as `86` or `89`) because FlashAttention would silently skip it. sm_80
kernels run on all Ampere and Ada GPUs. Set `BREEZE_BUILD_DRY_RUN=1` to print the
`docker build` command without running it.

Run with a local model directory:

```bash
bash docker/run.sh /path/to/breeze-model \
  --fast-all
```

`run.sh` publishes the API on port 7860 of every host interface. Set
`BREEZE_BIND_ADDR` to one host address (for example this machine's LAN IP) to
publish only there. See [the RTX guide](../docs/rtx-lan-server.md) for LAN-only
setups on Linux and Windows.

The model is mounted read-only and is never copied into the image. The build
runs an import/version smoke check and the CPU-safe core unit tests. GPU graph
capture happens only when fast stages are explicitly enabled on an NVIDIA GPU.
