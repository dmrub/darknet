# Shell Library

error() {
    echo >&2 "* Error: $@"
}

fatal() {
    error "$@"
    exit 1
}

message() {
    echo "$@"
}

update-git-repo() {
    # $1   - git repository url
    # $2   - source dir, where to clone
    # rest - additional arguments:
    #
    #        -n                     - don't chekout working dir        (git clone -n)
    #        --pull                 - pull instead of fetching         (git pull --rebase)
    #        --reset                - hard reset before pulling        (git reset --hard HEAD)
    #        --xrepo|--Xrepo <repo> - override the default repository
    #                                 with <repo>
    #        -b <branch>            - Point the local HEAD to <branch> (git clone -b <branch>
    #                                                                   git checkout <branch>)

    local git_url="${1:?}"
    local source_dir="${2:?}"
    shift 2

    local git_cmd=fetch
    local git_cmd_opt=
    local git_clone_opt=
    local git_branch=
    local git_reset=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pull)
                git_cmd=pull
                git_cmd_opt=--rebase
                ;;
            --reset)
                git_reset=true
                ;;
            -n)
                git_clone_opt="$git_clone_opt -n"
                ;;
            --xrepo|--Xrepo)
                shift
                if [[ $# -gt 0 ]]; then
                    if [[ "${git_url}" ]]; then
                        message "Overriding git URL \"${git_url:?}\" with \"${1:?}\""
                    fi
                    git_url="${1:?}"
                else
                    error "Missing argument (git URL) to --xrepo|--Xrepo option"
                    return 1
                fi
                ;;
            -b)
                shift
                if [[ $# -gt 0 ]]; then
                    if [[ -n "${git_branch}" ]]; then
                        message "Overriding git branch \"${git_branch:?}\" with \"${1:?}\""
                    fi
                    git_branch="${1:?}";
                    git_clone_opt="$git_clone_opt -b ${git_branch:?}"
                else
                    error "Missing argument (remote branch name) to -b option"
                    return 1
                fi
                ;;
            '')
                # Ignore empty argument
                shift
                ;;
            *)  error "update-git-repo: unrecognized argument: $1"
                return 1
                ;;
        esac
        shift
    done

    local exit_code

    if [[ -n "${git_branch}" ]]; then
        message "Selecting ${git_branch:?} branch as HEAD"
    fi

    if [[ -e "$source_dir" ]]; then
        cd "$source_dir"

        if [[ "$git_cmd" == "pull" && "$git_reset" == "true" ]]; then
            git reset --hard HEAD
        fi

        if [[ -n "${git_branch}" ]]; then
            git fetch && git checkout "${git_branch:?}"
            exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
                if [[ "$git_cmd" == "pull" ]] && ! git symbolic-ref -q HEAD > /dev/null; then
                    # HEAD is detached, git pull will not work
                    # FIXME: Following is not really nice and should be improved
                    git fetch && git fetch --tags && git checkout "${git_branch:?}"
                else
                    git "$git_cmd" $git_cmd_opt
                fi
                exit_code=$?
            fi
        else
            git "$git_cmd" $git_cmd_opt
            exit_code=$?
        fi
        cd - &> /dev/null
        # simple error check for incomplete git clone
        if [[ $exit_code -ne 0 && ! -e "$source_dir/.git" ]]; then
            error "'git $git_cmd $git_cmd_opt' failed !"
            error "Directory $source_dir exists but $source_dir/.git directory missing."
            error "Possibly 'git clone' command failed."
            error "You can try to remove $source_dir directory and try to update again."
        fi
    else
        message "Cloning $git_url to $source_dir..."
        test "${git_branch}" &&
            message "Selecting ${git_branch:?} branch as HEAD"
        git clone "$git_url" "$source_dir" $git_clone_opt
        exit_code=$?
    fi
    return $exit_code
}

# Define download function
define-download-func() {
    if type -f curl &> /dev/null; then
        download() {
            local url=$1
            local dest=$2

            if [[ ! -f "$dest" ]]; then
                echo "Download $url"
                curl --fail --location --output "$dest" "$url" || \
                    fatal "Could not load $url to $dest"
            else
                echo "File $dest exists, skipping download"
            fi
        }
    elif type -f wget &> /dev/null; then
        download() {
            local url=$1
            local dest=$2

            if [[ ! -f "$dest" ]]; then
                echo "Download $url"
                wget -O "$dest" "$url" || \
                    fatal "Could not load $url to $dest"
            else
                echo "File $dest exists, skipping download"
            fi
        }
    else
        fatal "No download tool detected (checked: curl, wget)"
    fi
}

# Define sha1hash
define-sha1hash-func() {
    if type -f sha1sum &> /dev/null && type -f cut &> /dev/null; then
        sha1hash() {
            sha1sum -b "$1" | cut -d' ' -f1
        }
    elif type -f openssl &> /dev/null && type -f cut 2 > /dev/null; then
        sha1hash() {
            openssl sha1 -r "$1" | cut -d' ' -f1
        }
    elif type -f python &> /dev/null; then

        sha1hash() {
            python -c "
import hashlib
import sys
h = hashlib.sha1()
fd = open(sys.argv[1], 'rb')
h.update(fd.read())
fd.close()
print h.hexdigest()" "$1"
        }
    else
        fatal "No SHA-1 tool detected (checked: sha1sum, openssl, python)"
    fi
}

check-sha1-hash() {
    local fn=$1
    local hash=$2
    echo "Verify SHA1 hash of file $fn ..."
    local dest_hash=$(sha1hash "$fn")
    if [[ "$dest_hash" == "$hash" ]]; then
        echo "SHA1 hash verified ($hash) !"
    else
        fatal "SHA1 hash verification of file $1 failed: hash is $dest_hash, but should be $hash"
    fi
    return 0
}

download-and-check-sha1-hash() {
    local url=$1
    local dest=$2
    local hash=$3
    local dest_hash
    if [[ -f "$dest" ]]; then
        echo "Verify SHA1 hash of file $dest ..."
        dest_hash=$(sha1hash "$dest")
        if [[ "$dest_hash" == "$hash" ]]; then
            echo "SHA1 hash verified ($hash) !"
            return 0
        else
            error "SHA1 hash verification failed: hash is $dest_hash, but should be $hash"
            rm "$dest"
        fi
    fi
    download "$1" "$2"
    dest_hash=$(sha1hash "$dest")
    if [[ "$dest_hash" == "$hash" ]]; then
        echo "SHA1 hash verified ($hash) !"
    else
        fatal "SHA1 hash verification failed: hash is $dest_hash, but should be $hash"
    fi
    return 0
}
