# syntax=docker/dockerfile:1
#
# mdnf1992/cpp-dev: C++ development image with GCC and DPC++ (intel/llvm, SYCL) in one place.
# Variants, pins and the build workflow are described in readme.md.
#
# One Dockerfile, three variants (--build-arg VARIANT=debian|cuda|tegra; see readme.md):
#   debian  debian:sid-slim,            GCC 16, DPC++ native_cpu,         oneMath netlib
#   cuda    nvidia/cuda ubuntu 24.04,   GCC 14, DPC++ native_cpu + CUDA,  oneMath netlib + cuBLAS
#   tegra   l4t-cuda 12.2 (ubuntu 22.04), GCC 12, DPC++ native_cpu + CUDA,  oneMath netlib + cuBLAS
#
# Stages:
#   os-debian | os-cuda | os-tegra   distro compilers and build tools (only the selected one is built)
#   base                             + the CMake binary. No toolchain/ copy: editing it never rebuilds DPC++
#   sycl_build                       DPC++ from source, /opt/sycl     (hours)
#   lapack                           Reference LAPACK/CBLAS, /opt/lapack
#   onemath                          oneMath into /opt/sycl
#   sycl_toolchain                   scratch: /opt/sycl + /opt/lapack only
#   dev_deps                         every library and tool the repos need (no DPC++)
#   cpp_dev                          dev_deps + the toolchain: the image
#
# Build with ./build.py, not a bare `docker build`: it keeps the multi-hour toolchain as a tagged
# local image (SYCL_TOOLCHAIN) so that builder garbage collection cannot evict it, and it never
# builds the toolchain and the dev layers at the same time.

ARG VARIANT=debian

# Base images. The debian digest is the one the previous cpp-dev was built on.
ARG DEBIAN_BASE=debian:sid-slim@sha256:ec3fa4e0b2987ae47be353f56854191e300261915470e40165b1c906d22a65db
ARG CUDA_BASE=nvidia/cuda:13.1.0-devel-ubuntu24.04
# nvcr.io/nvidia/l4t-cuda has no 12.6.11-devel tag (checked 2026-11-21: only 12.6.11-runtime, which has no
# nvcc or headers); 12.2.12-devel (CUDA 12.2, Ubuntu 22.04) is its newest devel image.
ARG TEGRA_BASE=nvcr.io/nvidia/l4t-cuda:12.2.12-devel

# Where cpp_dev takes /opt/sycl and /opt/lapack from: the stage below, or a tagged local image
# (build.py passes mdnf1992/cpp-dev:toolchain-<variant>-<hash>).
ARG SYCL_TOOLCHAIN=sycl_toolchain


# ---------------------------------------------------------------------------------------------
# OS stages
# ---------------------------------------------------------------------------------------------
FROM ${DEBIAN_BASE} AS os-debian
ARG DEBIAN_FRONTEND=noninteractive
# apt state of Debian sid: a snapshot.debian.org timestamp, or empty for live sid.
ARG DEBIAN_SNAPSHOT=20261116T212858Z
ENV CPP_DEV_VARIANT=debian \
    CPP_DEV_GCC=16 \
    CPP_DEV_CXX_STANDARD=26 \
    CPP_DEV_SYCL_CUDA=0
RUN set -eux; \
    if [ -n "${DEBIAN_SNAPSHOT}" ]; then \
      sed -i "s|^URIs: http://deb.debian.org/debian\$|URIs: http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/|" \
        /etc/apt/sources.list.d/debian.sources; \
      grep -q "snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/" /etc/apt/sources.list.d/debian.sources; \
      echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99snapshot; \
    fi; \
    apt-get update; \
    apt-get install -y \
      ca-certificates curl wget unzip git python3 pkg-config \
      gcc-${CPP_DEV_GCC} g++-${CPP_DEV_GCC} gfortran-${CPP_DEV_GCC} libc6-dev make \
      ninja-build lld \
      libzstd-dev zlib1g-dev libhwloc-dev ocl-icd-opencl-dev opencl-headers; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

FROM ${CUDA_BASE} AS os-cuda
ARG DEBIAN_FRONTEND=noninteractive
ENV CPP_DEV_VARIANT=cuda \
    CPP_DEV_GCC=14 \
    CPP_DEV_CXX_STANDARD=23 \
    CPP_DEV_SYCL_CUDA=1
