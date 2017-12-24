#!/bin/bash

env >&2

message() {
    echo >&2 "[entrypoint.sh] $*"
}

info() {
    message "info: $*"
}

error() {
    echo >&2 "* [entrypoint.sh] Error: $*"
}

fatal() {
    error "$@"
    exit 1
}

message "info: EUID=$EUID args: $@"

if [[ $EUID -ne 0 ]]; then
    # change user back to root
    if [[ -x /usr/local/bin/su-entrypoint ]]; then
        exec /usr/local/bin/su-entrypoint --app-user="$(id -un)" "$@"
    else
        exec /usr/bin/sudo -E "$0" --app-user="$(id -un)" "$@"
    fi
fi

ENTRYPOINT_CONFIG="/entrypoint-config.sh"
APP_CONFIG=()

usage() {
    echo "Entrypoint Script"
    echo
    echo "This script will perform following steps:"
    echo " * Override application user if --app-user option is specified"
    echo " * Create application configuration in /config.sh file from"
    echo "   --app-config options"
    echo " * Load configuration from ${ENTRYPOINT_CONFIG} file"
    echo ""
    echo "$0 [options]"
    echo "options:"
    echo "      --app-user=            Run application with specified user"
    echo "                             (default $APP_USER)"
    echo "      --app-config=          Add configuration option to config.sh"
    echo "      --entrypoint-config=   Load entrypoint configuration from"
    echo "                             specified file (default: $ENTRYPOINT_CONFIG)"
    echo "      --help-entrypoint      Display this help and exit"
}

while [[ $# > 0 ]]; do
    case "$1" in
        --app-user)
            APP_USER="$2"
            shift 2
            ;;
        --app-user=*)
            APP_USER="${1#*=}"
            shift
            ;;
        --app-config)
            APP_CONFIG+=("$2")
            shift 2
            ;;
        --app-config=*)
            APP_CONFIG+=("${1#*=}")
            shift
            ;;
        --autorestart)
            AUTORESTART="$2"
            shift 2
            ;;
        --autorestart=*)
            AUTORESTART="${1#*=}"
            shift
            ;;
        --help-entrypoint)
            usage
            exit
            ;;
        --)
            shift
            break
            ;;
        -*)
            break
            ;;
        *)
            break
            ;;
    esac
done

info "APP_USER=$APP_USER"
info "APP_CONFIG=(${APP_CONFIG[@]})"
info "ENTRYPOINT_CONFIG=$ENTRYPOINT_CONFIG"

for ((i = 0; i < ${#APP_CONFIG[@]}; i++)); do
    echo "${APP_CONFIG[i]}" >> /config.sh || exit 1
done

if [[ -f "${ENTRYPOINT_CONFIG}" ]]; then
    source "${ENTRYPOINT_CONFIG}"
fi

# Initialization

message "Install graphics driver"

if ! /usr/local/bin/install-driver.sh --run-time; then
    fatal "Could not install graphics driver"
fi

# Fix permissions for /tmp directory
chmod 0777 /tmp

if [[ -n "$APP_USER" ]] && type -t setfacl &> /dev/null; then
    # Workaround for Ubuntu Bug
    # https://bugs.launchpad.net/ubuntu/+source/xinit/+bug/1562219
    setfacl -m "u:$APP_USER:rw" /dev/tty*
fi

# Initialize NVIDIA
if ! nvidia-modprobe -u -c=0; then
    fatal "Failed to initialize CUDA, run 'nvidia-modprobe -u -c=0' on host machine"
fi

# Setup /dev/video0
if [[ -c "/dev/video0" && -n "$APP_USER" ]]; then
    VIDEO_DEV=/dev/video0
    OLD_VIDEO_GID=$(getent group video | cut -d: -f3)
    VIDEO_GID=$(stat -c '%g' "${VIDEO_DEV}")

    if [[ -z "$OLD_VIDEO_GID" ]]; then
        ADD_VIDEO_GROUP=true
        if type -f groupadd &>/dev/null && type -f usermod &>/dev/null; then
            info "groupadd/usermod tools detected"
            _add_video_group() { groupadd --gid "$VIDEO_GID" video; }
            _add_video_user() { usermod -aG video "$APP_USER"; }
        elif type -f adduser &>/dev/null && type -f addgroup; then
            info "adduser/addgroup tools detected"
            _add_video_group() { addgroup -g "$VIDEO_GID" video; }
            _add_video_user() { addgroup "$APP_USER" video; }
        else
            error "Neither groupadd/usermod nor adduser/addgroup tools detected"
            ADD_VIDEO_GROUP=
        fi
    else
        _add_video_group() { true; }
        _add_video_user() { usermod -aG "$VIDEO_GID" "$APP_USER"; }
        ADD_VIDEO_GROUP=true
    fi

    if [[ "$ADD_VIDEO_GROUP" == true ]]; then
        if _add_video_group; then
            if _add_video_user; then
                info "Added user $APP_USER to video group with GID $VIDEO_GID"
                ADDED_VIDEO_GROUP=true
            else
                error "Could not add user $APP_USER to video group"
            fi
        else
            error "Could not create video group with $VIDEO_GID group ID"
        fi
    fi
fi

if [[ -n "$APP_USER" ]]; then
    set -xe
    exec /usr/local/bin/tini -- /usr/local/bin/su-exec "$APP_USER" "$@"
else
    set -xe
    exec /usr/local/bin/tini -- "$@"
fi
