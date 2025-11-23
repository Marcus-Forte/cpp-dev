#!/bin/bash

# Configuration
IMAGE_NAME="mdnf1992/cpp-dev"
PUSH=false
PLATFORM=""

# Helper function for help menu
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -t <target>   Target to build. Options: [native]"
    echo "  --platform <platform>  Docker platform to build for when using native (default is host)."
    echo "  -p            Push to registry after build"
    echo "  -h            Show this help message"
    exit 1
}

build_native() {
    local TAG="${IMAGE_NAME}:latest"
    local PLAT="${PLATFORM:-}"
    echo "--- Building Native Version ($TAG) ---"

    local BUILD_CMD="docker build"
    if [ -n "$PLAT" ]; then
        BUILD_CMD="$BUILD_CMD --platform $PLAT"
    fi
    $BUILD_CMD \
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
    native)
        build_native
        ;;
    *)
        echo "Invalid target: $TARGET"
        usage
        ;;
esac

echo "Done."