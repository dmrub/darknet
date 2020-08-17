#!/bin/bash

THIS_DIR=$( (cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) )

IMAGE=darknet-demo

set -xe
docker build \
       --network=host \
       -t "$IMAGE" \
       -f "Dockerfile" \
       "$THIS_DIR"
