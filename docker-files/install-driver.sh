#!/bin/bash

# Install Graphics Driver
# Author: Dmitri Rubinstein <dmitri.rubinstein@dfki.de>
# Copyright 2016 - 2017, DFKI GmbH
# SPDX-License-Identifier: GPL-3.0+

# Load configuration
if [[ -f "/config.sh" ]]; then
    source "/config.sh"
fi

if [[ -z "$DRIVER_INSTALLER_MODE" ]]; then
    DRIVER_INSTALLER_MODE=run-time
fi

if [[ -z "$DRIVER_INSTALLER_TYPE" ]]; then
    DRIVER_INSTALLER_TYPE=detect
fi

if [[ -z "$DRIVER_INSTALLER" ]]; then
    DRIVER_INSTALLER=/opt/drivers
fi

info() {
    echo >&2 "[install-driver.sh] info: $*"
}

error() {
    echo >&2 "* [install-driver.sh] Error: $*"
}

fatal() {
    error "$@"
    exit 1
}

usage() {
    echo "Dockerizer Graphics Driver Installer"
    echo
    echo "This script will perform following steps:"
    echo " * Load configuration from /config.sh"
    echo ""
    echo "$0 [options]"
    echo "options:"
    echo "      --build-time           Pass when executed at container build-time"
    echo "      --run-time             Pass when executed at container run-time"
    echo "      --driver-installer-type="
    echo "                             One of detect | nvidia | amd | intel | '' "
    echo "                             (default $DRIVER_INSTALLER_TYPE)"
    echo "      --driver-installer="
    echo "                             Path to driver installer file or directory"
    echo "                             If directory is specified install-driver.sh will search for"
    echo "                             driver executable there."
    echo "      --driver-installer-mode="
    echo "                             Mode in which install driver. Either build-time or run-time."
    echo "      --help                 Display this help and exit"
}

MODE=build-time

while [[ $# > 0 ]]; do
    case "$1" in
        --build-time)
            MODE=build-time
            shift
            ;;
        --run-time)
            MODE=run-time
            shift
            ;;
        --driver-installer-type)
            DRIVER_INSTALLER_TYPE="$2"
            shift 2
            ;;
        --driver-installer-type=*)
            DRIVER_INSTALLER_TYPE="${1#*=}"
            shift
            ;;
        --driver-installer)
            DRIVER_INSTALLER="$2"
            shift 2
            ;;
        --driver-installer=*)
            DRIVER_INSTALLER="${1#*=}"
            shift
            ;;
        --driver-installer-mode)
            DRIVER_INSTALLER_MODE="$2"
            shift 2
            ;;
        --driver-installer=*)
            DRIVER_INSTALLER_MODE="${1#*=}"
            shift
            ;;
        --help)
            usage
            exit
            ;;
        --)
            shift
            break
            ;;
        -*)
            fatal "Unknown option $1"
            ;;
        *)
            break
            ;;
    esac
done

case "$DRIVER_INSTALLER_MODE" in
    build-time|run-time) ;;
    *) fatal "Unknown driver installer mode '$DRIVER_INSTALLER_MODE'";;
esac

info "MODE=$MODE"
info "DRIVER_INSTALLER=$DRIVER_INSTALLER"
info "DRIVER_INSTALLER_TYPE=$DRIVER_INSTALLER_TYPE"
info "DRIVER_INSTALLER_MODE=$DRIVER_INSTALLER_MODE"

driver-type-matches() {
    test "$DRIVER_INSTALLER_TYPE" = "detect" -o "$DRIVER_INSTALLER_TYPE" = "$1"
}

add-link() {
    local src=$1
    local dest=$2

    if [ ! -e "$src" ]; then
        rm -f "$src" && \
            ln -s "$dest" "$src" && \
            echo "Added link $src -> $dest"
    fi
}

