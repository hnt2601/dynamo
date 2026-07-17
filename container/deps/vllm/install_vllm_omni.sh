#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2024-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

: "${VLLM_OMNI_REF:?VLLM_OMNI_REF must be set}"

VLLM_OMNI_PROTECTED_PACKAGES_FILE="${VLLM_OMNI_PROTECTED_PACKAGES_FILE:-/tmp/vllm_omni_protected_packages.txt}"

PROTECTED_CONSTRAINTS="$(mktemp /tmp/vllm-openai-protected.XXXXXX.txt)"
VLLM_OMNI_VERSION="${VLLM_OMNI_REF#v}"

cleanup() {
  rm -rf "${PROTECTED_CONSTRAINTS}"
}

trap cleanup EXIT

python3 - "${VLLM_OMNI_PROTECTED_PACKAGES_FILE}" <<'PY' > "${PROTECTED_CONSTRAINTS}"
import importlib.metadata as md
from pathlib import Path
import sys

for raw_line in Path(sys.argv[1]).read_text().splitlines():
    name = raw_line.strip()
    if not name or name.startswith("#"):
        continue
    try:
        dist = md.distribution(name)
    except Exception:
        continue
    project_name = dist.metadata.get("Name") or name
    print(f"{project_name}=={dist.version}")
PY

export VLLM_OMNI_TARGET_DEVICE

# Install vLLM-Omni into whatever Python environment the base provides, matching
# container/deps/vllm/uv_pip_install.sh:
#   - VIRTUAL_ENV active  -> install into that venv (CPU/XPU set VIRTUAL_ENV)
#   - /opt/venv present   -> a venv base that only activates via PATH and leaves
#                            VIRTUAL_ENV unset (e.g. lmcache/vllm-openai); target
#                            it explicitly so vLLM-Omni lands where vLLM lives
#   - otherwise + CUDA    -> --system (official vllm/vllm-openai system Python)
if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "${VIRTUAL_ENV}/bin/python" ]; then
  PIP_TARGET=()
elif [ -x /opt/venv/bin/python ]; then
  PIP_TARGET=(--python /opt/venv/bin/python)
elif [ "${VLLM_OMNI_TARGET_DEVICE}" = "cuda" ]; then
  PIP_TARGET=(--system)
else
  PIP_TARGET=()
fi

uv pip install "${PIP_TARGET[@]}" \
  --prerelease=allow \
  --constraints "${PROTECTED_CONSTRAINTS}" \
  "vllm-omni==${VLLM_OMNI_VERSION}"
