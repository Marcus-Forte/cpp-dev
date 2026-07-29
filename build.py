#!/usr/bin/env python3

import argparse
import subprocess
import sys


IMAGE_NAME = "mdnf1992/cpp-dev"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the cpp-dev Docker image.",
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
    return parser.parse_args()


def build_native(push: bool, platform: str | None) -> None:
    tag = f"{IMAGE_NAME}:latest"
    print(f"--- Building Native Version ({tag}) ---")

    cmd = ["docker", "build"]
    if push:
        cmd.append("--push")
    if platform:
        cmd.extend(["--platform", platform])
    cmd.extend(["-t", tag, "."])

    subprocess.run(cmd, check=True)


def main() -> int:
    args = parse_args()
    try:
        build_native(push=args.push, platform=args.platform)
    except subprocess.CalledProcessError as exc:
        return exc.returncode

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())