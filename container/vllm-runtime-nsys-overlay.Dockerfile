# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Thin overlay: add the Nsight Systems (nsys) profiler CLI on top of an
# already-built Dynamo vLLM runtime image, WITHOUT rebuilding the 20GB base.
#
# The runtime image (vllm/vllm-openai based, Ubuntu 24.04, user `dynamo`)
# ships no profiler. This layer pulls nsys from NVIDIA's official devtools
# apt repo -- the same source and version used by container/templates/dev.Dockerfile.
#
# Build (base already built locally as mx-vllm-runtime:1.3.0-pd-disagg):
#   docker build --platform linux/amd64 \
#     -f container/vllm-runtime-nsys-overlay.Dockerfile \
#     --build-arg BASE=hub.fci.vn/ncp-modas/containers/mx-vllm-runtime:1.3.0-pd-disagg \
#     -t hub.fci.vn/ncp-modas/containers/mx-vllm-runtime:1.3.0-pd-disagg-nsys .
#
# Profile at runtime, e.g.:
#   nsys profile -o /workspace/report -t cuda,nvtx,osrt python -m dynamo.vllm ...
# ---------------------------------------------------------------------------
ARG BASE=hub.fci.vn/ncp-modas/containers/mx-vllm-runtime:1.3.0-pd-disagg
FROM ${BASE}

# nsys install needs root; the base runs as unprivileged `dynamo`.
USER root
ARG TARGETARCH=amd64

RUN mkdir -p /etc/apt/keyrings && \
    apt-get update && \
    apt-get install -y --no-install-recommends wget gnupg ca-certificates && \
    wget -qO - "https://developer.download.nvidia.com/devtools/repos/ubuntu2404/${TARGETARCH}/nvidia.pub" \
        | gpg --dearmor -o /etc/apt/keyrings/nvidia-devtools.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nvidia-devtools.gpg] https://developer.download.nvidia.com/devtools/repos/ubuntu2404/${TARGETARCH} /" \
        > /etc/apt/sources.list.d/nvidia-devtools.list && \
    apt-get update && \
    # CLI-only build keeps the layer small; fall back to the full meta package.
    (apt-get install -y --no-install-recommends nsight-systems-cli-2025.5.1 || \
     apt-get install -y --no-install-recommends nsight-systems-2025.5.1) && \
    rm -rf /var/lib/apt/lists/* && \
    # Resolve the REAL binary (not the update-alternatives symlink the package
    # may have already put in /usr/local/bin) and point nsys at it on PATH.
    NSYS_BIN=$(find /opt/nvidia -maxdepth 6 -type f -name nsys -executable 2>/dev/null | head -n1) && \
    test -n "$NSYS_BIN" && ln -sf "$NSYS_BIN" /usr/local/bin/nsys && \
    nsys --version

# Under nsys, Dynamo's NVTX annotations pass named colors (e.g. "magenta"),
# which the `nvtx` package can only resolve to hex when matplotlib is present.
# The vllm/vllm-openai base ships no matplotlib, so importing dynamo.vllm dies
# with "Invalid color magenta". Install it into the same interpreter as vLLM.
RUN pip install --no-cache-dir matplotlib || \
    pip install --no-cache-dir --break-system-packages matplotlib

# Restore the unprivileged runtime user baked into the base image.
USER dynamo
