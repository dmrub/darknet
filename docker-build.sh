#!/bin/bash

THIS_DIR=$( (cd "$(dirname -- "$BASH_SOURCE")" && pwd -P) )

IMAGE=darknet

set -xe
docker build \
       -t "$IMAGE" \
       -f "Dockerfile" \
       "$THIS_DIR"
