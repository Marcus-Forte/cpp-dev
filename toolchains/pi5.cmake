# Toolchain file for Raspberry Pi 5 (Cortex-A76)
# This assumes a native ARM64 build environment (e.g., inside an arm64 container).

set(CMAKE_SYSTEM_NAME Linux)

# Set the compilers (native ARM compilers)
set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)

# Set the architecture-specific flags for the Pi 5.
set(CMAKE_C_FLAGS_INIT   "-mcpu=cortex-a76" CACHE STRING "Initial C flags for Pi 5")
set(CMAKE_CXX_FLAGS_INIT "-mcpu=cortex-a76" CACHE STRING "Initial CXX flags for Pi 5")

message(STATUS "Loaded Raspberry Pi 5 toolchain file. Using -mcpu=cortex-a76.")