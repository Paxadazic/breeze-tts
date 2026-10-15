#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 MODEL_PATH [API arguments...]" >&2
  exit 2
fi

model_path="$1"
shift
image_tag="${BREEZE_IMAGE:-breeze-pytorch-infer:latest}"
# Host address to publish the API on. Empty publishes on every host interface;
# set it to this machine's LAN IP to keep the port off other networks.
bind_addr="${BREEZE_BIND_ADDR:-}"
publish="7860:7860"
if [[ -n "$bind_addr" ]]; then
  publish="$bind_addr:7860:7860"
fi

docker run --rm --gpus all \
  --ipc=host \
  --publish "$publish" \
  --volume "$model_path:/models/breeze:ro" \
  "$image_tag" \
  python -m breeze_infer.api /models/breeze \
    --host 0.0.0.0 \
    --port 7860 \
    "$@"
