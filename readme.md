# C++ Development Container

Container image for C++ development with Clang, CMake, Ninja, debugging tools, and prebuilt robotics/computer-vision dependencies.

See your project-level `devcontainer.json` for integration details.

## Build image

```bash
./build.py -h
```

Default image tag is `mdnf1992/cpp-dev:latest`.

## Included components

- Base image: `debian:trixie-slim`
- Toolchain and build: `clang`, `clang++`, `cmake`, `ninja`, `git`
- C/C++ tooling: `clangd`, `clang-format`, `clang-tidy`, `gdb`
- Core libraries: Eigen3, Boost, GoogleTest, GoogleMock, JSONCPP, FLANN, nanoflann
- ARM MCU cross-toolchain: `gcc-arm-none-eabi`
- Diagram tooling: PlantUML
- Python package manager: `uv`
- PCL from source: `pcl-1.15.1` (reduced module set)
- gRPC from source: `v1.78.0`
- OpenCV from source: `4.x` (with GStreamer enabled)
- Raspberry Pi camera stack from source: `libcamera` + `rpicam-apps`

## Toolchains inside the container

Toolchain files are copied to `/opt/toolchains`:

- `/opt/toolchains/native.cmake`: native host builds using GCC and C++23
- `/opt/toolchains/native-gcc-16.cmake`: native host builds using GCC-16 and C++26
- `/opt/toolchains/arm-toolchain.cmake`: `arm-none-eabi` bare-metal microcontroller builds

Example CMake usage:

```bash
cmake -S . -B build-native -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/toolchains/native.cmake
cmake --build build-native
```

```bash
cmake -S . -B build-arm -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/toolchains/arm-toolchain.cmake
cmake --build build-arm
```

Note: `arm-toolchain.cmake` is for bare-metal ARM microcontrollers, not Raspberry Pi Linux user-space targets.

## Recommended usage in app repos

To use this image as a devcontainer, the most reliable approach is:

- Copy the reference preset file `CMakePresets.json` to the root of the user repo.
- In VS Code, use the CMake Tools extension with presets enabled.

To build, use:

```bash
cmake --preset devcontainer-native
cmake --build --preset build-native
```

```bash
cmake --preset devcontainer-arm-none-eabi
cmake --build --preset build-arm-none-eabi
```
