# Toolchain file for SYCL builds using the DPC++ compiler in /opt/sycl

set(CMAKE_C_COMPILER   /opt/sycl/bin/clang)
set(CMAKE_CXX_COMPILER /opt/sycl/bin/clang++)
set(CMAKE_CXX_STANDARD 23)

# oneMath and the other libraries installed in /opt/sycl
list(APPEND CMAKE_PREFIX_PATH /opt/sycl)
