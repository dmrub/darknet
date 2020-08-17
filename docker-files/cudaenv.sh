# shellcheck shell=sh
for CUDA_HOME in /usr/local/cuda /usr/local/cuda-*; do
    if [ -d "$CUDA_HOME" ]; then
        export CUDA_HOME
        export PATH=$PATH:$CUDA_HOME/bin
        if [ -d "$CUDA_HOME/lib64" ]; then
            export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CUDA_HOME/lib64
        elif [ -d "$CUDA_HOME/lib" ]; then
            export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$CUDA_HOME/lib
        fi
        if [ -d "$CUDA_HOME/targets/x86_64-linux/lib/stubs" ]; then
            export CUDA_STUBS=$CUDA_HOME/targets/x86_64-linux/lib/stubs
        fi
        break;
    fi
done

if [ "$PS1" ]; then
    # Interactive mode
    if [ "${BASH:-}" ] && [ "$BASH" != "/bin/sh" ]; then
        :
    fi
fi
