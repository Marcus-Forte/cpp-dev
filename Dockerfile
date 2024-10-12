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
  gcc-arm-none-eabi \
  libpcl-dev \
  libgtest-dev \
  libomp-dev \
  libi2c-dev \
  gdb && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# gRPC
RUN cd /tmp && git clone --recurse-submodules -b v1.66.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc && \
  mkdir -p /tmp/grpc/build && cd /tmp/grpc/build && \
  cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF .. && \
  make -j8 install && \
  rm -rf /tmp/grpc