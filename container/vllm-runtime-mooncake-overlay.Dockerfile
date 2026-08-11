# syntax=docker/dockerfile:1
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Thin overlay Dockerfile that installs the Mooncake transfer-engine wheel on top
# of an already-built Dynamo vLLM runtime image without rebuilding the ~20GB base.
# The wheel ships the `mooncake_master` binary and the store client used for
# PD-disaggregated serving. Assumes a system-Python base (vLLM et al. under
# /usr/local/lib/python3.12/dist-packages); pulls the cp312 / CUDA-13 wheel from
# Mooncake's GitHub releases, installs the libnuma1 runtime prerequisite, and
# restores the unprivileged `dynamo` runtime user.
#
# Build (tag encodes dynamo / cuda / vllm / mooncake versions):
#   docker build --platform linux/amd64 \
#     -f container/vllm-runtime-mooncake-overlay.Dockerfile \
#     --build-arg BASE=hub.fci.vn/ncp-modas/containers/mx-vllm-runtime:1.4.0-rc-cu130-vllm0260 \
#     -t hub.fci.vn/ncp-modas/containers/dynamo-vllm-runtime:1.4.0-cu130-vllm0.26.0-mc0.3.11.post1 .
#
# To pin a different Mooncake release, override --build-arg MOONCAKE_WHEEL=<url>.
ARG BASE
FROM ${BASE}

USER root

ARG MOONCAKE_WHEEL=https://github.com/kvcache-ai/Mooncake/releases/download/v0.3.11.post1/mooncake_transfer_engine_cuda13-0.3.11.post1-cp312-cp312-manylinux_2_35_x86_64.whl

RUN apt-get update \
 && apt-get install -y --no-install-recommends libnuma1 \
 && rm -rf /var/lib/apt/lists/* \
 && pip uninstall -y mooncake-transfer-engine mooncake-transfer-engine-cuda13 2>/dev/null || true \
 && ( pip install --no-cache-dir "${MOONCAKE_WHEEL}" \
      || pip install --no-cache-dir --break-system-packages "${MOONCAKE_WHEEL}" )

USER dynamo
