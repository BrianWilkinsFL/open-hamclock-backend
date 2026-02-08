#!/bin/bash

# Variables to set
IMAGE_BASE=hamclock-be
VOACAP_VERSION=v.0.7.6
TAG=$(git describe --exact-match --tags 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "Not currently on a tag. Using 'latest'."
    TAG=latest
    #TAG=$(git rev-parse --short HEAD)
fi

# Don't set anything past here
IMAGE=$IMAGE_BASE:$TAG

# Get our directory locations in order
HERE="$(realpath -s "$(dirname "$0")")"
THIS="$(basename "$0")"
cd $HERE

# this hasn't changed since 2020. Also, while we are developing we don't need to keep pulling it.
if [ ! -e voacap-$VOACAP_VERSION.tgz ]; then
    curl -s https://codeload.github.com/jawatson/voacapl/tar.gz/refs/tags/v.0.7.6 -o voacap-$VOACAP_VERSION.tgz
fi

# make the docker-compose file
sed "s/__IMAGE__/$IMAGE/" docker-compose.yml.tmpl > docker-compose.yml
sed -i "s/__IMAGE_BASE__/$IMAGE_BASE/" docker-compose.yml

if $(docker image list --format '{{.Repository}}:{{.Tag}}' | grep -qs $IMAGE) && [ $TAG != latest ]; then
    echo "The docker image for '$IMAGE' already exists. Please remove it if you want to rebuild."
    # NOT ENFORCING THIS YET
    #exit 2
fi

# Build the image
echo
echo "Currently building version '$TAG' of '$IMAGE_BASE'"
pushd "$HERE/.." >/dev/null
docker build --rm -t $IMAGE -f docker/Dockerfile .
RETVAL=$?
popd >/dev/null

if [ $RETVAL -eq 0 ]; then
    # basic info
    echo
    echo "Completed building '$IMAGE'."
    echo
    echo "If this is the first time you are running OHB, run setup first:"
    echo "    docker-ohb-setup.sh"
    echo
    echo "To start the container, launch with docker compose:"
    echo "    docker compose up -d"
else
    echo "build failed with error: $RETVAL"
fi

exit $RETVAL
