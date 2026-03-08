# C++ Development Container with C++ compiler and some (cool) libraries.

See example `devcontainer.json` for usage.

## Usage

```bash
./build_push.sh -h
```

## Build & Push

```bash
./build_push.sh -p
```
## Components

- gtest + gmock
- gdb
- Eigen3
- PCL library
- clang-format, clang-tidy
- gRPC
- OpenCV
- Python + `uv`
- RaspberryPi libcamera (from CSI camera)

## Cross-compiling

Use provided cmake kits located at  `/opt/toolchains/cmake-kits.json` to cross-compile.
Add it to you devcontainer cmake extension: `"cmake.additionalKits": ["/opt/toolchains/cmake-kits.json"]`.
