FROM gcc:15.2.0-trixie

# 1. Define Build Arguments with defaults for your "Standard" ARM target
# You can override this at build time (e.g., for native builds)
ARG TARGET_CXX_FLAGS="-O3"

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_WORKERS=6

# Fix gfortran link in the base image
RUN ln -s /usr/bin/gfortran-14 /usr/bin/gfortran

# Common C++ dev tools
RUN apt-get update && apt-get install -y \
  clangd \
  clang-format \
  clang-tidy \
  git \
  libeigen3-dev \
  cmake \
  gcc-arm-none-eabi \
  libflann-dev \
  libjsoncpp-dev \
  libomp-dev \
  libgtest-dev \
  libgmock-dev \
  libboost-all-dev \
  libi2c-dev \
  python3-venv \
  gdb && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Automatic Docker Argument to detect host architecture
ARG TARGETARCH

# PCL
# This builds PCL specifically for the TARGET architecture defined by the ARGs.
RUN cd /tmp && git clone -b pcl-1.15.1 https://github.com/PointCloudLibrary/pcl.git && \
  mkdir -p /tmp/pcl/build && cd /tmp/pcl/build && \
  cmake \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="${TARGET_CXX_FLAGS}" \
    -DWITH_OPENGL=OFF -DWITH_VTK=OFF \ 
    -DBUILD_keypoints=OFF -DBUILD_segmentation=OFF -DBUILD_surface=OFF \ 
    -DBUILD_visualization=oFF -DBUILD_recognition=OFF -DBUILD_ml=off \ 
    -DBUILD_registration=off -DBUILD_tools=OFF -DBUILD_tracking=OFF -DBUILD_stereo=OFF .. && \
  make -j${BUILD_WORKERS} install && \
  rm -rf /tmp/pcl

# gRPC
# 1. First, we always build the HOST version (native to the container)
#    This is required because gRPC needs native plugins (grpc_cpp_plugin) to build the target version.
RUN cd /tmp && git clone --recurse-submodules -b v1.72.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc && \
  mkdir -p /tmp/grpc/build_host && cd /tmp/grpc/build_host && \
  cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release .. && \
  make -j${BUILD_WORKERS} install && \
  # 2. Clean up and build for the TARGET (using the ARGs)
  rm -rf * && \
  cmake \
    -DgRPC_INSTALL=ON \
    -DgRPC_BUILD_TESTS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="${TARGET_CXX_FLAGS}" \
    -DCMAKE_SYSTEM_NAME=Linux .. && \
  make -j${BUILD_WORKERS} install && \
  rm -rf /tmp/grpc

COPY toolchains/ /opt/toolchains