install-nvidia-driver() {
    local exit_code=0
    sh "$1" --accept-license --ui=none --no-questions --no-nouveau-check \
       --no-network --no-kernel-module --no-x-check
    exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        return $exit_code
    fi

    tar -cjvf /nvidia-opengl.tar.bz2 \
        /usr/lib/x86_64-linux-gnu/libGL* \
        /usr/lib/x86_64-linux-gnu/libgl* \
        /usr/lib/x86_64-linux-gnu/mesa* \
        /usr/lib/xorg/modules/extensions

    # Fix missing links
    add-link /usr/lib/libGL.so /usr/lib/libGL.so.1
    add-link /usr/lib/x86_64-linux-gnu/mesa/libGL.so.1 /usr/lib/libGL.so.1
    #add-link /usr/lib/x86_64-linux-gnu/mesa/libGL.so.1.2.0 /usr/lib/libGL.so.1
    return $exit_code
}

get-nvidia-driver-installer-version() {
    if grep -q NVIDIA "$1"; then
        local nvidia_driver_version
        if nvidia_driver_version=$(sh "$1" --info | \
                                          awk '/Identification/ { for (i = 1; i <= NF; i++) { if (i+3 <= NF && $i == "Driver" && $(i+1) == "for" ) { print $(i+3); } } }'); then
            if [ -n "$nvidia_driver_version" ]; then
                echo "$nvidia_driver_version"
                return 0
            fi
        fi
    fi
    return 1
}

if [[ "$MODE" = "run-time" ]]; then
    GFX_CARD=$(lspci -nn | grep '\[03')

    info "GFX_CARD='$GFX_CARD'"
else
    GFX_CARD=
fi

run_driver_installer=()           # filename
run_driver_installer_type=()      # nvidia | intel
run_driver_installer_id=()        # e.g. driver version

