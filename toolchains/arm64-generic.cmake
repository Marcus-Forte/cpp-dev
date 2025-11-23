# Toolchain file for "arm64-generic" builds that run on any Armv8-A board.
# Use this when compiling on any host but you want binaries that run on
# any Armv8-A (arm64) SoC, not just the exact CPU you built on.

# We are building for the host toolchain, so CMAKE_SYSTEM_NAME is NOT set.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Set the arm64 compilers
set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)

# Use conservative Armv8-A flags so the produced binaries work on any arm64
# Raspberry Pi (Pi 3/4/5, Pi Zero 2 W, etc.). These initialize the regular
# CMake C/CXX flag cache entries.
set(_GENERIC_ARM64_FLAGS "-march=armv8-a -mtune=cortex-a55")
set(CMAKE_C_FLAGS_INIT   "${_GENERIC_ARM64_FLAGS}" CACHE STRING "Initial C flags for portable arm64 build")
set(CMAKE_CXX_FLAGS_INIT "${_GENERIC_ARM64_FLAGS}" CACHE STRING "Initial CXX flags for portable arm64 build")

message(STATUS "Loaded ARM64-GENERIC toolchain file. Using flags: ${_GENERIC_ARM64_FLAGS}")

SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)