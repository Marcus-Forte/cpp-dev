FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG CMAKE_VERSION=4.4.2

# Common C++ dev tools and libraries
RUN echo "deb http://deb.debian.org/debian sid main" > /etc/apt/sources.list.d/sid.list && \
  apt-get update && \
  apt-get install -y -t sid g++-16 gcc-16 && \
  rm /etc/apt/sources.list.d/sid.list && \
  apt-get update && \
  apt-get install -y \
  clangd \
  clang-format \
  clang-tidy \
  git \
  libeigen3-dev \
  ninja-build \
  gcc \
  g++ \
  gcc-arm-none-eabi \
  libnanoflann-dev \
  libflann-dev \
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

# Install CMake binary
RUN arch="$(dpkg --print-architecture)" && \
  case "$arch" in \
    amd64) cmake_arch="x86_64" ;; \
    arm64) cmake_arch="aarch64" ;; \
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
  esac && \
  cmake_dir="cmake-${CMAKE_VERSION}-linux-${cmake_arch}" && \
  curl -fsSL "https://cmake.org/files/v${CMAKE_VERSION%.*}/${cmake_dir}.tar.gz" -o /tmp/${cmake_dir}.tar.gz && \
  tar -xzf /tmp/${cmake_dir}.tar.gz -C /opt && \
  ln -sf /opt/${cmake_dir}/bin/* /usr/local/bin/ && \
  rm -f /tmp/${cmake_dir}.tar.gz

# Install `uv` for python.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Cmake config
ARG CONF_PRESET=gcc-native
ARG BUILD_PRESET=build-native
ARG PRESET_FILE=/tmp/CMakePresets.json
ARG BUILD_WORKERS=6

COPY ./toolchains /opt/toolchains
COPY ./CMakePresets.json ${PRESET_FILE}

# PCL (Point Cloud Library)
RUN cd /tmp && git clone -b pcl-1.15.1 https://github.com/PointCloudLibrary/pcl.git && \
  cd /tmp/pcl && \
  cmake --presets-file ${PRESET_FILE} --preset ${CONF_PRESET} -DCMAKE_BUILD_TYPE=Release \
    -DWITH_OPENGL=OFF -DWITH_VTK=OFF \
    -DBUILD_keypoints=OFF -DBUILD_segmentation=OFF -DBUILD_surface=OFF -DBUILD_filters=ON \
    -DBUILD_visualization=OFF -DBUILD_recognition=OFF -DBUILD_ml=OFF -DBUILD_search=ON \
    -DBUILD_registration=OFF -DBUILD_tools=OFF -DBUILD_tracking=OFF -DBUILD_stereo=OFF && \
  cmake --build --presets-file ${PRESET_FILE} --preset ${BUILD_PRESET} -j${BUILD_WORKERS} && cmake --install build/native && \
  rm -rf /tmp/pcl

# gRPC
RUN cd /tmp && git clone --recurse-submodules -b v1.83.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc 

RUN cd /tmp/grpc && \
  cmake --presets-file ${PRESET_FILE} --preset ${CONF_PRESET} -DCMAKE_BUILD_TYPE=Release \
    -DgRPC_INSTALL=ON \
    -DgRPC_BUILD_TESTS=OFF && \
  cmake --build --presets-file ${PRESET_FILE} --preset ${BUILD_PRESET} -j${BUILD_WORKERS} && cmake --install build/native && \
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
  cd opencv-4.x && \
  cmake --presets-file ${PRESET_FILE} --preset ${CONF_PRESET} \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTS=OFF \
  -DBUILD_PERF_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_opencv_apps=OFF \
  -DWITH_GSTREAMER=ON && \
  cmake --build --presets-file ${PRESET_FILE} --preset ${BUILD_PRESET} -j${BUILD_WORKERS} && cmake --install build/native && \
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