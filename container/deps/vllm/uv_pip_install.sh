#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# `uv pip install` that targets whatever Python environment the runtime base
# ships, so the same Dockerfile works on a system-Python cuda base and on a
# cuda base that ships vLLM in a venv:
#
#   - VIRTUAL_ENV active     -> install into that venv (no flag)
#   - /opt/venv present      -> install into it via --python (PATH-only
#                               activation, e.g. lmcache/vllm-openai which
#                               leaves VIRTUAL_ENV unset)
#   - otherwise              -> --system (official vllm/vllm-openai system Python)
#
# The system-Python path is byte-for-byte the previous `uv pip install --system`
# behavior, so official cuda builds are unchanged.
set -euo pipefail

if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "${VIRTUAL_ENV}/bin/python" ]; then
    exec uv pip install "$@"
elif [ -x /opt/venv/bin/python ]; then
    exec uv pip install --python /opt/venv/bin/python "$@"
else
    exec uv pip install --system "$@"
fi
