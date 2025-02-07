FROM ubuntu:latest

# Common C++ dev tools
RUN apt-get update && apt-get install -y \
  bash-completion \
  build-essential \
  clangd \
  clang-format \
  clang-tidy \
  git \
  libeigen3-dev \
  cmake \
  rsync \
  gcc-arm-none-eabi \
  g++-13-aarch64-linux-gnu \
  libpcl-dev \
  libgtest-dev \
  libgmock-dev \
  libomp-dev \
  libi2c-dev \
  gdb && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
# gRPC
RUN cd /tmp && git clone --recurse-submodules -b v1.66.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc && \
  mkdir -p /tmp/grpc/build && cd /tmp/grpc/build && \
  cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF .. && \
  make -j8 install && \
  if [ $TARGETARCH != "arm64" ]; then \
  rm -rf * && \
  cmake -DgRPC_INSTALL=ON \
  -DgRPC_BUILD_TESTS=OFF \
  -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc-13 \
  -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++-13 \
  -DCMAKE_INSTALL_PREFIX=/usr/local/aarch64 \
  -DCMAKE_SYSTEM_NAME=Linux .. && \
  make -j8 install; \
  fi && \
  rm -rf /tmp/grpc

COPY toolchains/ /opt/toolchains