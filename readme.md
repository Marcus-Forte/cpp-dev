# cpp-dev: C++ development container

`mdnf1992/cpp-dev` is the C++ devcontainer image of moptim, mslam and msensor: GCC 16, CMake, the libraries and tools the repos need, and no SYCL. The SYCL (DPC++) image is a separate, optional build from `Dockerfile.sycl`, published as `mdnf1992/sycl-dev` (see [SYCL image](#sycl-image-dockerfilesycl)).

| File | Script | Image |
|---|---|---|
| `Dockerfile` | `build.py` | `mdnf1992/cpp-dev:latest` |
| `Dockerfile.sycl` | `build_sycl.py` | `mdnf1992/sycl-dev:{latest,cuda,tegra}` |

## Simple image (`Dockerfile`)

Contents:

- Base image: `debian:sid-slim`
- Toolchain and build: `gcc-16`, `g++-16`, `cmake` (`4.4.2` binary), `ninja`, `git`, `git-lfs`
- C/C++ tooling: `clangd`, `clang-format`, `clang-tidy`, `gdb`
- Core libraries: Eigen3, Boost, oneTBB (`libtbb-dev`), GoogleTest, GoogleMock, JSONCPP, spdlog, libi2c
- ARM MCU cross-toolchain: `gcc-arm-none-eabi`
- Python package manager: `uv`
- Node.js and npm (Debian packages)
- gRPC from source: `v1.84.0`
- OpenCV from source: `4.x` (with GStreamer enabled)
- Raspberry Pi camera stack from source: `libcamera` + `rpicam-apps`
- AI agent CLI: `opencode`

`packages/*.txt` are used only by the SYCL image; they are not read by this Dockerfile.

### Building

```bash
./build.py -h
./build.py                                   # mdnf1992/cpp-dev:latest
./build.py --build-arg BUILD_WORKERS=8       # parallel jobs of the source builds (Dockerfile default: 6)
./build.py --no-cache                        # any unknown argument goes to `docker build`
./build.py --platform linux/amd64,linux/arm64 --push   # multi-arch with buildx, then push
```

| Option | Effect |
|---|---|
| `--platform P` | docker platform (default: the host's); a comma list builds a multi-arch image with buildx |
| `-p`, `--push` | push the image to the registry after the build |
| `--docker-arg ARG` | extra `docker build` argument; may be repeated |
| other arguments | passed through to `docker build` |

The build takes 30 to 90 minutes (gRPC, OpenCV, libcamera). The command it runs is `docker build [args] [--push] [--platform P] -t mdnf1992/cpp-dev:latest .`

### Toolchains inside the container

`toolchain/` is copied to `/opt/toolchain` together with `/opt/toolchain/CMakePresets.json`:

- `/opt/toolchain/gcc.cmake`: native host builds using GCC 16 and C++26 (it reads `CPP_DEV_GCC` and `CPP_DEV_CXX_STANDARD` from the environment when set)
- `/opt/toolchain/arm-toolchain.cmake`: `arm-none-eabi` bare-metal microcontroller builds
- `/opt/toolchain/sycl.cmake`: SYCL builds using `/opt/sycl/bin/clang++` and C++23. It is inert in this image (there is no `/opt/sycl`); it works in `mdnf1992/sycl-dev`.

Copy `CMakePresets.json` (or include `/opt/toolchain/CMakePresets.json`) in your project root and use the presets:

```bash
cmake --preset gcc && cmake --build --preset build-gcc
cmake --preset arm-none-eabi && cmake --build --preset build-arm-none-eabi
```

## SYCL image (`Dockerfile.sycl`)

An optional image with GCC and DPC++ (the `intel/llvm` SYCL compiler) side by side, plus oneMath, the libraries of the simple image (Eigen, gRPC, OpenCV, spdlog/fmt, oneTBB, GoogleTest, Boost, jsoncpp, ARM cross-compiler, gdb, clangd/clang-format/clang-tidy, `uv`, Node.js, opencode) and guaranteed SYCL support. It is not what the repos' devcontainers use by default.

`Dockerfile.sycl` is one file; the variants come from its `VARIANT` build argument. Always build through `./build_sycl.py` (which passes `-f Dockerfile.sycl`), never a bare `docker build` (see [Building](#building-1)).

### Variants

| Variant | Tag | OS stage base | GCC (C++) | DPC++ backends | oneMath backends | Pi camera stack |
|---|---|---|---|---|---|---|
| `debian` (default) | `latest` | `debian:sid-slim@sha256:ec3fa4e0…` + apt snapshot `20261116T212858Z` | 16 (26) | native_cpu | netlib | yes |
| `cuda` | `cuda` | `nvidia/cuda:13.1.0-devel-ubuntu24.04` | 14 (23) | native_cpu + CUDA | netlib + cuBLAS | no |
| `tegra` | `tegra` | `nvcr.io/nvidia/l4t-cuda:12.2.12-devel` (Ubuntu 22.04) | 12 (20) | native_cpu + CUDA | netlib + cuBLAS | no |

The variants reuse the tags of the older `mdnf1992/sycl-dev:{latest,generic,cuda,tegra}` images. `generic` is no longer a variant: oneMath's generic (pure SYCL) BLAS backend can still be built with `--docker-arg=--build-arg=ONEMATH_BACKENDS=generic`.

Notes:

- `nvcr.io/nvidia/l4t-cuda` has no `12.6.11-devel` tag (only `12.6.11-runtime`, without nvcc or headers), so the Tegra variant uses CUDA 12.2.12 (JetPack 6.0, Ubuntu 22.04). Change `TEGRA_BASE` if a newer devel image appears.
- Ubuntu 22.04 has GCC 12 (C++20). If msensor needs GCC 13 there, add the ubuntu-toolchain PPA in the `os-tegra` stage (see the comment in `Dockerfile.sycl`).
- DPC++ is pinned to the commit moptim was validated with. Its CUDA support with CUDA 13.1 (`cuda`) and 12.2 (`tegra`) is **unverified**: only the CPU (`native_cpu`) path is exercised here, and running the CUDA backends needs an NVIDIA host. Override `DPCPP_REF` per variant if needed.

### Pins and build arguments

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

### Building

```bash
./build_sycl.py -h
./build_sycl.py                         # mdnf1992/sycl-dev:latest (debian)
./build_sycl.py --variant cuda          # mdnf1992/sycl-dev:cuda
./build_sycl.py --variant tegra         # mdnf1992/sycl-dev:tegra
./build_sycl.py --all-variants          # all three, one after the other
./build_sycl.py --dry-run --all-variants   # print the docker commands only
```

Why not `docker build .`: the DPC++ build takes hours (about 2.5 to 5 h, then roughly 1 to 1.5 h for the rest) and needs a lot of RAM. `build_sycl.py` therefore builds a variant in two separate `docker build` invocations, never at the same time:

1. **The toolchain** (`/opt/sycl`, `/opt/lapack`): the `sycl_toolchain` stage, tagged `mdnf1992/sycl-dev:toolchain-<variant>-<hash12>`. The hash covers the `Dockerfile.sycl` stages that decide its content (the OS stage, `base`, `sycl_build`, `lapack`, `onemath`) and the build arguments, so changing `packages/`, `toolchain/`, the presets or the dev layers reuses it. Being a tagged image, builder garbage collection cannot evict it. It is built only if that tag is missing, or with `--rebuild-toolchain`. The LLVM source and object tree are in a BuildKit cache mount, so a failed or interrupted toolchain build resumes where it stopped.
2. **The image**: the `cpp_dev` stage, with `--build-arg SYCL_TOOLCHAIN=<that tag>`: the dev layers (`dev_deps`) plus a copy of the toolchain.

A lock keeps two `build_sycl.py` runs from overlapping. `build_sycl.py` never passes `--pull`.

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

#### Candidate, promote, rollback

```bash
./build_sycl.py --tag candidate           # build next to the current image
# ... test it ...
./build_sycl.py --promote candidate       # latest -> latest-previous, candidate -> latest
docker tag mdnf1992/sycl-dev:latest-previous mdnf1992/sycl-dev:latest   # roll back
```

`--promote` works on the variant given by `--variant` (and its default tag, or `--tag`).

#### Stages of Dockerfile.sycl

`os-debian | os-cuda | os-tegra` (compilers and build tools; only the selected one is built) → `base` (+ CMake; no copy of `toolchain/`, so editing it never rebuilds DPC++) → `sycl_build` (DPC++, in `/opt/sycl`), `lapack` (`/opt/lapack`) → `onemath` (into `/opt/sycl`) → `sycl_toolchain` (scratch, only `/opt/sycl` and `/opt/lapack`). Independently, `dev_deps` (apt lists, uv, Node.js, gRPC, OpenCV, Eigen/fmt/spdlog on Ubuntu, libcamera and rpicam-apps if enabled, the toolchain files, opencode) and finally `cpp_dev` (the image: `dev_deps` + the toolchain, with checks).

`sycl_build`, `lapack` and `onemath` run no `apt-get`: everything they need comes from the OS stage. `/opt/sycl/share/cpp-dev/toolchain.env` records the DPC++ ref, the variant, the GCC version, the oneMath ref and backends, and the libc6 and libstdc++6 versions the toolchain was built against. `cpp_dev` stops the build if its libc6 or libstdc++6 is older than that.

### Environment in the container

Use `/opt/toolchain/sycl.cmake` through `cmake --preset sycl && cmake --build --preset build-sycl` in this image.

- `/opt/sycl/bin` is **appended** to `PATH`: `clang-format`, `clangd` and `clang-tidy` stay the ones in `/usr/bin` (mslam's build runs `clang-format -i`), while `clang`, `clang++` and `sycl-ls` are DPC++'s. `SYCL_HOME=/opt/sycl`.
- Debian's `/etc/profile` resets `PATH`, so login shells would lose the `ENV` above. `/etc/profile.d/zz-sycl.sh` appends `/opt/sycl/bin` again (only if missing) and exports `SYCL_HOME`. VS Code devcontainers take their environment from a login shell (`userEnvProbe`), so without it `clang++` and `sycl-ls` would be missing in their terminals. The image build checks `bash -lc` too.
- `/opt/sycl/lib` is on the loader path through `/etc/ld.so.conf.d/zz-sycl.conf` (`ldconfig`), after everything else, and there is no `LD_LIBRARY_PATH`: the system `libOpenCL` and other system libraries win over the copies DPC++ ships.
- apt resolves udev's `systemd | systemd-standalone-sysusers` dependency to `systemd-standalone-sysusers`, so, unlike the pre-fold image, `systemd` and `dbus` are not installed. They are not used in the container; add `systemd` to `packages/debian.txt` if needed.
- `/opt/lapack` (Reference LAPACK/CBLAS, for oneMath's netlib backend) is outside `/usr/local` so it cannot shadow the system BLAS for GCC builds.
- Eigen in the DPC++ device pass runs scalar: a `-fsycl` project in this image must add the device-pass flags itself: `-Xsycl-target-frontend=<triple> -DEIGEN_DONT_VECTORIZE`.
- On arm64 the `native_cpu` device front end crashes (`ItaniumMangle`, "unexpected Neon vector element type") on `<arm_neon.h>`, which OpenCV and abseil (so protobuf and gRPC) include under `__ARM_NEON`. A `-fsycl` project must add `-Xsycl-target-frontend=native_cpu -U__ARM_NEON -Xsycl-target-frontend=native_cpu -U__ARM_NEON__` (device pass only) itself. Including `<arm_neon.h>` directly in a SYCL translation unit still crashes this compiler.
- With GCC >= 16 libstdc++, DPC++ rejects `std::copy`, `std::distance` and `std::ranges` algorithms on iterators in kernels (a false positive: `default_initializable` contains `::new`, reported as "SYCL kernel cannot allocate storage"), and `std::sort` (recursion). Device code should use loops or `__builtin_memcpy`; `std::fill`, `std::min`/`std::max`, `std::array` and `std::swap` are fine.
- The build runs smoke tests: `sycl-ls` lists `native_cpu`, a `single_task` returns 42, a `-fsycl` translation unit including Eigen, spdlog, gRPC, protobuf and OpenCV compiles, and `clang-format`, `clangd`, `clang-tidy` resolve to `/usr/bin`.

## Dev containers

`.devcontainer/devcontainer.json` is the standard template: image `mdnf1992/cpp-dev`, the cmake-tools, clangd, cpptools (debugger) and protobuf extensions, CMake presets on, and one named volume per build directory (`${localWorkspaceFolderBasename}-build-${devcontainerId}`) so builds never land in a synced folder. Never mount one volume on two build directories: a build directory aliased across targets corrupts both. The file has commented examples for ports, hardware access (`--privileged`, `/dev`, `/run/udev`) and GPUs (`mdnf1992/sycl-dev:cuda` or `:tegra` with `--gpus all` / `--runtime nvidia`).
