# Use arm64 
FROM debian:trixie-slim

ARG TOOLCHAIN_FILE=/opt/toolchains/arm64-generic.cmake
ARG SKIP_TARGET_BUILD=false

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_WORKERS=6

ENV PIP_ROOT_USER_ACTION=ignore
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Common C++ dev tools
RUN dpkg --add-architecture arm64 && apt-get update && apt-get install -y \
  build-essential \
  clangd \
  clang-format \
  clang-tidy \
  git \
  libeigen3-dev \
  cmake \
  gcc-arm-none-eabi \
  libflann-dev \
  libjsoncpp-dev \
  libgtest-dev \
  libgmock-dev \
  libboost-dev \
  libboost-iostreams-dev \
  libi2c-dev \
  python3 \
  gdb \
  # ARM64
  crossbuild-essential-arm64 \
  libboost-iostreams-dev:arm64 && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

COPY toolchains/ /opt/toolchains

# PCL (Point Cloud Library)
RUN cd /tmp && git clone -b pcl-1.15.1 https://github.com/PointCloudLibrary/pcl.git && \
  mkdir -p /tmp/pcl/build && cd /tmp/pcl/build && \
  cmake \
    -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE} \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_OPENGL=OFF -DWITH_VTK=OFF \ 
    -DBUILD_keypoints=OFF -DBUILD_segmentation=OFF -DBUILD_surface=OFF \ 
    -DBUILD_visualization=OFF -DBUILD_recognition=OFF -DBUILD_ml=OFF \ 
    -DBUILD_registration=OFF -DBUILD_tools=OFF -DBUILD_tracking=OFF -DBUILD_stereo=OFF .. && \
  make -j${BUILD_WORKERS} install && \
  rm -rf /tmp/pcl

# gRPC
# Build a native (host) gRPC first to produce grpc_cpp_plugin, then
# perform the cross/target build using the configured toolchain file.
# TODO if native build, no need to re-build for target
RUN cd /tmp && git clone --recurse-submodules -b v1.72.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc && \
  mkdir -p /tmp/grpc/build_host && cd /tmp/grpc/build_host && \
  cmake \
    -DgRPC_INSTALL=ON \
    -DgRPC_BUILD_TESTS=OFF \
    -DCMAKE_BUILD_TYPE=Release .. && \
  make -j${BUILD_WORKERS} install && \
  # If SKIP_TARGET_BUILD is true we are doing a native build and can stop here.
  if [ "${SKIP_TARGET_BUILD}" = "true" ]; then \
    rm -rf /tmp/grpc && ldconfig; \
  else \
    # now build for the target (using the toolchain file). The host-installed
    # grpc_cpp_plugin will be found in PATH and used to generate protobuf/grpc sources
    rm -rf /tmp/grpc/build_host && \
    mkdir -p /tmp/grpc/build && cd /tmp/grpc/build && \
    cmake \
      -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE} \
      -DgRPC_INSTALL=ON \
      -DgRPC_BUILD_TESTS=OFF \
      -DCMAKE_BUILD_TYPE=Release .. && \
    make -j${BUILD_WORKERS} install && \
    rm -rf /tmp/grpc && ldconfig; \
  fi
