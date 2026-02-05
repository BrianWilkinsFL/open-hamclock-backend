#!/bin/bash

# Variables to set
IMAGE_BASE=hamclock-be
TAG=test
VOACAP_VERSION=v.0.7.6

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

if $(docker image list --format '{{.Repository}}:{{.Tag}}' | grep -qs $IMAGE) ; then
    echo "The docker image for '$IMAGE' already exists. Please remove it if you want to rebuild."
    # NOT ENFORCING THIS YET
    #exit 2
fi

# Build the image
echo "Currently building version $TAG of $IMAGE_BASE"
pushd "$HERE/.." >/dev/null
docker build --rm -t $IMAGE -f docker/Dockerfile .
popd >/dev/null

# basic info
echo
echo "Completed building '$IMAGE'."
echo "To start a container, try: 'docker-compose up -d'."
