#!/bin/bash

THIS_DIR=$( (cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) )

IMAGE=darknet-demo

set -xe
docker run --rm -it --privileged --net host \
       --volume="$THIS_DIR/workspace:/workspace" \
       --volume="$THIS_DIR/drivers:/opt/drivers" \
       --volume=/var/run/dbus:/var/run/dbus \
       --device /dev/video0:/dev/video0 \
       --device /dev/nvidia0:/dev/nvidia0 \
       --device /dev/nvidiactl:/dev/nvidiactl \
       --device /dev/bus/usb:/dev/bus/usb:rwm \
       --device /dev/dri:/dev/dri \
       -- \
       "$IMAGE" \
       "$@"
