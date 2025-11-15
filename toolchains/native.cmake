# Toolchain file for NATIVE compilation
# (e.g., building on your x86_64 laptop)

# We are building for the host, so CMAKE_SYSTEM_NAME is NOT set.

# Set the native compilers
set(CMAKE_C_COMPILER   gcc)
set(CMAKE_CXX_COMPILER g++)

# Set the architecture-specific flags.
# These will be added BEFORE build-type flags (like -O3).
set(CMAKE_C_FLAGS_INIT   "-march=native" CACHE STRING "Initial C flags for native build")
set(CMAKE_CXX_FLAGS_INIT "-march=native" CACHE STRING "Initial CXX flags for native build")

message(STATUS "Loaded NATIVE toolchain file. Using -march=native.")