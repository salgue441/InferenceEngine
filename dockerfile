FROM ubuntu:22.04 AS base
ENV DEBIAN_FRONTEND=nointeractive

# System dependencies
RUN apt-get update && apt-get install -y \
  wget \
  curl \
  unzip \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# === Build Stage ===
FROM base AS builder

# Install build depedencies
RUN apt-get update && apt-get install -y \
  build-essential \
  cmake \
  git \
  pkg-config \
  libomp-dev \
  python3 \
  python3-pip \
  && rm -rf /var/lib/apt/lists/*

# LibTorch configuration
WORKDIR /opt
RUN wget https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-2.1.0%2Bcpu.zip \
  && unzip libtorch-cxx11-abi-shared-with-deps-2.1.0+cpu.zip \
  && rm libtorch-cxx11-abi-shared-with-deps-2.1.0+cpu.zip

ENV CMAKE_PREFIX_PATH=/opt/libtorch

# Copy Source Code
COPY . /app
WORKDIR /app

# Create build directory and compile
RUN mkdir -p build && cd build && \
  cmake -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/opt/libtorch \
  .. && \
  make -j$(nproc)

# === Runtime Stage ===
FROM base AS runtime

# Runtime dependencies
RUN apt-get update && apt-get install -y \
  libomp5 \
  libgomp1 \
  && rm -rf /var/lib/apt/lists/*

# Copy LibTorch libraries
COPY --from=builder /opt/libtorch/lib /usr/local/lib
COPY --from=builder /opt/libtorch/include /usr/local/include

# Copy the built application
COPY --from=builder /app/build/inference_engine /usr/local/bin/inference_engine

# Copy configuration and model directories
COPY --from=builder /app/build/config /app/config
COPY --from=builder /app/build/models /app/models

# Non-root user
RUN useradd -m -u 1000 inference && \
  chown -R inference:inference /app

USER inference
WORKDIR /app

# Update library path
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Health Check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Port and Default Command
EXPOSE 8080
CMD ["inference_engine", "--config", "/app/config/server.json"]