RUN set -eux; \
    apt-get update; \
    apt-get install -y \
      ca-certificates curl wget unzip git python3 pkg-config \
      gcc-${CPP_DEV_GCC} g++-${CPP_DEV_GCC} gfortran-${CPP_DEV_GCC} libc6-dev make \
      ninja-build lld \
      libzstd-dev zlib1g-dev libhwloc-dev ocl-icd-opencl-dev opencl-headers; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# Ubuntu 22.04 ships GCC 12 (C++20). msensor needs C++23 features that want GCC 13: if it fails
# there, add the ubuntu-toolchain-r/test PPA here and set CPP_DEV_GCC=13 and CPP_DEV_CXX_STANDARD=23.
FROM ${TEGRA_BASE} AS os-tegra
ARG DEBIAN_FRONTEND=noninteractive
ENV CPP_DEV_VARIANT=tegra \
    CPP_DEV_GCC=12 \
    CPP_DEV_CXX_STANDARD=20 \
    CPP_DEV_SYCL_CUDA=1
RUN set -eux; \
    apt-get update; \
    apt-get install -y \
      ca-certificates curl wget unzip git python3 pkg-config \
      gcc-${CPP_DEV_GCC} g++-${CPP_DEV_GCC} gfortran-${CPP_DEV_GCC} libc6-dev make \
      ninja-build lld \
      libzstd-dev zlib1g-dev libhwloc-dev ocl-icd-opencl-dev opencl-headers; \
    apt-get clean; rm -rf /var/lib/apt/lists/*


# ---------------------------------------------------------------------------------------------
# base: the selected OS stage plus CMake. Nothing from toolchain/ is copied here.
# ---------------------------------------------------------------------------------------------
FROM os-${VARIANT} AS base
ARG CMAKE_VERSION=4.4.2
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) cmake_arch="x86_64" ;; \
      arm64) cmake_arch="aarch64" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    cmake_dir="cmake-${CMAKE_VERSION}-linux-${cmake_arch}"; \
    curl -fsSL "https://cmake.org/files/v${CMAKE_VERSION%.*}/${cmake_dir}.tar.gz" -o /tmp/${cmake_dir}.tar.gz; \
    tar -xzf /tmp/${cmake_dir}.tar.gz -C /opt; \
    ln -sf /opt/${cmake_dir}/bin/* /usr/local/bin/; \
    rm -f /tmp/${cmake_dir}.tar.gz


# ---------------------------------------------------------------------------------------------
# sycl_build: DPC++ (intel/llvm). No apt here: everything comes from the OS stage.
# ---------------------------------------------------------------------------------------------
FROM base AS sycl_build
ARG VARIANT
# Pinned to the commit moptim was validated with (built with assertions). CUDA 13.1 (cuda) and
# CUDA 12.2 (tegra) support at this commit is unverified: override DPCPP_REF per variant if needed.
ARG DPCPP_REPO=https://github.com/intel/llvm.git
ARG DPCPP_REF=fc235e9a9576f9771e0cab55aa31557095ef8091
ARG DPCPP_ASSERTIONS=ON
ARG BUILD_WORKERS=8
ENV SYCL_HOME=/opt/sycl

# The source and object tree live in a cache mount (not in the image), so that a failed or
# interrupted build resumes where it stopped. Only /opt/sycl is kept.
RUN --mount=type=cache,id=cpp-dev-llvm-${VARIANT},target=/cache/llvm \
    set -eux; \
    src=/cache/llvm/src; obj=/cache/llvm/build; \
    mkdir -p "$src" "$obj"; \
    cd "$src"; \
    [ -d .git ] || git init -q; \
    git remote remove origin 2>/dev/null || true; \
    git remote add origin "${DPCPP_REPO}"; \
    if [ "$(git rev-parse -q --verify HEAD || true)" != "${DPCPP_REF}" ]; then \
      git fetch --depth 1 origin "${DPCPP_REF}"; \
      git checkout -q --force FETCH_HEAD; \
    fi; \
    test "$(git rev-parse HEAD)" = "${DPCPP_REF}"; \
    cuda_flag=""; if [ "${CPP_DEV_SYCL_CUDA}" = "1" ]; then cuda_flag="--cuda"; fi; \
    assert_flag=""; if [ "${DPCPP_ASSERTIONS}" != "ON" ]; then assert_flag="--no-assertions"; fi; \
    export CC=gcc-${CPP_DEV_GCC} CXX=g++-${CPP_DEV_GCC}; \
    python3 buildbot/configure.py \
      -s "$src" -o "$obj" \
      ${cuda_flag} --native_cpu ${assert_flag} \
      -t Release \
      --cmake-opt="-DCMAKE_INSTALL_PREFIX=${SYCL_HOME}" \
      --cmake-opt="-DCMAKE_C_COMPILER=gcc-${CPP_DEV_GCC}" \
      --cmake-opt="-DCMAKE_CXX_COMPILER=g++-${CPP_DEV_GCC}" \
      --cmake-opt="-DLLVM_USE_LINKER=lld" \
      --cmake-opt="-DLLVM_USE_STATIC_ZSTD=OFF" \
      --cmake-opt="-DCMAKE_POLICY_VERSION_MINIMUM=3.5" \
      --cmake-opt="-DSYCL_INCLUDE_TESTS=OFF"; \
    python3 buildbot/compile.py -s "$src" -o "$obj" -t deploy-sycl-toolchain -j${BUILD_WORKERS}; \
    cmake --build "$obj" --target install-clang-scan-deps -j${BUILD_WORKERS}; \
    mkdir -p ${SYCL_HOME}/share/cpp-dev; \
    { \
      echo "DPCPP_REF=${DPCPP_REF}"; \
      echo "DPCPP_ASSERTIONS=${DPCPP_ASSERTIONS}"; \
      echo "CPP_DEV_VARIANT=${CPP_DEV_VARIANT}"; \
      echo "CPP_DEV_GCC=${CPP_DEV_GCC}"; \
      echo "CPP_DEV_SYCL_CUDA=${CPP_DEV_SYCL_CUDA}"; \
      echo "LIBC6_VERSION=$(dpkg-query -W -f='${Version}' libc6)"; \
      echo "LIBSTDCXX6_VERSION=$(dpkg-query -W -f='${Version}' libstdc++6)"; \
    } > ${SYCL_HOME}/share/cpp-dev/toolchain.env; \
    ${SYCL_HOME}/bin/clang++ --version


# ---------------------------------------------------------------------------------------------
# lapack: Reference LAPACK + CBLAS in /opt/lapack. Kept out of /usr/local so that it cannot
# shadow the system BLAS for GCC builds. Independent of sycl_build.
# ---------------------------------------------------------------------------------------------
FROM base AS lapack
ARG LAPACK_VERSION=3.12.1
ARG BUILD_WORKERS=8
RUN set -eux; \
    cd /tmp; \
    curl -fsSL https://github.com/Reference-LAPACK/lapack/archive/refs/tags/v${LAPACK_VERSION}.tar.gz -o lapack.tar.gz; \
    tar -xzf lapack.tar.gz; \
    cmake -S lapack-${LAPACK_VERSION} -B lapack-${LAPACK_VERSION}/build -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/opt/lapack \
      -DCMAKE_C_COMPILER=gcc-${CPP_DEV_GCC} \
      -DCMAKE_Fortran_COMPILER=gfortran-${CPP_DEV_GCC} \
      -DBUILD_TESTING=OFF \
      -DTEST_FORTRAN_COMPILER=OFF \
      -DCBLAS=ON \
      -DLAPACKE=ON \
      -DBUILD_INDEX64_EXT_API=OFF \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON; \
    cmake --build lapack-${LAPACK_VERSION}/build -j${BUILD_WORKERS}; \
    cmake --install lapack-${LAPACK_VERSION}/build; \
    rm -rf /tmp/lapack*


# ---------------------------------------------------------------------------------------------
# onemath: oneMath into /opt/sycl, built with the DPC++ above.
# ONEMATH_BACKENDS is a comma list of netlib, cublas and generic ("generic" excludes the others).
# Empty means netlib, plus cublas when the variant has CUDA.
# ---------------------------------------------------------------------------------------------
FROM base AS onemath
ARG ONEMATH_REF=v0.9
ARG ONEMATH_BACKENDS=
ARG SYCL_GENERIC_TARGETS=spir64,native_cpu
ARG LAPACK_VERSION=3.12.1
ARG BUILD_WORKERS=8
ENV SYCL_HOME=/opt/sycl
COPY --from=sycl_build /opt/sycl /opt/sycl
COPY --from=lapack /opt/lapack /opt/lapack
RUN set -eux; \
    backends="${ONEMATH_BACKENDS}"; \
    if [ -z "$backends" ]; then \
      backends=netlib; \
      if [ "${CPP_DEV_SYCL_CUDA}" = "1" ]; then backends=netlib,cublas; fi; \
    fi; \
    flags=""; \
    for b in $(echo "$backends" | tr ',' ' '); do \
      case "$b" in \
        netlib) flags="$flags -DENABLE_NETLIB_BACKEND=ON" ;; \
        cublas) flags="$flags -DENABLE_CUBLAS_BACKEND=ON -DCUDA_CUDA_LIBRARY=/usr/local/cuda/lib64/libcudart.so" ;; \
        generic) flags="$flags -DENABLE_GENERIC_BLAS_BACKEND=ON \"-DCMAKE_CXX_FLAGS=-fsycl -fsycl-targets=${SYCL_GENERIC_TARGETS}\"" ;; \
        *) echo "unknown oneMath backend: $b" >&2; exit 1 ;; \
      esac; \
    done; \
    case ",$backends," in \
      *,generic,*) [ "$backends" = generic ] || { echo "the generic oneMath backend cannot be combined with others" >&2; exit 1; } ;; \
    esac; \
    cd /tmp; \
    git clone --depth 1 -b ${ONEMATH_REF} https://github.com/uxlfoundation/oneMath.git; \
    eval cmake -S oneMath -B oneMath/build -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=${SYCL_HOME}/bin/clang \
      -DCMAKE_CXX_COMPILER=${SYCL_HOME}/bin/clang++ \
      -DCMAKE_PREFIX_PATH=/opt/lapack \
      -DREF_BLAS_ROOT=/opt/lapack \
      -DREF_LAPACK_ROOT=/opt/lapack \
      -DBUILD_FUNCTIONAL_TESTS=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DENABLE_CUSOLVER_BACKEND=OFF \
      -DENABLE_MKLCPU_BACKEND=OFF \
      -DENABLE_MKLGPU_BACKEND=OFF \
      $flags; \
    LD_LIBRARY_PATH=${SYCL_HOME}/lib cmake --build oneMath/build -j${BUILD_WORKERS}; \
    LD_LIBRARY_PATH=${SYCL_HOME}/lib cmake --install oneMath/build --prefix ${SYCL_HOME}; \
    { \
      echo "ONEMATH_REF=${ONEMATH_REF}"; \
      echo "ONEMATH_BACKENDS=$backends"; \
      echo "LAPACK_VERSION=${LAPACK_VERSION}"; \
    } >> ${SYCL_HOME}/share/cpp-dev/toolchain.env; \
    rm -rf /tmp/oneMath


# ---------------------------------------------------------------------------------------------
# sycl_toolchain: only the toolchain files. build.py tags this stage as
# mdnf1992/cpp-dev:toolchain-<variant>-<hash> and passes the tag as SYCL_TOOLCHAIN.
# ---------------------------------------------------------------------------------------------
FROM scratch AS sycl_toolchain
COPY --from=onemath /opt/sycl /opt/sycl
COPY --from=lapack /opt/lapack /opt/lapack


# ---------------------------------------------------------------------------------------------
# dev_deps: libraries and tools of the repos (mslam, msensor, moptim, ...). No DPC++, so the
# CUDA/Tegra package sets can be tested without the multi-hour toolchain build.
# ---------------------------------------------------------------------------------------------
FROM base AS dev_deps
ARG VARIANT
ARG DEBIAN_FRONTEND=noninteractive
ARG BUILD_WORKERS=8
# libcamera + rpicam-apps (Raspberry Pi camera stack): empty means ON for debian, OFF otherwise.
ARG WITH_RPI_CAMERA=

COPY packages/${VARIANT}.txt /tmp/packages.txt
RUN set -eux; \
    apt-get update; \
    grep -vE '^[[:space:]]*(#|$)' /tmp/packages.txt | xargs apt-get install -y; \
    apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/packages.txt

# uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Node.js: the distro package on Debian sid (24.x); on the Ubuntu variants the official binary of
# the same major version (Ubuntu ships 12 and 18).
ARG NODE_VERSION=24.22.2
RUN set -eux; \
    if [ "${CPP_DEV_VARIANT}" != "debian" ]; then \
      case "$(dpkg --print-architecture)" in amd64) node_arch=x64 ;; arm64) node_arch=arm64 ;; *) exit 1 ;; esac; \
      curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.gz" \
        | tar -xz -C /usr/local --strip-components=1 --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md; \
    fi; \
    node --version; npm --version

# CMake toolchain for the source builds below: the same compiler and flags as
# toolchain/gcc.cmake, but generated here so that editing toolchain/ does not rebuild them.
RUN printf '%s\n' \
      'set(CMAKE_C_COMPILER   /usr/bin/gcc-$ENV{CPP_DEV_GCC})' \
      'set(CMAKE_CXX_COMPILER /usr/bin/g++-$ENV{CPP_DEV_GCC})' \
      'set(CMAKE_CXX_STANDARD $ENV{CPP_DEV_CXX_STANDARD})' \
      'if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")' \
      '  string(APPEND CMAKE_C_FLAGS_INIT   " -march=armv8-a")' \
      '  string(APPEND CMAKE_CXX_FLAGS_INIT " -march=armv8-a")' \
      'endif()' \
      > /tmp/cpp-dev-build.cmake

# Eigen 5.0.1, fmt 11.1.1 and spdlog 1.15.3 on the Ubuntu variants (Debian sid ships them): the
# same versions everywhere, and a fmt that clang 23 accepts.
RUN set -eux; \
    if [ "${CPP_DEV_VARIANT}" != "debian" ]; then \
      cd /tmp; \
      git clone --depth 1 -b 5.0.1 https://gitlab.com/libeigen/eigen.git; \
      cmake -S eigen -B eigen/build -GNinja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=/tmp/cpp-dev-build.cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_TESTING=OFF -DEIGEN_BUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF; \
      cmake --install eigen/build; \
      git clone --depth 1 -b 11.1.1 https://github.com/fmtlib/fmt.git; \
      cmake -S fmt -B fmt/build -GNinja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=/tmp/cpp-dev-build.cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=ON -DFMT_TEST=OFF -DFMT_DOC=OFF; \
      cmake --build fmt/build -j${BUILD_WORKERS}; \
      cmake --install fmt/build; \
      ldconfig; \
      git clone --depth 1 -b v1.15.3 https://github.com/gabime/spdlog.git; \
      cmake -S spdlog -B spdlog/build -GNinja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=/tmp/cpp-dev-build.cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DSPDLOG_BUILD_SHARED=ON -DSPDLOG_FMT_EXTERNAL=ON \
        -DSPDLOG_BUILD_TESTS=OFF -DSPDLOG_BUILD_EXAMPLE=OFF; \
      cmake --build spdlog/build -j${BUILD_WORKERS}; \
      cmake --install spdlog/build; \
      ldconfig; \
      rm -rf /tmp/eigen /tmp/fmt /tmp/spdlog; \
    fi

# gRPC (with its bundled protobuf, abseil, re2, c-ares: CMake configs in /usr/local)
RUN set -eux; \
    cd /tmp; \
    git clone --recurse-submodules -b v1.84.0 --depth 1 --shallow-submodules https://github.com/grpc/grpc; \
    cmake -S grpc -B grpc/build -GNinja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE=/tmp/cpp-dev-build.cmake \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DgRPC_INSTALL=ON \
      -DgRPC_BUILD_TESTS=OFF; \
    cmake --build grpc/build -j${BUILD_WORKERS}; \
    cmake --install grpc/build; \
    ldconfig; \
    rm -rf /tmp/grpc

# OpenCV, the 4.x commit of 2026-11-16 (what the previous cpp-dev image had)
ARG OPENCV_REF=333974b268332108df496e93a976c96d052f9dde
RUN set -eux; \
    mkdir /tmp/opencv; cd /tmp/opencv; \
    git init -q; \
    git remote add origin https://github.com/opencv/opencv.git; \
    git fetch --depth 1 origin "${OPENCV_REF}"; \
    git checkout -q FETCH_HEAD; \
    test "$(git rev-parse HEAD)" = "${OPENCV_REF}"; \
    cmake -S . -B build -GNinja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE=/tmp/cpp-dev-build.cmake \
      -DBUILD_TESTS=OFF \
      -DBUILD_PERF_TESTS=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_opencv_apps=OFF \
      -DWITH_GSTREAMER=ON; \
    cmake --build build -j${BUILD_WORKERS}; \
    cmake --install build; \
    ldconfig; \
    rm -rf /tmp/opencv

# Raspberry Pi camera stack: libcamera + rpicam-apps (only when WITH_RPI_CAMERA is ON)
RUN set -eux; \
    want="${WITH_RPI_CAMERA}"; \
    if [ -z "$want" ]; then if [ "${CPP_DEV_VARIANT}" = "debian" ]; then want=ON; else want=OFF; fi; fi; \
    if [ "$want" != "ON" ]; then echo "skipping libcamera and rpicam-apps (WITH_RPI_CAMERA=$want)"; exit 0; fi; \
    apt-get update; \
    apt-get install -y \
      git \
      python3-pip python3-jinja2 \
      libboost-dev \
      libgnutls28-dev openssl libtiff5-dev pybind11-dev \
      meson cmake \
      python3-yaml python3-ply \
      libglib2.0-dev libgstreamer-plugins-base1.0-dev \
      libboost-program-options-dev libdrm-dev libexif-dev \
      libpng-dev libjpeg-dev \
      libgstreamer1.0-dev \
      gstreamer1.0-tools; \
    apt-get clean; rm -rf /var/lib/apt/lists/*; \
    cd /tmp; \
    git clone https://github.com/raspberrypi/libcamera.git; \
    cd libcamera; \
    meson setup build \
      --buildtype=release \
      -Dpipelines=rpi/vc4,rpi/pisp \
      -Dipas=rpi/vc4,rpi/pisp \
      -Dv4l2=true -Dgstreamer=enabled \
      -Dtest=false -Dlc-compliance=disabled \
      -Dcam=disabled -Dqcam=disabled \
      -Ddocumentation=disabled \
      -Dpycamera=enabled; \
    ninja -C build; \
    ninja -C build install; \
    cd /tmp; rm -rf /tmp/libcamera; \
    ldconfig; \
    git clone https://github.com/raspberrypi/rpicam-apps.git; \
    cd rpicam-apps; \
    meson setup build \
      -Denable_libav=disabled \
      -Denable_drm=enabled \
      -Denable_egl=disabled \
      -Denable_qt=disabled \
      -Denable_opencv=disabled \
      -Denable_tflite=disabled \
      -Denable_hailo=disabled; \
    meson compile -C build; \
    meson install -C build; \
    cd /tmp; rm -rf /tmp/rpicam-apps; \
    ldconfig

ENV GST_PLUGIN_PATH=/usr/local/lib/aarch64-linux-gnu/gstreamer-1.0:/usr/local/lib/gstreamer-1.0

# Toolchain files and CMake presets for the repos (after the source builds, which do not depend
# on them).
RUN rm -f /tmp/cpp-dev-build.cmake
COPY ./toolchain /opt/toolchain
COPY ./CMakePresets.json /opt/toolchain/CMakePresets.json

# opencode (last, it changes most often)
RUN curl -fsSL https://opencode.ai/v2/install | bash


# ---------------------------------------------------------------------------------------------
# cpp_dev: the image. dev_deps + DPC++, oneMath and LAPACK from the toolchain.
# ---------------------------------------------------------------------------------------------
FROM ${SYCL_TOOLCHAIN} AS toolchain

FROM dev_deps AS cpp_dev
COPY --from=toolchain /opt/sycl /opt/sycl
COPY --from=toolchain /opt/lapack /opt/lapack

# The DPC++ runtime libraries were built against the libc6 and libstdc++6 of the OS stage: the
# system here must not be older (a toolchain image built on another snapshot, for instance).
RUN set -eu; \
    . /opt/sycl/share/cpp-dev/toolchain.env; \
    for pair in "libc6:${LIBC6_VERSION}" "libstdc++6:${LIBSTDCXX6_VERSION}"; do \
      pkg="${pair%%:*}"; built="${pair#*:}"; have="$(dpkg-query -W -f='${Version}' "$pkg")"; \
      if ! dpkg --compare-versions "$have" ge "$built"; then \
        echo "the toolchain was built against $pkg $built, this image has the older $pkg $have" >&2; exit 1; \
      fi; \
    done

# /opt/sycl/lib comes last in the loader's search order, through ld.so.conf (no LD_LIBRARY_PATH):
# the system libOpenCL and the other system libraries win over the copies DPC++ ships.
RUN echo /opt/sycl/lib > /etc/ld.so.conf.d/zz-sycl.conf && ldconfig

ENV SYCL_HOME=/opt/sycl
# Appended: /usr/bin clang-format, clangd and clang-tidy stay first (mslam's build runs
# `clang-format -i`); clang, clang++ and sycl-ls come from /opt/sycl/bin.
ENV PATH=${PATH}:/opt/sycl/bin
# Debian's /etc/profile resets PATH, so login shells (`bash -lc`, and the login-shell probe VS Code
# devcontainers use for their environment) would lose the ENV above. Same rule: append only.
RUN printf '%s\n' \
      'case ":$PATH:" in *:/opt/sycl/bin:*) ;; *) PATH="$PATH:/opt/sycl/bin" ;; esac' \
      'export PATH' \
      'export SYCL_HOME=/opt/sycl' > /etc/profile.d/zz-sycl.sh

# Smoke tests: the image must be able to compile and run SYCL code, and compile a -fsycl
# translation unit that uses the libraries of the repos. On cuda/tegra sycl-ls may list no CUDA
# device (no GPU while building); native_cpu is always there.
RUN set -eux; \
    cat /opt/sycl/share/cpp-dev/toolchain.env; \
    clang++ --version; \
    sycl-ls | tee /tmp/sycl-ls.txt; \
    grep -q native_cpu /tmp/sycl-ls.txt; \
    test "$(command -v clang-format)" = /usr/bin/clang-format; \
    test "$(command -v clangd)" = /usr/bin/clangd; \
    test "$(command -v clang-tidy)" = /usr/bin/clang-tidy; \
    test "$(command -v clang++)" = /opt/sycl/bin/clang++; \
    test "$(bash -lc 'command -v clang++')" = /opt/sycl/bin/clang++; \
    test "$(bash -lc 'command -v clang-format')" = /usr/bin/clang-format; \
    bash -lc 'sycl-ls' | grep -q native_cpu; \
    mkdir /tmp/smoke; cd /tmp/smoke; \
    printf '%s\n' \
      '#include <sycl/sycl.hpp>' \
      '#include <cstdio>' \
      'int main() {' \
      '  sycl::queue q{sycl::default_selector_v};' \
      '  int *r = sycl::malloc_shared<int>(1, q);' \
      '  q.single_task([=] { *r = 42; }).wait();' \
      '  const int v = *r;' \
      '  std::printf("single_task: %d on %s\n", v, q.get_device().get_info<sycl::info::device::name>().c_str());' \
      '  sycl::free(r, q);' \
      '  return v == 42 ? 0 : 1;' \
      '}' > single_task.cc; \
    clang++ -std=c++20 -fsycl -fsycl-targets=native_cpu single_task.cc -o single_task; \
    ./single_task; \
    printf '%s\n' \
      '#include <sycl/sycl.hpp>' \
      '#include <Eigen/Dense>' \
      '#include <spdlog/spdlog.h>' \
      '#include <grpcpp/grpcpp.h>' \
      '#include <google/protobuf/message.h>' \
      '#include <opencv2/core.hpp>' \
      'int main() {' \
      '  sycl::queue q{sycl::default_selector_v};' \
      '  Eigen::Vector3d v(1, 2, 3);' \
      '  spdlog::info("{} {}", v.norm(), grpc::Status::OK.ok());' \
      '  return q.get_device().is_cpu() ? 0 : 1;' \
      '}' > libs.cc; \
    clang++ -std=c++20 -fsycl -fsycl-targets=native_cpu -Xsycl-target-frontend=native_cpu -DEIGEN_DONT_VECTORIZE \
      -Xsycl-target-frontend=native_cpu -U__ARM_NEON -Xsycl-target-frontend=native_cpu -U__ARM_NEON__ \
      $(pkg-config --cflags eigen3) -I/usr/local/include/opencv4 \
      -c libs.cc -o libs.o; \
    cd /; rm -rf /tmp/smoke /tmp/sycl-ls.txt
