# Generic C++ Development Container.

See example `devcontainer.json` for usage.

## Components

- GTEST
- GDB
- ARM and X64 GCC
- PCL library
- clang-format, clang-tidy
- gRPC

## Cross-compiling

Use provided cmake kits located at  `/opt/toolchains/cmake-kits.json` to cross-compile.
Add it to cmake extension: `"cmake.additionalKits": ["/opt/toolchains/cmake-kits.json"]`.
