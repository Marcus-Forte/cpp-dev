#!/usr/bin/env python3
"""Build the mdnf1992/cpp-dev images (GCC + DPC++/SYCL) from the single Dockerfile.

Each variant (debian, cuda, tegra) is built in two separate `docker build` invocations, never at
the same time (a DPC++ build needs a lot of RAM):

1. the toolchain (/opt/sycl, /opt/lapack): the `sycl_toolchain` stage, tagged
   mdnf1992/cpp-dev:toolchain-<variant>-<hash12>. It takes hours, so it is built only when that
   tag is missing (or with --rebuild-toolchain). The hash covers the stages and build args that
   decide its content, so editing only the dev layers, toolchain/ or packages/ reuses it. Being a
   tagged image, builder garbage collection cannot evict it.
2. the image: the `cpp_dev` stage with --build-arg SYCL_TOOLCHAIN=<that tag>.

It never passes --pull: the base images and the toolchain images come from the local store.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

IMAGE = "mdnf1992/cpp-dev"
HERE = Path(__file__).resolve().parent
DOCKERFILE = HERE / "Dockerfile"

# variant -> default tag of the image
VARIANT_TAGS = {"debian": "latest", "cuda": "cuda", "tegra": "tegra"}

# Build args that only affect the dev layers or how the toolchain is built, not what it contains.
# They are left out of the toolchain hash.
NON_TOOLCHAIN_ARGS = {
    "BUILD_WORKERS",
    "LLVM_PARALLEL_LINK_JOBS",
    "WITH_RPI_CAMERA",
    "OPENCV_REF",
    "NODE_VERSION",
    "SYCL_TOOLCHAIN",
    "VARIANT",
}

RETIRED_FLAGS = {
    "--sycl": "SYCL is in every image now: use `./build.py` (--variant debian, the default)",
    "--lapack": "SYCL and oneMath are in every image now: use `./build.py` (--variant debian, the default)",
    "--generic": "use `./build.py --docker-arg=--build-arg=ONEMATH_BACKENDS=generic` (the generic oneMath backend)",
    "--cuda": "use `./build.py --variant cuda`",
    "--tegra": "use `./build.py --variant tegra`",
    "--all-sycl": "use `./build.py --all-variants`",
    "--all-cuda": "use `./build.py --all-variants` (or --variant cuda / --variant tegra)",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the mdnf1992/cpp-dev images (GCC + DPC++/SYCL) from the single Dockerfile.",
        epilog="Any other argument is passed to `docker build`.",
    )
    parser.add_argument(
        "--variant",
        choices=sorted(VARIANT_TAGS),
        default="debian",
        help="debian (default, tag latest), cuda (tag cuda) or tegra (tag tegra).",
    )
    parser.add_argument(
        "--all-variants",
        action="store_true",
        help="Build debian, cuda and tegra, one after the other.",
    )
    parser.add_argument(
        "--tag",
        help="Tag of the image (default: latest / cuda / tegra, or deps-<variant> with --deps-only). "
        "Build a candidate with `--tag candidate`, then --promote it.",
    )
    parser.add_argument(
        "--toolchain-only",
        action="store_true",
        help="Only build the toolchain image (mdnf1992/cpp-dev:toolchain-<variant>-<hash12>).",
    )
    parser.add_argument(
        "--rebuild-toolchain",
        action="store_true",
        help="Build the toolchain image even if its tag exists (the BuildKit cache mount resumes).",
    )
    parser.add_argument(
        "--deps-only",
        action="store_true",
        help="Build only the dev_deps stage (apt lists and the source-built libraries, no DPC++): "
        "checks a variant's package set without the toolchain.",
    )
    parser.add_argument(
        "--build-workers",
        type=int,
        metavar="N",
        help="Parallel jobs of the builds inside the image (BUILD_WORKERS, default 8).",
    )
    parser.add_argument(
        "--promote",
        metavar="CANDIDATE",
        help="Do not build: retag the current image tag as <tag>-previous and CANDIDATE as the tag.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the docker commands without running them.",
    )
    parser.add_argument(
        "--platform",
        help="Docker platform to build for (default is host platform).",
    )
    parser.add_argument(
        "-p",
        "--push",
        action="store_true",
        help="Push the image to the registry after the build (the toolchain image stays local).",
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
    for flag in RETIRED_FLAGS:
        parser.add_argument(flag, action="store_true", help=argparse.SUPPRESS)
    args, extra_args = parser.parse_known_args()

    for flag, advice in RETIRED_FLAGS.items():
        if getattr(args, flag.lstrip("-").replace("-", "_")):
            parser.exit(2, f"build.py: {flag} was removed: {advice}\n")
    docker_args = [arg for arg in args.docker_args if arg is not None]
    docker_args.extend(extra_args)
    if any(arg == "--pull" or arg.startswith("--pull=") for arg in docker_args):
        parser.exit(2, "build.py: never --pull: the base and toolchain images come from the local store\n")
    args.docker_args = docker_args

    if args.all_variants and args.tag:
        parser.error("--tag names one image: use it with --variant, not --all-variants")
    if args.all_variants and args.promote:
        parser.error("--promote names one candidate tag: use it with --variant, not --all-variants")
    if args.toolchain_only and args.deps_only:
        parser.error("--toolchain-only and --deps-only exclude each other")
    return args


def build_args_of(docker_args: list[str]) -> dict[str, str]:
    """The --build-arg KEY=VALUE pairs among the docker arguments."""
    found: dict[str, str] = {}
    i = 0
    while i < len(docker_args):
        arg = docker_args[i]
        value = None
        if arg == "--build-arg" and i + 1 < len(docker_args):
            value = docker_args[i + 1]
            i += 1
        elif arg.startswith("--build-arg="):
            value = arg.split("=", 1)[1]
        if value is not None:
            key, _, val = value.partition("=")
            found[key] = val
        i += 1
    return found


def dockerfile_stages(text: str) -> dict[str, str]:
    """Dockerfile text per stage; "" is the text before the first FROM. Comments and blank lines
    are dropped so that documentation edits do not change the toolchain hash."""
    stages: dict[str, list[str]] = {"": []}
    current = ""
    for line in text.splitlines():
        stripped = line.strip()
        match = re.match(r"FROM\s+\S+\s+AS\s+(\S+)", stripped, re.IGNORECASE)
        if match:
            current = match.group(1)
            stages[current] = []
        if not stripped or stripped.startswith("#"):
            continue
        stages[current].append(line.rstrip())
    return {name: "\n".join(lines) for name, lines in stages.items()}


def toolchain_hash(variant: str, docker_args: list[str], platform: str | None) -> str:
    """Hash of what decides the toolchain: the preamble, os-<variant>, base, sycl_build, lapack,
    onemath and sycl_toolchain stages, and the build args that are not dev-layer-only."""
    stages = dockerfile_stages(DOCKERFILE.read_text())
    names = ["", f"os-{variant}", "base", "sycl_build", "lapack", "onemath", "sycl_toolchain"]
    digest = hashlib.sha256()
    digest.update(f"variant={variant}\nplatform={platform or ''}\n".encode())
    for name in names:
        digest.update(f"--- stage {name}\n{stages.get(name, '')}\n".encode())
    for key, value in sorted(build_args_of(docker_args).items()):
        if key not in NON_TOOLCHAIN_ARGS:
            digest.update(f"arg {key}={value}\n".encode())
    return digest.hexdigest()[:12]


def run(cmd: list[str], dry_run: bool) -> None:
    print("+", " ".join(cmd), flush=True)
    if not dry_run:
        subprocess.run(cmd, check=True)


def image_exists(ref: str) -> bool:
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", ref],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        return False
    return result.returncode == 0


def docker_build(
    variant: str,
    target: str,
    tag: str,
    extra_build_args: list[str],
    args: argparse.Namespace,
    push: bool,
) -> list[str]:
    cmd = ["docker", "build"]
    cmd.extend(args.docker_args)
    if push:
        cmd.append("--push")
    if args.platform:
        cmd.extend(["--platform", args.platform])
    cmd.extend(["--build-arg", f"VARIANT={variant}"])
    if args.build_workers:
        cmd.extend(["--build-arg", f"BUILD_WORKERS={args.build_workers}"])
    for build_arg in extra_build_args:
        cmd.extend(["--build-arg", build_arg])
    cmd.extend(["--target", target, "-t", tag, str(HERE)])
    return cmd


def build_variant(variant: str, args: argparse.Namespace) -> None:
    tag = args.tag or (f"deps-{variant}" if args.deps_only else VARIANT_TAGS[variant])
    image = f"{IMAGE}:{tag}"

    if args.deps_only:
        print(f"--- {variant}: dev_deps only ({image}) ---", flush=True)
        run(docker_build(variant, "dev_deps", image, [], args, push=False), args.dry_run)
        return

    toolchain = f"{IMAGE}:toolchain-{variant}-{toolchain_hash(variant, args.docker_args, args.platform)}"
    if args.rebuild_toolchain or not image_exists(toolchain):
        print(f"--- {variant}: building the toolchain ({toolchain}); this takes hours ---", flush=True)
        run(docker_build(variant, "sycl_toolchain", toolchain, [], args, push=False), args.dry_run)
    else:
        print(f"--- {variant}: toolchain {toolchain} exists, reusing it ---", flush=True)
    if args.toolchain_only:
        return

    print(f"--- {variant}: building {image} ---", flush=True)
    cmd = docker_build(variant, "cpp_dev", image, [f"SYCL_TOOLCHAIN={toolchain}"], args, push=args.push)
    run(cmd, args.dry_run)


def promote(variant: str, args: argparse.Namespace) -> None:
    tag = args.tag or VARIANT_TAGS[variant]
    candidate = args.promote if "/" in args.promote else f"{IMAGE}:{args.promote}"
    current = f"{IMAGE}:{tag}"
    if not args.dry_run and not image_exists(candidate):
        raise SystemExit(f"build.py: candidate image {candidate} does not exist")
    if args.dry_run or image_exists(current):
        run(["docker", "tag", current, f"{current}-previous"], args.dry_run)
    else:
        print(f"{current} does not exist: nothing to keep as {tag}-previous", flush=True)
    run(["docker", "tag", candidate, current], args.dry_run)
    print(f"Rollback: docker tag {current}-previous {current}", flush=True)


def main() -> int:
    args = parse_args()
    variants = list(VARIANT_TAGS) if args.all_variants else [args.variant]

    # One build.py at a time: a DPC++ build and the dev layers must not run concurrently (RAM).
    lock_file = open(Path(tempfile.gettempdir()) / "cpp-dev-build.lock", "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("build.py: another build.py is running (lock file in the temp dir); builds never run concurrently",
              file=sys.stderr)
        return 1

    try:
        for variant in variants:
            if args.promote:
                promote(variant, args)
            else:
                build_variant(variant, args)
    except subprocess.CalledProcessError as exc:
        return exc.returncode
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(exc.code, file=sys.stderr)
            return 1
        raise

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
