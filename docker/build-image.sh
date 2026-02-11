#!/bin/bash

# Variables to set
IMAGE_BASE=komacke/open-hamclock-backend
VOACAP_VERSION=v.0.7.6
HTTP_PORT=80

# Don't set anything past here
TAG=$(git describe --exact-match --tags 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "NOTE: Not currently on a tag. Using 'latest'."
    echo
    TAG=latest
    GIT_VERSION=$(git rev-parse --short HEAD)
else
    GIT_VERSION=$TAG
fi

IMAGE=$IMAGE_BASE:$TAG
CONTAINER=${IMAGE_BASE##*/}

# Get our directory locations in figured out
HERE="$(realpath -s "$(dirname "$0")")"
THIS="$(basename "$0")"
cd $HERE

usage() {
    cat<<EOF
$THIS: 
    -c: build compose only
    -p <port>: set the http port
    -m: multi-platform image buld for: linux/amd64 linux/arm64 linux/arm/v7
        - argument is ignored when run with -c
        - remember to setup a buildx container: 
            docker buildx create --name ohb --driver docker-container --use
            docker buildx inspect --bootstrap
    -n: add no-cache to build
EOF
    exit 0
}

main() {
    RETVAL=0
    ONLY_COMPOSE=false
    MULTI_PLATFORM=false
    NOCACHE=false

    if [[ "$@" =~ --help ]]; then
        usage
    fi

    while getopts ":p:cmh" opt; do
        case $opt in
            c)
                ONLY_COMPOSE=true
                ;;
            p)
                HTTP_PORT="$OPTARG"
                # if there was a :, it was probably IP:PORT; otherwise add colon for port only
                [[ $HTTP_PORT =~ : ]] || HTTP_PORT=":$HTTP_PORT"
                ;;
            m)
                MULTI_PLATFORM=true
                ;;
            n)
                NOCACHE=true
                ;;
            h)
                usage
                ;;
            \?) # Handle invalid options
                echo "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
            :) # Handle options requiring an argument but none provided
                echo "Option -$OPTARG requires an argument." >&2
                exit 1
                ;;
        esac
    done

    if [ $ONLY_COMPOSE == true ]; then
        make_docker_compose
        compose_done_message
    else
        do_all
        build_done_message
    fi
}

do_all() {
    make_docker_compose
    warn_image_tag
    build_image
}

make_docker_compose() {
    echo "Creating docker compose file for image: '$IMAGE_BASE:$TAG', port '$HTTP_PORT'"
    # make the docker-compose file
    sed "s|__IMAGE__|$IMAGE|" docker-compose.yml.tmpl > docker-compose.yml
    sed -i "s/__CONTAINER__/$CONTAINER/" docker-compose.yml
    sed -i "s/__HTTP_PORT__/$HTTP_PORT/" docker-compose.yml
}

warn_image_tag() {
    if [ $TAG != latest ]; then
        if [ $MULTI_PLATFORM == true ]; then
            docker manifest inspect $IMAGE >/dev/null
            if [ $? -eq 0 ]; then
                echo
                echo "WARNING: the multiplatform docker image for '$IMAGE' already exists in Docker Hub. Please"
                echo "         remove it if you want to rebuild."
                exit 2
            fi
        elif docker image list --format '{{.Repository}}:{{.Tag}}' | grep -qs $IMAGE; then
            echo
            echo "WARNING: the docker image for '$IMAGE' already exists. Please remove it if you want to rebuild."
            exit 2
        fi
    fi
}

build_image() {
    if [ $NOCACHE == true ]; then
        NOCACHE_ARG="--no-cache"
    fi
    # Build the image
    echo
    echo "Building image for '$IMAGE_BASE:$TAG'"
    pushd "$HERE/.." >/dev/null
    echo $GIT_VERSION > git.version
    if [ $MULTI_PLATFORM == true ]; then
        docker buildx build -t $IMAGE -f docker/Dockerfile --platform linux/amd64,linux/arm64 --push .
    else
        docker build $NOCACHE_ARG -t $IMAGE -f docker/Dockerfile .
    fi
    rm -f git.version
    RETVAL=$?
    popd >/dev/null
}

compose_done_message() {
    echo
    echo "If this is the first time you are running OHB, run setup first:"
    echo "    docker-ohb-setup.sh"
    echo
    echo "To start the container, launch with docker compose:"
    echo "    docker compose up -d"
}

build_done_message() {
    if [ $RETVAL -eq 0 ]; then
        # basic info
        echo
        echo "Completed building '$IMAGE'."
        compose_done_message
    else
        echo "build failed with error: $RETVAL"
    fi
}

main "$@"
exit $RETVAL
