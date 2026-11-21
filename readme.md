# cpp-dev: C++ and SYCL development container

One image, `mdnf1992/cpp-dev`, with GCC and DPC++ (the `intel/llvm` SYCL compiler) side by side, plus the libraries and tools the repos need (Eigen, gRPC, OpenCV, spdlog/fmt, oneTBB, GoogleTest, Boost, jsoncpp, ARM cross-compiler, gdb, clangd/clang-format/clang-tidy, `uv`, Node.js, opencode). It builds moptim, mslam and msensor, with guaranteed SYCL support.

There is **one `Dockerfile`**, and the variants come from its `VARIANT` build argument. Always build through `./build.py`, never a bare `docker build` (see [Building](#building)).

## Variants

| Variant | Tag | OS stage base | GCC (C++) | DPC++ backends | oneMath backends | Pi camera stack |
|---|---|---|---|---|---|---|
| `debian` (default) | `latest` | `debian:sid-slim@sha256:ec3fa4e0…` + apt snapshot `20261116T212858Z` | 16 (26) | native_cpu | netlib | yes |
| `cuda` | `cuda` | `nvidia/cuda:13.1.0-devel-ubuntu24.04` | 14 (23) | native_cpu + CUDA | netlib + cuBLAS | no |
| `tegra` | `tegra` | `nvcr.io/nvidia/l4t-cuda:12.2.12-devel` (Ubuntu 22.04) | 12 (20) | native_cpu + CUDA | netlib + cuBLAS | no |

These replace the old `mdnf1992/sycl-dev:{latest,generic,cuda,tegra}` images. oneMath's generic (pure SYCL) BLAS backend is no longer a variant: build it with `--docker-arg=--build-arg=ONEMATH_BACKENDS=generic`.

Notes:

- `nvcr.io/nvidia/l4t-cuda` has no `12.6.11-devel` tag (only `12.6.11-runtime`, without nvcc or headers), so the Tegra variant uses CUDA 12.2.12 (JetPack 6.0, Ubuntu 22.04). Change `TEGRA_BASE` if a newer devel image appears.
- Ubuntu 22.04 has GCC 12 (C++20). If msensor needs GCC 13 there, add the ubuntu-toolchain PPA in the `os-tegra` stage (see the comment in the Dockerfile).
- DPC++ is pinned to the commit moptim was validated with. Its CUDA support with CUDA 13.1 (`cuda`) and 12.2 (`tegra`) is **unverified**: only the CPU (`native_cpu`) path is exercised here, and running the CUDA backends needs an NVIDIA host. Override `DPCPP_REF` per variant if needed.

## Pins and build arguments

Pass them as `--docker-arg=--build-arg=NAME=value` (or `--build-workers N` for `BUILD_WORKERS`).

| Argument | Default | Meaning |
|---|---|---|
| `DEBIAN_BASE` | `debian:sid-slim@sha256:ec3fa4e0…a65db` | Debian base image |
| `DEBIAN_SNAPSHOT` | `20261116T212858Z` | snapshot.debian.org time of the apt packages; empty = live sid |
| `CUDA_BASE`, `TEGRA_BASE` | see the table | Ubuntu bases of the CUDA variants |
| `CMAKE_VERSION` | `4.4.2` | CMake binary (arch-aware) |
| `DPCPP_REF` | `fc235e9a9576f9771e0cab55aa31557095ef8091` | intel/llvm commit, fetched shallowly by SHA and verified |
| `DPCPP_ASSERTIONS` | `ON` | LLVM assertions (moptim was validated with them on) |
| `ONEMATH_REF` | `v0.9` | oneMath tag |
| `ONEMATH_BACKENDS` | empty | comma list of `netlib`, `cublas`, `generic`; empty = netlib, plus cublas on cuda/tegra (`generic` excludes the others) |
| `LAPACK_VERSION` | `3.12.1` | Reference LAPACK/CBLAS, installed in `/opt/lapack` |
| `OPENCV_REF` | `333974b268332108df496e93a976c96d052f9dde` | OpenCV `4.x` commit of 2026-11-16 |
| `NODE_VERSION` | `24.22.2` | Node.js binary on the Ubuntu variants (Debian uses its package, also 24.x) |
| `WITH_RPI_CAMERA` | empty | libcamera + rpicam-apps: empty = `ON` for debian, `OFF` otherwise |
| `BUILD_WORKERS` | `8` | parallel jobs of the builds inside the image (lower it, e.g. `--build-workers 6`, if the DPC++ build runs out of RAM) |

Always the same in every variant: gRPC `v1.84.0` (with its bundled protobuf and abseil, CMake configs in `/usr/local`), Eigen 5.0.1, fmt 11.1.1 and spdlog 1.15.3. Debian sid ships those Eigen, fmt and spdlog versions; the Ubuntu variants build them from source, because Ubuntu's Eigen is 3.4 (its NEON code does not compile in the DPC++ device pass) and its fmt 9/10 hits a consteval error with clang 23. Package lists per variant are in `packages/`.

## Building

```bash
./build.py -h
./build.py                         # mdnf1992/cpp-dev:latest (debian)
./build.py --variant cuda          # mdnf1992/cpp-dev:cuda
./build.py --variant tegra         # mdnf1992/cpp-dev:tegra
./build.py --all-variants          # all three, one after the other
./build.py --dry-run --all-variants   # print the docker commands only
```

Why not `docker build .`: the DPC++ build takes hours (about 2.5 to 5 h, then roughly 1 to 1.5 h for the rest) and needs a lot of RAM. `build.py` therefore builds a variant in two separate `docker build` invocations, never at the same time:

1. **The toolchain** (`/opt/sycl`, `/opt/lapack`): the `sycl_toolchain` stage, tagged `mdnf1992/cpp-dev:toolchain-<variant>-<hash12>`. The hash covers the Dockerfile stages that decide its content (the OS stage, `base`, `sycl_build`, `lapack`, `onemath`) and the build arguments, so changing `packages/`, `toolchain/`, the presets or the dev layers reuses it. Being a tagged image, builder garbage collection cannot evict it. It is built only if that tag is missing, or with `--rebuild-toolchain`. The LLVM source and object tree are in a BuildKit cache mount, so a failed or interrupted toolchain build resumes where it stopped.
2. **The image**: the `cpp_dev` stage, with `--build-arg SYCL_TOOLCHAIN=<that tag>`: the dev layers (`dev_deps`) plus a copy of the toolchain.

A lock keeps two `build.py` runs from overlapping. `build.py` never passes `--pull`.

Other options:

| Option | Effect |
|---|---|
| `--toolchain-only` | build only the toolchain image |
| `--rebuild-toolchain` | build the toolchain even if its tag exists |
| `--deps-only` | build only `dev_deps` (tag `deps-<variant>`): checks a variant's package set and the source builds without DPC++ |
| `--tag NAME` | tag of the image (default `latest` / `cuda` / `tegra`) |
| `--build-workers N` | `BUILD_WORKERS` |
| `--promote CANDIDATE` | see below |
| `--push`, `--platform`, `--docker-arg` | as before (only the image is pushed, not the toolchain image) |

The old `--sycl`, `--lapack`, `--generic`, `--cuda`, `--tegra`, `--all-sycl` and `--all-cuda` flags were removed and exit with a message naming the replacement.

### Candidate, promote, rollback

```bash
./build.py --tag candidate           # build next to the current image
# ... test it ...
./build.py --promote candidate       # latest -> latest-previous, candidate -> latest
docker tag mdnf1992/cpp-dev:latest-previous mdnf1992/cpp-dev:latest   # roll back
```

`--promote` works on the variant given by `--variant` (and its default tag, or `--tag`).

## Stages of the Dockerfile

`os-debian | os-cuda | os-tegra` (compilers and build tools; only the selected one is built) → `base` (+ CMake; no copy of `toolchain/`, so editing it never rebuilds DPC++) → `sycl_build` (DPC++, in `/opt/sycl`), `lapack` (`/opt/lapack`) → `onemath` (into `/opt/sycl`) → `sycl_toolchain` (scratch, only `/opt/sycl` and `/opt/lapack`). Independently, `dev_deps` (apt lists, uv, Node.js, gRPC, OpenCV, Eigen/fmt/spdlog on Ubuntu, libcamera and rpicam-apps if enabled, the toolchain files, opencode) and finally `cpp_dev` (the image: `dev_deps` + the toolchain, with checks).

`sycl_build`, `lapack` and `onemath` run no `apt-get`: everything they need comes from the OS stage. `/opt/sycl/share/cpp-dev/toolchain.env` records the DPC++ ref, the variant, the GCC version, the oneMath ref and backends, and the libc6 and libstdc++6 versions the toolchain was built against. `cpp_dev` stops the build if its libc6 or libstdc++6 is older than that.

## Environment in the container

- `/opt/sycl/bin` is **appended** to `PATH`: `clang-format`, `clangd` and `clang-tidy` stay the ones in `/usr/bin` (mslam's build runs `clang-format -i`), while `clang`, `clang++` and `sycl-ls` are DPC++'s. `SYCL_HOME=/opt/sycl`.
- `/opt/sycl/lib` is on the loader path through `/etc/ld.so.conf.d/zz-sycl.conf` (`ldconfig`), after everything else, and there is no `LD_LIBRARY_PATH`: the system `libOpenCL` and other system libraries win over the copies DPC++ ships.
- `/opt/lapack` (Reference LAPACK/CBLAS, for oneMath's netlib backend) is outside `/usr/local` so it cannot shadow the system BLAS for GCC builds.
- Eigen in the DPC++ device pass runs scalar: `-fsycl` consumers get that from moptim's CMake target (see moptim's readme).
- The build runs smoke tests: `sycl-ls` lists `native_cpu`, a `single_task` returns 42, a `-fsycl` translation unit including Eigen, spdlog, gRPC and OpenCV compiles, and `clang-format`, `clangd`, `clang-tidy` resolve to `/usr/bin`.

## Toolchains inside the container

`toolchain/` is copied to `/opt/toolchain` together with `/opt/toolchain/CMakePresets.json`:

- `gcc.cmake`: native GCC builds. It reads `CPP_DEV_GCC` and `CPP_DEV_CXX_STANDARD` from the image's environment (defaults 16 and 26, the Debian image's values).
- `arm-toolchain.cmake`: `arm-none-eabi` bare-metal builds.
- `sycl.cmake`: DPC++ builds (`/opt/sycl/bin/clang++`, C++23, `/opt/sycl` appended to `CMAKE_PREFIX_PATH`).

Use them from a project through the presets:

```bash
cmake --preset gcc && cmake --build --preset build-gcc
cmake --preset arm-none-eabi && cmake --build --preset build-arm-none-eabi
cmake --preset sycl && cmake --build --preset build-sycl
```

Copy `CMakePresets.json` into the project or include `/opt/toolchain/CMakePresets.json`.

## Dev containers

`.devcontainer/devcontainer.json` is the standard template: image `mdnf1992/cpp-dev`, the cmake-tools, clangd, cpptools (debugger) and protobuf extensions, CMake presets on, and one named volume per build directory (`${localWorkspaceFolderBasename}-build-${devcontainerId}`) so builds never land in a synced folder. Never mount one volume on two build directories: a build directory aliased across targets corrupts both. The file has commented examples for ports, hardware access (`--privileged`, `/dev`, `/run/udev`) and GPUs (`cpp-dev:cuda` or `:tegra` with `--gpus all` / `--runtime nvidia`).
