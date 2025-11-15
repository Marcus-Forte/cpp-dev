#!/bin/bash

# Configuration
IMAGE_NAME="mdnf1992/cpp-dev"
PUSH=false

# Helper function for help menu
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -t <target>   Target architecture to build. Options: [pi5, pizero2, native, all]"
    echo "  -p            Push to registry after build"
    echo "  -h            Show this help message"
    exit 1
}

# Function to build specifically for Raspberry Pi 5
# CPU: Cortex-A76 (ARMv8.2-A)
build_pi5() {
    local TAG="${IMAGE_NAME}:pi5"
    echo "--- Building for Raspberry Pi 5 ($TAG) ---"
    
    # We build a linux/arm64 image. 
    # We use the native compilers (g++, gcc) because the container itself is ARM64.
    docker build \
        --platform linux/arm64 \
        --build-arg TARGET_CXX_FLAGS="-mcpu=cortex-a76 -O3 -DNDEBUG" \
        -t "$TAG" .

    if [ "$PUSH" = true ]; then docker push "$TAG"; fi
}

# Function to build for Raspberry Pi Zero 2 W
# CPU: Cortex-A53 (ARMv8-A) - Also works for Pi 3 and Pi 4 (though Pi4 is A72)
build_pizero2() {
    local TAG="${IMAGE_NAME}:pizero2"
    echo "--- Building for Raspberry Pi Zero 2 W ($TAG) ---"

    docker build \
        --platform linux/arm64 \
        --build-arg TARGET_CXX_FLAGS="-mcpu=cortex-a53 -mtune=cortex-a53 -O3 -DNDEBUG" \
        -t "$TAG" .

    if [ "$PUSH" = true ]; then docker push "$TAG"; fi
}

# Function to build for the current host (likely x86/amd64)
# Good for testing logic on your laptop before deploying to Pi
build_native() {
    local TAG="${IMAGE_NAME}:latest"
    echo "--- Building Native/Host Version ($TAG) ---"

    docker build \
        --build-arg TARGET_CXX_FLAGS="-march=native -O3" \
        -t "$TAG" .

    if [ "$PUSH" = true ]; then docker push "$TAG"; fi
}

# Parse Arguments
TARGET=""
while getopts "t:ph" opt; do
    case $opt in
        t) TARGET=$OPTARG ;;
        p) PUSH=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validation
if [ -z "$TARGET" ]; then
    echo "Error: You must specify a target with -t"
    usage
fi

# Execution Logic
case $TARGET in
    pi5)
        build_pi5
        ;;
    pizero2)
        build_pizero2
        ;;
    native)
        build_native
        ;;
    all)
        build_native
        build_pi5
        build_pizero2
        ;;
    *)
        echo "Invalid target: $TARGET"
        usage
        ;;
esac

echo "Done."