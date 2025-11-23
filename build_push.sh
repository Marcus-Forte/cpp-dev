#!/bin/bash

# Configuration
IMAGE_NAME="mdnf1992/cpp-dev"
PUSH=false
PLATFORM=""

# Helper function for help menu
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -t <target>   Target architecture to build. Options: [pi5, pizero2, arm64-generic, all]"
    echo "  --platform <platform>  Docker platform to build for (e.g., linux/arm64, linux/amd64). Defaults per target."
    echo "  -p            Push to registry after build"
    echo "  -h            Show this help message"
    exit 1
}

# Function to build specifically for Raspberry Pi 5
# CPU: Cortex-A76 (ARMv8.2-A)
build_pi5() {
    local TAG="${IMAGE_NAME}:pi5"
    local PLAT="${PLATFORM:-linux/arm64}"
    echo "--- Building for Raspberry Pi 5 ($TAG) ---"
    
    docker build \
        --platform "$PLAT" \
        --build-arg TOOLCHAIN_FILE=/opt/toolchains/pi5.cmake \
        -t "$TAG" .

    if [ "$PUSH" = true ]; then docker push "$TAG"; fi
}

# Function to build for Raspberry Pi Zero 2 W
# CPU: Cortex-A53 (ARMv8-A) - Also works for Pi 3 and Pi 4 (though Pi4 is A72)
build_pizero2() {
    local TAG="${IMAGE_NAME}:pizero2"
    local PLAT="${PLATFORM:-linux/arm64}"
    echo "--- Building for Raspberry Pi Zero 2 W ($TAG) ---"

    docker build \
        --platform "$PLAT" \
        --build-arg TOOLCHAIN_FILE=/opt/toolchains/pizero2.cmake \
        -t "$TAG" .

    if [ "$PUSH" = true ]; then docker push "$TAG"; fi
}

 # Function to build the generic ARM64 image using the portable toolchain
build_arm64_generic() {
    local TAG="${IMAGE_NAME}:latest"
    local PLAT="${PLATFORM:-}"
    echo "--- Building ARM64-Generic Version ($TAG) ---"

    local BUILD_CMD="docker build"
    if [ -n "$PLAT" ]; then
        BUILD_CMD="$BUILD_CMD --platform $PLAT"
    fi
    $BUILD_CMD \
        --build-arg TOOLCHAIN_FILE=/opt/toolchains/arm64-generic.cmake \
        -t "$TAG" .

    if [ "$PUSH" = true ]; then docker push "$TAG"; fi
}

# Parse Arguments
TARGET=""
while getopts "t:p-:h" opt; do
    case $opt in
        t) TARGET=$OPTARG ;;
        p) PUSH=true ;;
        h) usage ;;
        -)
            case "${OPTARG}" in
                platform)
                    PLATFORM="${!OPTIND}"; ((OPTIND++))
                    ;;
                *)
                    echo "Unknown option: --${OPTARG}"
                    usage
                    ;;
            esac
            ;;
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
    arm64-generic)
        build_arm64_generic
        ;;
    all)
        build_arm64_generic
        build_pi5
        build_pizero2
        ;;
    *)
        echo "Invalid target: $TARGET"
        usage
        ;;
esac

echo "Done."