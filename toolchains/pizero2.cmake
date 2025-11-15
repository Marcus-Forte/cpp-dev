# Toolchain file for Raspberry Pi Zero 2 W (Cortex-A53)
# This assumes a native ARM64 build environment (e.g., inside an arm64 container).
# This is also a safe, generic build for Pi 3 and Pi 4.

set(CMAKE_SYSTEM_NAME Linux)

# Set the compilers (native ARM compilers)
set(CMAKE_C_COMPILER   gcc)
set(CMAKE_CXX_COMPILER g++)

# Set the architecture-specific flags.
set(CMAKE_C_FLAGS_INIT   "-mcpu=cortex-a53 -mtune=cortex-a53" CACHE STRING "Initial C flags for Pi Zero 2")
set(CMAKE_CXX_FLAGS_INIT "-mcpu=cortex-a53 -mtune=cortex-a53" CACHE STRING "Initial CXX flags for Pi Zero 2")

message(STATUS "Loaded Raspberry Pi Zero 2 toolchain file. Using -mcpu=cortex-a53.")