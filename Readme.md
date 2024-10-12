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
Add this lines to top-level CMakeLists.txt before `project()`
```
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(ARM_OBJCOPY arm-none-eabi-objcopy)
```