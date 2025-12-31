FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_WORKERS=6

ENV MAIN_TOOLCHAIN_FILE=/opt/toolchains/native.cmake

# Common C++ dev tools and libraries
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
  curl \
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

# OpenCV Stack
RUN apt-get update && apt-get install -y \
  wget \
  unzip \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# OpenCv
RUN cd /tmp && wget -O opencv.zip https://github.com/opencv/opencv/archive/4.x.zip && \
  unzip opencv.zip && \
  mkdir opencv-4.x/build && cd opencv-4.x/build && \
  cmake  \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE=${MAIN_TOOLCHAIN_FILE} \
  -DBUILD_TESTS=OFF \
  -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_opencv_apps=OFF \
  -DWITH_GSTREAMER=ON .. && \
  cmake --build . -j${BUILD_WORKERS} && cmake --install . && \
  rm -r /tmp/opencv-4.x

# RPI Camera SDK (TODO, make it optional?)
RUN apt-get update && apt-get install -y \
    git \
    # libcamera dependencies
    python3-pip python3-jinja2 \
    libboost-dev \
    libgnutls28-dev openssl libtiff5-dev pybind11-dev \
    meson cmake \
    python3-yaml python3-ply \
    libglib2.0-dev libgstreamer-plugins-base1.0-dev \
    # rpicam-apps dependencies
    libboost-program-options-dev libdrm-dev libexif-dev \
    libpng-dev libjpeg-dev \
    ninja-build \
    # GStreamer development packages
    libgstreamer1.0-dev \
    gstreamer1.0-tools && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Build and install libcamera
RUN cd /tmp && git clone https://github.com/raspberrypi/libcamera.git && \
    cd libcamera && \
    meson setup build \
    --buildtype=release \
    -Dpipelines=rpi/vc4,rpi/pisp \
    -Dipas=rpi/vc4,rpi/pisp \
    -Dv4l2=true -Dgstreamer=enabled \
    -Dtest=false -Dlc-compliance=disabled \
    -Dcam=disabled -Dqcam=disabled \
    -Ddocumentation=disabled \
    -Dpycamera=enabled && \
    ninja -C build && \
    ninja -C build install && \
    rm -r /tmp/libcamera && \
    ldconfig


RUN cd /tmp && git clone https://github.com/raspberrypi/rpicam-apps.git && \
    cd rpicam-apps && \
    meson setup build \
    -Denable_libav=disabled \
    -Denable_drm=enabled \
    -Denable_egl=disabled \
    -Denable_qt=disabled \
    -Denable_opencv=disabled \
    -Denable_tflite=disabled \
    -Denable_hailo=disabled && \
    meson compile -C build && \
    meson install -C build && \
    rm -r /tmp/rpicam-apps && \
    ldconfig

ENV GST_PLUGIN_PATH=/usr/local/lib/aarch64-linux-gnu/gstreamer-1.0:/usr/local/lib/gstreamer-1.0