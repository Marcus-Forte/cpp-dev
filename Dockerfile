FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_WORKERS=6

ENV PIP_ROOT_USER_ACTION=ignore
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV MAIN_TOOLCHAIN_FILE=/opt/toolchains/native.cmake

# Common C++ dev tools (native builds only)
RUN apt-get update && apt-get install -y \
  build-essential \
  clangd \
  clang-format \
  clang-tidy \
  git \
  libeigen3-dev \
  cmake \
  gcc-arm-none-eabi \
  libnanoflann-dev \
  libjsoncpp-dev \
  libgtest-dev \
  libgmock-dev \
  libboost-all-dev \
  libi2c-dev \
  plantuml \
  gdb && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Install `uv` for python.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

COPY ./toolchains /opt/toolchains

# PCL (Point Cloud Library)
RUN cd /tmp && git clone -b pcl-1.15.1 https://github.com/PointCloudLibrary/pcl.git && \
  mkdir -p /tmp/pcl/build && cd /tmp/pcl/build && \
  cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=${MAIN_TOOLCHAIN_FILE} \
    -DWITH_OPENGL=OFF -DWITH_VTK=OFF \
    -DBUILD_keypoints=OFF -DBUILD_segmentation=OFF -DBUILD_surface=OFF \
    -DBUILD_visualization=OFF -DBUILD_recognition=OFF -DBUILD_ml=OFF \
    -DBUILD_registration=OFF -DBUILD_tools=OFF -DBUILD_tracking=OFF -DBUILD_stereo=OFF .. && \
  make -j${BUILD_WORKERS} install && \
  rm -rf /tmp/pcl

# gRPC
RUN cd /tmp && git clone --recurse-submodules -b v1.76.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc && \
  mkdir -p /tmp/grpc/build && cd /tmp/grpc/build && \
  cmake \
    -DgRPC_INSTALL=ON \
    -DCMAKE_TOOLCHAIN_FILE=${MAIN_TOOLCHAIN_FILE} \
    -DgRPC_BUILD_TESTS=OFF \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_BUILD_TYPE=Release .. && \
  make -j${BUILD_WORKERS} install && \
  rm -rf /tmp/grpc
