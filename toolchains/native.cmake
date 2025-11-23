# Toolchain file for native builds that run on the host system
# set(CMAKE_SYSTEM_NAME Linux)

set(CMAKE_C_COMPILER   gcc)
set(CMAKE_CXX_COMPILER g++)

# If building for arm64 host, use generic Armv8-A flags for broad compatibility
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(_GENERIC_ARM64_FLAGS "-march=armv8-a")
    set(CMAKE_C_FLAGS_INIT   "${_GENERIC_ARM64_FLAGS}" CACHE STRING "Initial C flags for portable arm64 build")
    set(CMAKE_CXX_FLAGS_INIT "${_GENERIC_ARM64_FLAGS}" CACHE STRING "Initial CXX flags for portable arm64 build")
endif()

message(STATUS "Loaded NATIVE toolchain file. Using flags: ${_GENERIC_ARM64_FLAGS}")