#!/usr/bin/env bash

THIS_DIR=$( (cd "$(dirname -- "$BASH_SOURCE")" && pwd -P) )

export LD_LIBRARY_PATH=$THIS_DIR:$LD_LIBRARY_PATH
export PYTHONPATH=$THIS_DIR/python:$PYTHONPATH
set -xe
exec python/stream_demo.py "$@"
