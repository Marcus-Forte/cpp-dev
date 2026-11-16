#!/usr/bin/env python3

from __future__ import annotations

import argparse
import subprocess
import sys


CPP_DEV_IMAGE = "mdnf1992/cpp-dev"
SYCL_DEV_IMAGE = "mdnf1992/sycl-dev"

SYCL_TARGETS: dict[str, dict[str, str | bool]] = {
    "lapack": {
        "description": "SYCL + oneMath (Lapack/Netlib)",
        "base_img": f"{CPP_DEV_IMAGE}:latest",
        "target": "onemath_lapack",
        "tag": f"{SYCL_DEV_IMAGE}:latest",
        "cuda": False,
    },
    "cuda": {
        "description": "SYCL + oneMath (cuBLAS + Lapack)",
        "base_img": "nvidia/cuda:13.1.0-devel-ubuntu24.04",
        "target": "onemath_cublas",
        "tag": f"{SYCL_DEV_IMAGE}:cuda",
        "cuda": True,
    },
    "generic": {
        "description": "SYCL + oneMath (Generic pure-SYCL BLAS)",
        "base_img": f"{CPP_DEV_IMAGE}:latest",
        "target": "onemath_generic",
        "tag": f"{SYCL_DEV_IMAGE}:generic",
        "cuda": False,
    },
    "tegra": {
        "description": "SYCL + oneMath for Jetson/Tegra (cuBLAS + Lapack)",
        "base_img": "nvcr.io/nvidia/l4t-cuda:12.6.11-devel",
        "target": "onemath_cublas",
        "tag": f"{SYCL_DEV_IMAGE}:tegra",
        "cuda": True,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the cpp-dev and sycl-dev Docker images.",
    )
    parser.add_argument(
        "--platform",
        help="Docker platform to build for (default is host platform).",
    )
    parser.add_argument(
        "-p",
        "--push",
        action="store_true",
        help="Push to registry after build.",
    )
    parser.add_argument(
        "--sycl",
        "--lapack",
        dest="sycl_lapack",
        action="store_true",
        help="Build the default SYCL + oneMath (Lapack) image (mdnf1992/sycl-dev:latest).",
    )
    parser.add_argument(
        "--cuda",
        dest="sycl_cuda",
        action="store_true",
        help="Build the SYCL + CUDA (cuBLAS) image (mdnf1992/sycl-dev:cuda).",
    )
    parser.add_argument(
        "--generic",
        dest="sycl_generic",
        action="store_true",
        help="Build the SYCL + Generic oneMath image (mdnf1992/sycl-dev:generic).",
    )
    parser.add_argument(
        "--tegra",
        dest="sycl_tegra",
        action="store_true",
        help="Build the SYCL + Tegra L4T CUDA image (mdnf1992/sycl-dev:tegra).",
    )
    parser.add_argument(
        "--all-sycl",
        action="store_true",
        help="Build all SYCL image variants (lapack, cuda, generic, tegra).",
    )
    parser.add_argument(
        "--docker-arg",
        dest="docker_args",
        action="append",
        nargs="?",
        default=[],
        metavar="ARG",
        help="Additional argument to pass to the docker build command. May be specified multiple times.",
    )
    args, extra_args = parser.parse_known_args()

    docker_args = [arg for arg in args.docker_args if arg is not None]
    docker_args.extend(extra_args)
    args.docker_args = docker_args
    return args


def build_cpp_dev(push: bool, platform: str | None, docker_args: list[str]) -> None:
    tag = f"{CPP_DEV_IMAGE}:latest"
    print(f"--- Building C++ Dev Image ({tag}) ---", flush=True)

    cmd = ["docker", "build"]
    if docker_args:
        cmd.extend(docker_args)
    if push:
        cmd.append("--push")
    if platform:
        cmd.extend(["--platform", platform])
    cmd.extend(["-t", tag, "."])

    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def build_sycl_variant(
    variant: str,
    push: bool,
    platform: str | None,
    docker_args: list[str],
) -> None:
    spec = SYCL_TARGETS[variant]
    tag = str(spec["tag"])
    base_img = str(spec["base_img"])
    target = str(spec["target"])
    cuda = bool(spec["cuda"])

    print(f"--- Building {spec['description']} ({tag}) ---", flush=True)

    cmd = ["docker", "build", "-f", "Dockerfile.sycl"]
    if docker_args:
        cmd.extend(docker_args)
    if push:
        cmd.append("--push")
    if platform:
        cmd.extend(["--platform", platform])
    if cuda:
        cmd.extend(["--build-arg", "SYCL_CUDA_FLAG=--cuda"])
    cmd.extend(
        [
            "--build-arg",
            f"BASE_IMG={base_img}",
            "--target",
            target,
            "-t",
            tag,
            ".",
        ]
    )

    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def main() -> int:
    args = parse_args()

    selected_sycl: list[str] = []
    if args.all_sycl:
        selected_sycl = ["lapack", "cuda", "generic", "tegra"]
    else:
        if args.sycl_lapack:
            selected_sycl.append("lapack")
        if args.sycl_cuda:
            selected_sycl.append("cuda")
        if args.sycl_generic:
            selected_sycl.append("generic")
        if args.sycl_tegra:
            selected_sycl.append("tegra")

    try:
        if not selected_sycl:
            build_cpp_dev(
                push=args.push,
                platform=args.platform,
                docker_args=args.docker_args,
            )
        else:
            for variant in selected_sycl:
                build_sycl_variant(
                    variant=variant,
                    push=args.push,
                    platform=args.platform,
                    docker_args=args.docker_args,
                )
    except subprocess.CalledProcessError as exc:
        return exc.returncode

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
