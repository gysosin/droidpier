FROM ubuntu:22.04@sha256:2edbbc5dc405e9612ba3584ce95480277e3eb374407b5505fe26f17df77c7dbc
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev \
    curl ca-certificates git python3 xz-utils zip unzip build-essential nasm \
    patchelf dpkg-dev rpm file libfuse2 libglu1-mesa xvfb xauth \
    libprotobuf-dev protobuf-compiler libbrotli-dev liblz4-dev libzstd-dev \
    libpcre2-dev zlib1g-dev libgtest-dev patch \
    && rm -rf /var/lib/apt/lists/*
ARG BUILD_UID=1000
RUN useradd --create-home --uid ${BUILD_UID} builder
USER builder
WORKDIR /workspace
