# NeuraForge - High-Performance C++20 Neural Inference Engine
# Multi-stage production Docker build

# ==========================================
# Base Stage - Common dependencies
# ==========================================
FROM ubuntu:22.04 AS base
ENV DEBIAN_FRONTEND=nointeractive

# Common runtime dependencies
RUN apt-get update && apt-get install -y \
  ca-certificates \
  curl \
  libgomp1 \
  libstdc++6 \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean

# ==========================================
# Builder Stage - Compile the application
# ==========================================
FROM base AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
  build-essential \
  cmake \
  ninja-build \
  git \
  curl \
  zip \
  unzip \
  tar \
  pkg-config \
  wget \
  && rm -rf /var/lib/apt/lists/*

ENV VCPKG_ROOT=/opt/vcpkg
RUN git clone https://github.com/Microsoft/vcpkg.git ${VCPKG_ROOT} \
  && ${VCPKG_ROOT}/bootstrap-vcpkg.sh \
  && chmod +x ${VCPKG_ROOT}/vcpkg

# Environment setup
WORKDIR /src
COPY vcpkg.json vcpkg-configuration.json ./

RUN ${VCPKG_ROOT}/vcpkg install --triplet=x64-linux --clean-after-build
COPY . .

RUN cmake --preset=release-linux \
  -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
  -DBUILD_TESTS=OFF \
  -DBUILD_BENCHMARKS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="-O3 -march=x86-64 -mtune=generic -DNDEBUG"

RUN cmake --build --preset=release-linux --parallel $(nproc)
RUN find build/release/bin -type f -executable -exec strip {} \; || true

# ==========================================
# Runtime Stage - Minimal prod image
# ==========================================
FROM base AS runtime

# Environment setup
RUN groupadd -r neuraforge && \
  useradd -r -g neuraforge -s /bin/false neuraforge

RUN mkdir -p /app/bin /app/lib /app/models /app/logs /app/config && \
  chown -R neuraforge:neuraforge /app

COPY --from=builder --chown=neuraforge:neuraforge /src/build/release/bin/neuraforge /app/bin/

RUN mkdir -p /tmp/lib-check
COPY --from=builder /src/build/release/lib/ /tmp/lib-check/ 
RUN if [ "$(ls -A /tmp/lib-check 2>/dev/null)" ]; then \
  cp -r /tmp/lib-check/* /app/lib/ && \
  chown -R neuraforge:neuraforge /app/lib; \
  fi && \
  rm -rf /tmp/lib-check

RUN echo "/app/lib" > /etc/ld.so.conf.d/neuraforge.conf && ldconfig
ENV PATH="/app/bin:${PATH}" \
  LD_LIBRARY_PATH="/app/lib:${LD_LIBRARY_PATH}" \
  NEURAFORGE_MODEL_PATH="/app/models" \
  NEURAFORGE_LOG_PATH="/app/logs" \
  NEURAFORGE_LOG_LEVEL="info" \
  NEURAFORGE_CONFIG_PATH="/app/config"

USER neuraforge
WORKDIR /app

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

CMD ["neuraforge", "--server", "--host=0.0.0.0", "--port=8080"]

# ==========================================
# Development Stage - Full dev environment
# ==========================================
FROM builder AS development

# Install additional development tools
RUN apt-get update && apt-get install -y \
  gdb \
  valgrind \
  strace \
  ltrace \
  clang-tidy \
  clang-format \
  cppcheck \
  ccache \
  perf-tools-unstable \
  htop \
  vim \
  nano \
  tree \
  && rm -rf /var/lib/apt/lists/*

# Debug Environment Setup
RUN cmake --preset=debug \
  -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
  -DBUILD_TESTS=ON \
  -DBUILD_BENCHMARKS=ON \
  -DENABLE_SANITIZERS=ON \
  -DENABLE_COVERAGE=ON

RUN cmake --build --preset=debug --parallel $(nproc)
ENV CMAKE_BUILD_TYPE=Debug \
  ASAN_OPTIONS="detect_leaks=1:abort_on_error=1:check_initialization_order=1" \
  UBSAN_OPTIONS="print_stacktrace=1:abort_on_error=1" \
  VCPKG_ROOT=/opt/vcpkg

WORKDIR /src
CMD ["/bin/bash"]

# ==========================================
# Benchmark Stage - Performance testing
# ==========================================
FROM runtime AS benchmark

# Install benchmarking tools (as root temporarily)
USER root
RUN apt-get update && apt-get install -y \
  linux-perf \
  htop \
  iotop \
  stress-ng \
  sysbench \
  && rm -rf /var/lib/apt/lists/*

# Copy benchmark binary if it exists
RUN if [ -f "/src/build/release/bin/neuraforge_benchmarks" ]; then \
  cp /src/build/release/bin/neuraforge_benchmarks /app/bin/ && \
  chown neuraforge:neuraforge /app/bin/neuraforge_benchmarks; \
  fi

# Switch back to non-root user
USER neuraforge
ENV NEURAFORGE_BENCHMARK_ITERATIONS=1000 \
  NEURAFORGE_BENCHMARK_WARMUP=100 \
  NEURAFORGE_BENCHMARK_OUTPUT="/app/logs"

RUN echo '#!/bin/bash\n\
  if [ -f "/app/bin/neuraforge_benchmarks" ]; then\n\
  /app/bin/neuraforge_benchmarks --benchmark_format=json --benchmark_out=/app/logs/benchmark_results.json\n\
  else\n\
  echo "Benchmark binary not found, running regular inference tests..."\n\
  /app/bin/neuraforge --benchmark --iterations=${NEURAFORGE_BENCHMARK_ITERATIONS}\n\
  fi' > /app/bin/run_benchmarks.sh && \
  chmod +x /app/bin/run_benchmarks.sh

CMD ["/app/bin/run_benchmarks.sh"]

# ==========================================
# Testing Stage - For CI/CD Testing
# ==========================================
FROM development AS testing

# Run tests during build 
RUN cd /src && ctest --preset=debug --output-on-failure || true
ENV CTEST_OUTPUT_ON_FAILURE=1 \
  GTEST_COLOR=1

CMD ["ctest", "--preset=debug", "--verbose"]

# ================================================
# Security Scan Stage - Vulnerability assessment
# ================================================
FROM runtime AS security-scan

# Install dependencies sca
USER root
RUN apt-get update && apt-get install -y \
  clamav \
  rkhunter \
  && rm -rf /var/lib/apt/lists/*

USER neuraforge
CMD ["echo", "Security scan stage - integrate with your security tools"]

# ==========================================
# Labels and Metadata
# ==========================================
LABEL maintainer="NeuraForge Team <team@neuraforge.ai>" \
  version="1.0.0" \
  description="High-performance C++20 neural inference engine with multi-stage builds" \
  org.opencontainers.image.title="NeuraForge" \
  org.opencontainers.image.description="Blazing fast PyTorch model inference with modern C++20 features" \
  org.opencontainers.image.version="1.0.0" \
  org.opencontainers.image.vendor="NeuraForge" \
  org.opencontainers.image.licenses="MIT" \
  org.opencontainers.image.source="https://github.com/your-org/neuraforge" \
  org.opencontainers.image.documentation="https://neuraforge.readthedocs.io" \
  org.opencontainers.image.created="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  org.opencontainers.image.authors="NeuraForge Development Team"