# Running the API server on a consumer RTX PC

This guide runs the streaming API on a desktop with a GeForce RTX card and
makes it reachable from other machines on the same local network only. The API
has no authentication, so it must never be exposed to the internet.

## 1. Pick the build target

FlashAttention is compiled for specific GPU architectures. Choose the profile
that matches your card with `BREEZE_GPU`:

| Card | Architecture | `BREEZE_GPU` | Compiled for |
| --- | --- | --- | --- |
| RTX 3060 to 3090 | Ampere (sm_86) | `rtx30` | sm_80 |
| RTX 4060 to 4090 | Ada (sm_89) | `rtx40` | sm_80 |
| RTX 5060 to 5090 | Blackwell (sm_120) | `rtx50` | sm_120 |
| Any of the above | mixed | `rtx` | sm_80 and sm_120 |

```bash
BREEZE_GPU=rtx40 bash docker/build.sh
```

RTX 30 and 40 cards use the sm_80 build because sm_80 kernels run on every
Ampere and Ada GPU. FlashAttention 2.8.3 ignores values such as `86` or `89`, so
`docker/build.sh` rejects them instead of producing an image with no kernels for
your card. `BREEZE_GPU=rtx` builds one image that works on RTX 30, 40 and 50 at
the cost of a longer compile. RTX 20 (Turing) cards are not supported by
FlashAttention 2.

The build compiles FlashAttention from source and can take a long time on a
desktop CPU. If it runs out of memory, lower parallelism by editing `MAX_JOBS`
in `docker/Dockerfile` (for example `MAX_JOBS=4`).

`FLASH_ATTN_CUDA_ARCHS` still works and overrides the profile, for example
`FLASH_ATTN_CUDA_ARCHS="80;120" bash docker/build.sh`.

## 2. Choose the mode for your VRAM

| VRAM | Example cards | Mode |
| --- | --- | --- |
| 8 GB | RTX 3070, 4060 | Not recommended; eager inference needs about 7.7 GiB |
| 12 GB | RTX 3060 12 GB, 4070, 5070 | Eager (default, no extra flags) |
| 16 GB | RTX 4060 Ti 16 GB, 4080, 5080 | Eager, or `--fast-all` if no other GPU apps are running |
| 24 GB or more | RTX 3090, 4090, 5090 | `--fast-all` |

Eager inference uses about 7.7 GiB and `--fast-all` about 14.4 GiB. On a PC that
also drives a display, Windows and the desktop take part of the VRAM, so leave
headroom. `--fast-all` adds a warmup at startup in exchange for much lower
latency per request. The batch endpoint needs more memory as the batch grows, so
start with small batches on 12 GB cards.

## 3. Run it

### Linux

Install the NVIDIA driver and the NVIDIA Container Toolkit, then:

```bash
BREEZE_BIND_ADDR=192.168.1.50 bash docker/run.sh /path/to/breeze-tts-2           # 12 GB
BREEZE_BIND_ADDR=192.168.1.50 bash docker/run.sh /path/to/breeze-tts-2 --fast-all # 24 GB
```

Replace `192.168.1.50` with this PC's LAN address (`ip -4 addr`). Inside the
container the server always listens on `0.0.0.0:7860`; `BREEZE_BIND_ADDR`
controls which host address Docker publishes it on. Without it Docker publishes
on every interface, and Docker's published ports bypass `ufw`, so a `ufw` rule
alone does not restrict them.

### Windows with Docker Desktop

1. Install the latest NVIDIA Game Ready or Studio driver on Windows. Do not
   install a Linux driver inside WSL.
2. Install Docker Desktop with the WSL 2 backend. GPU support is enabled by
   default; check it with
   `docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi`.
3. Clone this repository inside your WSL distribution (for example
   `~/breeze-tts`, not under `/mnt/c`, which is much slower), then build and run
   from a WSL shell as on Linux. Leave `BREEZE_BIND_ADDR` unset or set it to the
   Windows PC's LAN address shown by `ipconfig`.
4. Allow the port from the local subnet only, in an elevated PowerShell:

   ```powershell
   New-NetFirewallRule -DisplayName "Breeze TTS (LAN)" -Direction Inbound `
     -Protocol TCP -LocalPort 7860 -RemoteAddress LocalSubnet -Profile Private -Action Allow
   ```

   Make sure your home network is set to the Private profile in Windows
   settings.

### Windows with WSL 2 and no Docker

Install the Windows NVIDIA driver, then in WSL install Python 3.10 or newer, the
requirements, and FlashAttention with `FLASH_ATTN_CUDA_ARCHS` set as in step 1.
Start the server with:

```bash
python -m breeze_infer.api /path/to/breeze-tts-2 --host 0.0.0.0 --port 7860
```

WSL 2 uses NAT networking by default, so other PCs cannot reach the server. On
Windows 11, turn on mirrored networking by adding this to
`%UserProfile%\.wslconfig` and running `wsl --shutdown`:

```ini
[wsl2]
networkingMode=mirrored
```

Then add the firewall rule from the Docker Desktop section. Mirrored mode also
applies the Hyper-V firewall, which may need its own rule:

```powershell
New-NetFirewallHyperVRule -Name BreezeTTS -DisplayName "Breeze TTS (LAN)" -Direction Inbound `
  -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts 7860
```

## 4. Check it from the other PC

```bash
curl http://192.168.1.50:7860/health
curl -X POST http://192.168.1.50:7860/v1/audio/speech \
  -F "text=Hello from the RTX PC." \
  -F "instruction=Speak warmly and cheerfully." \
  --output hello.pcm
```

The response is mono 24 kHz signed 16-bit little-endian PCM. Play it with
`ffplay -f s16le -ar 24000 -ac 1 hello.pcm`.

## Keep it on the LAN

- Do not forward port 7860 on your router or enable UPnP for it.
- Only allow the local subnet in the firewall, as above.
- The server handles one request at a time and returns HTTP 409 while busy.
