from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

BUILD_SCRIPT = Path(__file__).resolve().parents[1] / "docker" / "build.sh"

pytestmark = pytest.mark.skipif(shutil.which("bash") is None, reason="bash is required")


def _run_build(**env_overrides: str) -> subprocess.CompletedProcess[str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if key not in {"BREEZE_GPU", "FLASH_ATTN_CUDA_ARCHS"}
    }
    env["BREEZE_BUILD_DRY_RUN"] = "1"
    env.update(env_overrides)
    return subprocess.run(
        ["bash", str(BUILD_SCRIPT)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _build_archs(result: subprocess.CompletedProcess[str]) -> str:
    assert result.returncode == 0, result.stderr
    for token in result.stdout.split():
        if token.startswith("FLASH_ATTN_CUDA_ARCHS="):
            return token.split("=", 1)[1].replace("\\;", ";")
    raise AssertionError(f"no FLASH_ATTN_CUDA_ARCHS build arg in {result.stdout!r}")


@pytest.mark.parametrize(
    ("gpu", "archs"),
    [
        (None, "90"),
        ("h100", "90"),
        ("a100", "80"),
        ("rtx30", "80"),
        ("rtx40", "80"),
        ("rtx50", "120"),
        ("rtx", "80;120"),
    ],
)
def test_gpu_profiles_select_flash_attention_archs(gpu: str | None, archs: str) -> None:
    overrides = {} if gpu is None else {"BREEZE_GPU": gpu}
    assert _build_archs(_run_build(**overrides)) == archs


def test_explicit_archs_override_the_profile() -> None:
    result = _run_build(BREEZE_GPU="rtx50", FLASH_ATTN_CUDA_ARCHS="80;90")
    assert _build_archs(result) == "80;90"


def test_unknown_gpu_profile_is_rejected() -> None:
    result = _run_build(BREEZE_GPU="rtx4090")
    assert result.returncode == 2
    assert "unknown BREEZE_GPU" in result.stderr


@pytest.mark.parametrize("archs", ["86", "89", "80;86", ";80"])
def test_archs_flash_attention_would_ignore_are_rejected(archs: str) -> None:
    result = _run_build(FLASH_ATTN_CUDA_ARCHS=archs)
    assert result.returncode == 2