detect-driver-installer() {
    local fn=$1
    local allowed_type=$2 # optional
    if [[ -f "$fn" ]]; then
        # Check NVIDIA driver
        local nvidia_driver_version
        if nvidia_driver_version=$(get-nvidia-driver-installer-version "$fn"); then
            if [[ $# -eq 1 || "$allowed_type" == "detect" || "$allowed_type" == "nvidia" ]]; then
                info "NVIDIA driver version: $nvidia_driver_version"

                run_driver_installer+=("$fn")
                run_driver_installer_type+=(nvidia)
                run_driver_installer_id+=("$nvidia_driver_version")
                return 0
            fi
        fi
        # Add here more files to check
    fi
    return 1
}

if [[ -n "$DRIVER_INSTALLER_TYPE" ]]; then
    # Driver installer type is not empty

    if [[ -d "$DRIVER_INSTALLER" ]]; then
        # Search for driver installers in specified directory, use auto-detection

        info "Driver installer is a directory, non-recursive search for a driver installer file"
        for fn in "$DRIVER_INSTALLER"/*; do
            detect-driver-installer "$fn" "$DRIVER_INSTALLER_TYPE"
        done
    else
        # Driver installer is a file

        if [[ "$DRIVER_INSTALLER_TYPE" = "detect" ]]; then
            info "Trying to detect driver type"

            if ! detect-driver-installer "$DRIVER_INSTALLER" "$DRIVER_INSTALLER_TYPE"; then
                error "Could not detect driver installer type"
            fi
        else
            run_driver_installer+=("$DRIVER_INSTALLER")
            run_driver_installer_type+=("$DRIVER_INSTALLER_TYPE")
            run_driver_installer_id+=('')
        fi
    fi

    if [[ "${#run_driver_installer[@]}" -gt 0 && "${#run_driver_installer_type[@]}" -gt 0 ]]; then
        info "Found ${#run_driver_installer[@]} driver installers"
    else
        fatal "Could not find driver installer"
    fi
fi

# Run driver installers

NVIDIA_GFX_CARD=
NVIDIA_HOST_DRIVER_VERSION=

nvidia-driver-installer() {
    local drv_fn=$1
    local drv_id=$2

    if [[ "$DRIVER_INSTALLER_MODE" == "$MODE" ]]; then

        if [[ "$MODE" == "run-time" ]]; then
            # We can check graphics card only at run-time

            if [[ -z "$NVIDIA_GFX_CARD" ]]; then
                if grep -qi NVIDIA <<<$GFX_CARD; then
                    NVIDIA_GFX_CARD=1
                else
                    NVIDIA_GFX_CARD=0
                fi
            fi

            if [[ "$NVIDIA_GFX_CARD" == 1 ]]; then
                info "Detected NVIDIA graphics card"
            else
                # In the case we have another card than NVIDIA don't abort,
                # but continue with a different driver
                error "No NVIDIA graphics card detected, driver installation aborted"
                return 1
            fi

            # Check version

            if [[ -z "$NVIDIA_HOST_DRIVER_VERSION" ]]; then
                NVIDIA_HOST_DRIVER_VERSION=$(\cat /proc/driver/nvidia/version | \
                                                 awk '/NVIDIA/ { for (i = 1; i <= NF; i++) { if (i+2 <= NF && $i == "Kernel" && $(i+1) == "Module" ) { print $(i+2); } } }')
            fi

            info "NVIDIA driver host version: $NVIDIA_HOST_DRIVER_VERSION"

            if [[ -z "drv_id" ]]; then
                drv_id=$(get-nvidia-driver-installer-version "$drv_fn")
            fi

            info "NVIDIA driver version: $drv_id"

            if [[ "$NVIDIA_HOST_DRIVER_VERSION" != "$drv_id" ]]; then
                error "Driver version mismatch: host: $NVIDIA_HOST_DRIVER_VERSION  != driver: $drv_id"
                return 1
            fi
        fi

        if ! install-nvidia-driver "$drv_fn"; then
            fatal "Could not install NVIDIA driver"
        fi
    fi

    # X Configuration (only at run-time)

    local bus_ids
    if [[ "$MODE" = "run-time" ]]; then
        info "Configure NVIDIA card, run nvidia-xconfig"
        if type -t nvidia-xconfig &> /dev/null; then
            bus_ids=( $(${SUDO} nvidia-xconfig --query-gpu-info | \
                            sed -n '/PCI BusID/ s/[^:]\+:[[:space:]]*PCI:\([^[:space:]]*\)[[:space:]]*/--busid=\1/p') )
            info "NVIDIA driver detected bus IDs: ${bus_ids[@]}"
            ${SUDO} nvidia-xconfig -a --use-display-device=None \
                    --enable-all-gpus "${bus_ids[@]}" --virtual=${WIDTH:-1280}x${HEIGHT:-1024}
        fi
    fi

    exit 0
}

# Driver installation

drv_num=${#run_driver_installer[@]}
for (( i=0; i<drv_num; i++)); do
    drv_fn=${run_driver_installer[$i]}
    drv_type=${run_driver_installer_type[$i]}
    drv_id=${run_driver_installer_id[$i]}

    case "$drv_type" in
        nvidia)
            nvidia-driver-installer "$drv_fn" "$drv_id"
        ;;
    esac
done

if [[ "$MODE" = "run-time" ]]; then
    # Default device handling

    if grep -qi Intel <<<$GFX_CARD; then
        info "Detected Intel graphics card"
        if [[ -e /dev/dri/card0 ]]; then
            ${SUDO} chmod 666 /dev/dri/card0
        fi
    fi

    # FIXME: Following is not neccessarily useful

    # Restore Xorg OpenGL libraries
    if [[ -e "/xorg-opengl.tar.bz2" ]]; then
        info "Restore Xorg OpenGL files"

        # Does not work !
        #for f in tar tf /nvidia-opengl.tar.bz2; do
        #    if [ -e "$f" -a ! -d "$f" ]; then
        #        ${SUDO} rm "$f"
        #    fi
        #done

        ${SUDO} tar -xvf /xorg-opengl.tar.bz2 -C /
    fi
fi
