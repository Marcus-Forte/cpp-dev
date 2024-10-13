# /bin/bash

DEVCONTAINER_NAME=mdnf1992/cpp-dev
TAG=latest

OPTSTRING="ph"
PUSH=false
while getopts $OPTSTRING opt; do
    case $opt in
    h)
    echo "build_push.sh [-p push to registry]"
    exit 0
    ;;
    p) 
    echo "p"
    PUSH=true
    ;;
    esac
done

docker build --platform=linux/arm64,linux/amd64 -t $DEVCONTAINER_NAME:$TAG .

if $PUSH; then
docker push $DEVCONTAINER_NAME:$TAG
fi