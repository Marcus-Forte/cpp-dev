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
  libflann-dev \
  libjsoncpp-dev \
  libomp-dev \
  libgtest-dev \
  libgmock-dev \
  libboost-all-dev \
  libi2c-dev \
  gdb && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
# PCL
RUN cd /tmp && git clone -b pcl-1.15.0 https://github.com/PointCloudLibrary/pcl.git && \
  mkdir -p /tmp/pcl/build && cd /tmp/pcl/build && \
  cmake -DCMAKE_BUILD_TYPE=Release -DWITH_OPENGL=OFF -DWITH_VTK=OFF \ 
  -DBUILD_keypoints=OFF -DBUILD_segmentation=OFF -DBUILD_surface=OFF \ 
  -DBUILD_visualization=oFF -DBUILD_recognition=OFF -DBUILD_ml=off \ 
  -DBUILD_registration=off -DBUILD_tools=OFF -DBUILD_tracking=OFF -DBUILD_stereo=OFF .. && \
  make -j4 install && \
  rm -rf /tmp/pcl

# gRPC
RUN cd /tmp && git clone --recurse-submodules -b v1.72.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc && \
  mkdir -p /tmp/grpc/build && cd /tmp/grpc/build && \
  cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release .. && \
  make -j8 install && \
  if [ $TARGETARCH != "arm64" ]; then \
  rm -rf * && \
  cmake -DgRPC_INSTALL=ON \
  -DgRPC_BUILD_TESTS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc-13 \
  -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++-13 \
  -DCMAKE_INSTALL_PREFIX=/usr/local/aarch64 \
  -DCMAKE_SYSTEM_NAME=Linux .. && \
  make -j8 install; \
  fi && \
  rm -rf /tmp/grpc

COPY toolchains/ /opt/toolchains