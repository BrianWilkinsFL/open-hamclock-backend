#!/bin/bash

IMAGE_BASE=hamclock-be
TAG=test

docker build --no-cache --rm -t hamclock-be:test .
exit

#TMPFILE=$(mktemp -qp .)
#curl -sq https://www.clearskyinstitute.com/ham/HamClock/ESPHamClock.zip -o $TMPFILE 
# version.sh: #define HC_VERSION
#eval $(unzip -p $TMPFILE ESPHamClock/version.h | sed -n 's/#define\s\+\([^\s]\+\)\s\+\(.*\)/\1=\2/p')
#rm $TMPFILE
HC_VERSION=$(curl -s http://clearskyinstitute.com/ham/HamClock/version.pl | head -n 1)

if [ -z "$HC_VERSION" ]; then
    echo "Could not find a version for $IMAGE_BASE."
    exit 1
fi

TAG=$HC_VERSION
IMAGE=$IMAGE_BASE:$TAG

echo "The lastest version of $IMAGE_BASE is: $TAG"
if $(docker image list --format '{{.Repository}}:{{.Tag}}' | grep -qs $IMAGE) ; then
    echo "The docker image for $IMAGE already exists. Please remove it if you want to rebuild."
    exit 2
fi

#DOCKER_BUILDKIT=0 docker build --no-cache --rm -t $IMAGE .
docker build --no-cache --rm -t $IMAGE .

sed "s/__TAG__/$TAG/" docker-compose.yml.tmpl > docker-compose.yml
