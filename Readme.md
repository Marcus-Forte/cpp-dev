# Generic C++ Development Container.

## Components:

- GTEST
- GDB
- ARM and X64 GCC
- PCL library
- clang-format, clang-tidy

use this in your `devcontainer.json`:
```
"image": "mdnf1992/cpp-dev"
```

## Cross-compiling to arm uC.
Use `cmake -DCMAKE_TOOLCHAIN_FILE=/opt/toolchains/arm-toolchain.cmake ...`