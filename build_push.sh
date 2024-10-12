# /bin/bash

DEVCONTAINER_NAME=mdnf1992/cpp-dev
TAG=latest

docker build -t $DEVCONTAINER_NAME:$TAG .
docker push $DEVCONTAINER_NAME:$TAG