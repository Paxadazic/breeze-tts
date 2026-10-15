#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image_tag="${BREEZE_IMAGE:-breeze-pytorch-infer:latest}"
gpu_target="${BREEZE_GPU:-h100}"

# FlashAttention 2.8.3 only recognizes these exact values in FLASH_ATTN_CUDA_ARCHS.
# Any other value (for example 86 or 89) is silently ignored and leaves the
# extension without kernels for that GPU. An sm_80 build runs on every Ampere
# and Ada card (sm_80, sm_86, sm_87, sm_89).
supported_archs=" 80 90 100 120 "

case "$gpu_target" in
  h100 | hopper) profile_archs="90" ;;
  a100) profile_archs="80" ;;
  rtx30 | ampere) profile_archs="80" ;;
  rtx40 | ada) profile_archs="80" ;;
  rtx50 | blackwell) profile_archs="120" ;;
  rtx) profile_archs="80;120" ;;
  *)
    echo "unknown BREEZE_GPU '$gpu_target'" >&2
    echo "expected one of: h100, a100, rtx30, rtx40, rtx50, rtx (RTX 30/40/50 in one image)" >&2
    exit 2
    ;;
esac

flash_attn_cuda_archs="${FLASH_ATTN_CUDA_ARCHS:-$profile_archs}"

IFS=';' read -r -a requested_archs <<< "$flash_attn_cuda_archs"
if [[ ${#requested_archs[@]} -eq 0 ]]; then
  echo "FLASH_ATTN_CUDA_ARCHS is empty" >&2
  exit 2
fi
for arch in "${requested_archs[@]}"; do
  if [[ "$supported_archs" != *" $arch "* ]]; then
    echo "unsupported FLASH_ATTN_CUDA_ARCHS entry '$arch'; use 80, 90, 100 or 120 separated by ';'" >&2
    echo "Ampere and Ada cards (RTX 30/40, sm_86/sm_89) use 80; RTX 50 (sm_120) uses 120" >&2
    exit 2
  fi
done

build_cmd=(
  docker build
  --file "$repo_dir/docker/Dockerfile"
  --tag "$image_tag"
  --build-arg "FLASH_ATTN_CUDA_ARCHS=$flash_attn_cuda_archs"
  "$repo_dir"
)

if [[ "${BREEZE_BUILD_DRY_RUN:-0}" == "1" ]]; then
  printf '%q ' "${build_cmd[@]}"
  printf '\n'
  exit 0
fi

exec "${build_cmd[@]}"
