# Toolchain file for native builds that run on the host system
# set(CMAKE_SYSTEM_NAME Linux)

set(CMAKE_C_COMPILER   clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_CXX_STANDARD 23)

# If building for arm64 host, use generic Armv8-A flags for broad compatibility
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(_GENERIC_ARM64_FLAGS "-march=armv8-a")
    string(APPEND CMAKE_C_FLAGS_INIT   " ${_GENERIC_ARM64_FLAGS}")
    string(APPEND CMAKE_CXX_FLAGS_INIT " ${_GENERIC_ARM64_FLAGS}")
endif()

message(STATUS "Loaded NATIVE toolchain file. Using flags: ${_GENERIC_ARM64_FLAGS}")