# Toolchain file for native builds that run on the host system.
#
# The GCC version and the C++ standard come from the image (ENV set by the Dockerfile's OS stage:
# CPP_DEV_GCC and CPP_DEV_CXX_STANDARD). The defaults are those of the Debian image.

if(DEFINED ENV{CPP_DEV_GCC})
    set(_CPP_DEV_GCC "$ENV{CPP_DEV_GCC}")
else()
    set(_CPP_DEV_GCC 16)
endif()

if(DEFINED ENV{CPP_DEV_CXX_STANDARD})
    set(_CPP_DEV_CXX_STANDARD "$ENV{CPP_DEV_CXX_STANDARD}")
else()
    set(_CPP_DEV_CXX_STANDARD 26)
endif()

set(CMAKE_C_COMPILER   /usr/bin/gcc-${_CPP_DEV_GCC})
set(CMAKE_CXX_COMPILER /usr/bin/g++-${_CPP_DEV_GCC})
set(CMAKE_CXX_STANDARD ${_CPP_DEV_CXX_STANDARD})

# If building for arm64 host, use generic Armv8-A flags for broad compatibility
if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(_GENERIC_ARM64_FLAGS "-march=armv8-a")
    string(APPEND CMAKE_C_FLAGS_INIT   " ${_GENERIC_ARM64_FLAGS}")
    string(APPEND CMAKE_CXX_FLAGS_INIT " ${_GENERIC_ARM64_FLAGS}")
endif()

message(STATUS "Loaded toolchain file. GCC ${_CPP_DEV_GCC}, C++${_CPP_DEV_CXX_STANDARD}. Using flags: ${_GENERIC_ARM64_FLAGS}")
