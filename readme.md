# C++ & SYCL Development Containers

Container images for C++ and SYCL development with GCC 16, DPC++ (`intel/llvm`), oneMath, CMake, Ninja, debugging tools, and prebuilt robotics/computer-vision dependencies.

See your project-level `devcontainer.json` for integration details.

## Build images

```bash
./build.py -h
```

### Base C++ Development Image (`Dockerfile`)

```bash
./build.py
```

Default image tag is `mdnf1992/cpp-dev:latest`.

### SYCL + oneMath Development Images (`Dockerfile.sycl`)

`Dockerfile.sycl` builds the Intel LLVM DPC++ SYCL toolchain (`/opt/sycl`) and UXl Foundation `oneMath` across multiple base images and BLAS backends:

- **Default (`lapack`)**: `mdnf1992/sycl-dev:latest` (base `mdnf1992/cpp-dev:latest`, target `onemath_lapack` with Reference LAPACK/CBLAS Netlib backend and SYCL Native CPU)
- **CUDA (`cuda`)**: `mdnf1992/sycl-dev:cuda` (base `nvidia/cuda:13.1.0-devel-ubuntu24.04`, target `onemath_cublas` with SYCL CUDA + cuBLAS + Netlib backends)
- **Generic (`generic`)**: `mdnf1992/sycl-dev:generic` (base `mdnf1992/cpp-dev:latest`, target `onemath_generic` with pure-SYCL Generic BLAS backend)
- **Tegra (`tegra`)**: `mdnf1992/sycl-dev:tegra` (base `nvcr.io/nvidia/l4t-cuda:12.6.11-devel`, target `onemath_cublas` with SYCL CUDA + cuBLAS + Netlib backends for NVIDIA Jetson/Tegra)

Build specific SYCL targets using `./build.py`:

```bash
./build.py --sycl       # or --lapack: builds mdnf1992/sycl-dev:latest
./build.py --cuda       # builds mdnf1992/sycl-dev:cuda
./build.py --generic    # builds mdnf1992/sycl-dev:generic
./build.py --tegra      # builds mdnf1992/sycl-dev:tegra
./build.py --all-sycl   # builds all SYCL variants
```

## Included components

### `mdnf1992/cpp-dev` (`Dockerfile`)
- Base image: `debian:sid-slim`
- Toolchain and build: `gcc-16`, `g++-16`, `cmake` (`4.4.2`), `ninja`, `git`, `git-lfs`
- C/C++ tooling: `clangd`, `clang-format`, `clang-tidy`, `gdb`
- Core libraries: Eigen3, Boost, oneTBB (`libtbb-dev`), GoogleTest, GoogleMock, JSONCPP, spdlog, libi2c
- ARM MCU cross-toolchain: `gcc-arm-none-eabi`
- Python package manager: `uv`
- gRPC from source: `v1.84.0`
- OpenCV from source: `4.x` (with GStreamer enabled)
- Raspberry Pi camera stack from source: `libcamera` + `rpicam-apps`
- AI agent CLI: `opencode`

### `mdnf1992/sycl-dev` (`Dockerfile.sycl`)
- SYCL compiler (`intel/llvm`, branch `sycl`) installed in `/opt/sycl` with Native CPU (and optional `--cuda` backend)
- Reference LAPACK + CBLAS (`v3.12.1`)
- UXL Foundation `oneMath` (`onemath_lapack`, `onemath_generic`, or `onemath_cublas`) installed in `/opt/sycl`

## Toolchains inside the container

Toolchain files are copied to `/opt/toolchain` alongside `/opt/toolchain/CMakePresets.json`:

- `/opt/toolchain/gcc.cmake`: native host builds using GCC 16 and C++26
- `/opt/toolchain/arm-toolchain.cmake`: `arm-none-eabi` bare-metal microcontroller builds
- `/opt/toolchain/sycl.cmake`: SYCL builds using `/opt/sycl/bin/clang++` and C++23

## Recommended usage in app repos

Copy `CMakePresets.json` (or include `/opt/toolchain/CMakePresets.json`) in your project root:

```bash
cmake --preset gcc
cmake --build --preset build-gcc
```

```bash
cmake --preset arm-none-eabi
cmake --build --preset build-arm-none-eabi
```

```bash
cmake --preset sycl
cmake --build --preset build-sycl
```
