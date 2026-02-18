#!/bin/bash

# at release time, this value is set to the tagged release
OHB_MANAGER_VERSION=latest

OHB_HTDOCS_DVC=ohb-htdocs
IMAGE_BASE=komacke/open-hamclock-backend

# Get our directory locations in order
HERE="$(realpath -s "$(dirname "$0")")"
THIS="$(basename "$0")"
STARTED_FROM="$PWD"
cd $HERE

DOCKER_PROJECT=${THIS%.*}
DEFAULT_TAG=latest
GIT_TAG=$(git describe --exact-match --tags 2>/dev/null)
GIT_VERSION=$(git rev-parse --short HEAD 2>/dev/null)
CONTAINER=${IMAGE_BASE##*/}
DEFAULT_HTTP_PORT=:80
REQUEST_DOCKER_PULL=false
DEFAULT_ENV_FILE="$STARTED_FROM/.env"
RETVAL=0

main() {
    COMMAND=$1
    case $COMMAND in
        -h|--help|help)
            usage
            ;;
        -v|--version|version)
            ohb_manager_version
            ;;
        check-docker)
            check_docker_installed
            ;;
        check-ohb-install)
            check_ohb_installed
            ;;
        install)
            shift && get_compose_opts "$@"
            install_ohb
            ;;
        upgrade)
            shift && get_compose_opts "$@"
            upgrade_ohb
            ;;
        full-reset)
            shift && get_compose_opts "$@"
            recreate_ohb
            ;;
        reset)
            shift && get_compose_opts "$@"
            docker_compose_reset
            ;;
        restart)
            shift && get_compose_opts "$@"
            docker_compose_restart
            ;;
        remove)
            remove_ohb
            ;;
        up)
            shift && get_compose_opts "$@"
            docker_compose_up
            ;;
        down)
            shift && get_compose_opts "$@"
            docker_compose_down
            ;;
        generate-docker-compose)
            shift && get_compose_opts "$@"
            generate_docker_compose
            ;;
        add-env-file)
            shift && get_compose_opts "$@"
            copy_env_to_container
            ;;
        *)
            echo "Invalid or missing option. Try using '$THIS help'."
            RETVAL=1
            ;;
    esac
}

get_compose_opts() {
    while getopts ":p:t:e:" opt; do
        case $opt in
            p)
                REQUESTED_HTTP_PORT="$OPTARG"
                ;;
            t)
                REQUESTED_TAG="$OPTARG"
                ;;
            e)
                REQUESTED_ENV_FILE="$OPTARG"
                ;;
            \?) # Handle invalid options
                echo "Command '$COMMAND': Invalid option: -$OPTARG" >&2
                exit 1
                ;;
            :) # Handle options requiring an argument but none provided
                echo "Command '$COMMAND': Option -$OPTARG requires an argument." >&2
                exit 1
                ;;
        esac
    done
}

usage () {
    cat<<EOF
$THIS <COMMAND> [options]:
    help: 
            This message

    check-docker:
            checks docker requirements and shows version

    check-ohb-install:
            checkif OHB is installed and report versions

    install [-p <port>] [-t <tag>]
            do a fresh install and optionally provide the version
            -p: set the HTTP port
            -t: set image tag

    upgrade [-p <port>] [-t <tag>]
            upgrade ohb; defaults to current git tag if there is one. Otherwise you can provide one.
            -p: set the HTTP port (defaults to current setting)
            -t: set image tag

    full-reset [-p <port>] [-t <tag>]: 
            clear out all data and start fresh
            -p: set the HTTP port (defaults to current setting)
            -t: set image tag

    reset:
            resets the OHB container to new but does not reset the persistent storage

    restart:
            restarts the OHB container. No file contents modified

    up [-p <port>] [-t <tag>]
            start an existing, not-running OHB install; defaults to current git tag if there is one. Otherwise you can provide one.
            -p: set the HTTP port (defaults to current setting)
            -t: set image tag

    down
            stop a running OHB install

    remove: 
            stop and remove the docker container, docker storage and docker image

    add-env-file [-e <env file>]:
            add .env to OHB. Defaults a file named '.env' in your PWD. The
            .env file contains secrets such as api keys for services. If OHB
            was already running, it needs to be restarted for the file
            to take effect. See the restart command. See .env.example for more info.
            -e: .env file location

    generate-docker-compose [-p <port>] [-t <tag>]: 
            writes the docker compose file to STDOUT
            -p: set the HTTP port (defaults to current setting)
            -t: set image tag
EOF
}

ohb_manager_version() {
    echo $OHB_MANAGER_VERSION
}

install_ohb() {
    check_docker_installed >/dev/null || return $?
    check_dvc_created || return $?

    echo "Installing OHB ..."

    echo "Creeating persistent storage ..."
    if create_dvc; then
        echo "Persistent storage created successfully."
    else
        echo "ERROR: failed to create persistence storage." >&2
        return $RETVAL
    fi

    echo "Starting the container ..."
    if docker_compose_up; then
        echo "Container started successfully."
    else
        echo "ERROR: failed to start OHB with docker compose up" >&2
        return $RETVAL
    fi
    return $RETVAL
}

check_ohb_installed() {
    echo "$THIS version: '$OHB_MANAGER_VERSION'"
    echo

    echo "Checking for docker ..."
    if ! check_docker_installed | sed 's/^/  /'; then
        RETVAL=1
        return $RETVAL
    fi
    echo

    if is_dvc_exists; then
        echo "OHB is installed"
    else
        echo "OHB does not appear to be installed."
        RETVAL=1
        return $RETVAL
    fi

    get_current_image_tag
    if [ -z "$CURRENT_TAG" ]; then
        echo "OHB does not appear to be running. Try running '$THIS up'"
        RETVAL=1
        return $RETVAL
    else
        get_current_http_port
        echo
        echo "  Base docker image: '$CURRENT_IMAGE_BASE'"
        echo "  Docker image tag:  '$CURRENT_TAG'"
        echo "  HTTP PORT in use:  '$CURRENT_HTTP_PORT'"
    fi

    if !  is_container_running; then
        echo
        echo "OHB appears to be in a failed state. Try '$THIS up' and look for docker errors."
    fi

    if [ -n "$GIT_VERSION" ]; then
        echo
        echo "You appear to have OHB source code checked out from git."
        echo
        if [ -n "$GIT_TAG" ]; then
            echo "  On a tagged release: '$GIT_TAG'"
        elif [ -n "$GIT_VERSION" ]; then
            echo "  Not on a tagged release. git hash: '$GIT_VERSION'"
        else
            echo "  Not running from a git checkout."
        fi
    fi
}

upgrade_ohb() {
    check_docker_installed >/dev/null || return $?

    get_current_http_port
    get_current_image_tag

    echo "Upgrading OHB ..."

    REQUEST_DOCKER_PULL=true
    echo "Starting the container ..."
    if docker_compose_up; then
        echo "Container started successfully."
    else
        echo "ERROR: failed to start OHB with docker compose up"
        return $RETVAL
    fi
    return $RETVAL
}

check_docker_installed() {
    DOCKERD_VERSION=$(dockerd -v 2>/dev/null)
    DOCKERD_RETVAL=$?
    DOCKER_COMPOSE_VERSION=$(docker compose version 2>/dev/null)
    DOCKER_COMPOSE_RETVAL=$?

    if [ $DOCKERD_RETVAL -ne 0 ]; then
        echo "ERROR: docker is not installed. Could not find dockerd." >&2
        RETVAL=$DOCKERD_RETVAL
    elif [ $DOCKER_COMPOSE_RETVAL -ne 0 ]; then
        echo "ERROR: docker compose is not installed but we found docker. Try installing docker compose." >&2
        echo "  docker version found: '$DOCKERD_VERSION'" >&2
        RETVAL=$DOCKER_COMPOSE_RETVAL
    else
        echo "$DOCKERD_VERSION"
        echo "$DOCKER_COMPOSE_VERSION"
    fi
    return $RETVAL
}

check_dvc_created() {
    if is_dvc_exists; then
        echo "This doesn't appear to be a fresh install. A docker volume container"
        echo "was found."
        echo
        echo "Maybe you wanted to upgrade:"
        echo "  $THIS upgrade"
        echo "or"
        echo "Maybe you wanted to reset the system and all its data:"
        echo "  $THIS full-reset"
        RETVAL=1
    fi
    return $RETVAL
}

docker_compose_up() {
    if is_container_running; then
        echo "OHB is already running."
        RETVAL=0
    else
        docker_compose_yml && docker compose -f <(echo "$DOCKER_COMPOSE_YML") create 
        if [ -n "$REQUESTED_ENV_FILE" -o -r "$DEFAULT_ENV_FILE" ]; then
            copy_env_to_container >/dev/null
        fi
        docker_compose_yml && docker compose -f <(echo "$DOCKER_COMPOSE_YML") up -d
        RETVAL=$?
    fi

    return $RETVAL
}

docker_compose_down() {
    docker_compose_yml && docker compose -f <(echo "$DOCKER_COMPOSE_YML") down -v
    RETVAL=$?

    if is_container_exists; then
        RUNNING_PROJECT=$(docker inspect open-hamclock-backend | jq -r '.[0].Config.Labels."com.docker.compose.project"')
        if [ "$RUNNING_PROJECT" != "$DOCKER_PROJECT" ]; then
            echo "ERROR: this OHB was created with a different docker-compsose file. Please run" >&2
            echo "    'docker stop $CONTAINER'" >&2
            echo "    'docker rm $CONTAINER'" >&2
            echo "before running this utility." >&2
        else
            echo "ERROR: OHB failed to stop." >&2
        fi
        RETVAL=1
    fi
    
    return $RETVAL
}

docker_compose_reset() {
    get_current_http_port
    get_current_image_tag
    docker_compose_down || return $RETVAL
    docker_compose_up
}

docker_compose_restart() {
    docker restart $CONTAINER
}

generate_docker_compose() {
    docker_compose_yml && echo "$DOCKER_COMPOSE_YML"
}

remove_ohb() {
    echo "Stopping the container ..."
    if docker_compose_down; then
        echo "Container stopped successfully."
    else
        echo "ERROR: failed to stop OHB with docker compose down" >&2
        return $RETVAL
    fi
    echo "Removing persistent storage ..."
    if rm_dvc; then
        echo "Persistent storage removed successfully."
    else
        echo "ERROR: failed to remove persistence storage." >&2
        return $RETVAL
    fi
}

recreate_ohb() {
    get_current_http_port
    get_current_image_tag

    remove_ohb || return $RETVAL
    install_ohb || return $RETVAL
}

copy_env_to_container() {
    if [ -n "$REQUESTED_ENV_FILE" ]; then
        if [[ "$REQUESTED_ENV_FILE" == /* ]]; then
            ENV_FILE="$REQUESTED_ENV_FILE"
        else
            ENV_FILE="$STARTED_FROM/$REQUESTED_ENV_FILE"
        fi
    else
        ENV_FILE="$DEFAULT_ENV_FILE"
    fi

    if is_container_exists; then
        if [ -r "$ENV_FILE" ]; then
            docker cp $ENV_FILE $CONTAINER:/opt/hamclock-backend/.env
        else
            echo "ERROR: ENV file not found: '$(realpath "$ENV_FILE")'" >&2
            RETVAL=1
        fi
    else
        echo "ERROR: the docker container needs to exist for this command." >&2
        echo "Install or start OHB first." >&2
        RETVAL=1
    fi

    return $RETVAL
}

is_dvc_exists() {
    docker volume ls | grep -qsw $OHB_HTDOCS_DVC
    return $?
}

is_container_running() {
    docker ps --format '{{.Names}}' | grep -wqs $CONTAINER
    return $?
}

is_container_exists() {
    docker ps -a --format '{{.Names}}' | grep -wqs $CONTAINER
    return $?
}

create_dvc() {
    docker volume create $OHB_HTDOCS_DVC >/dev/null
    RETVAL=$?
    return $RETVAL
}

rm_dvc() {
    docker volume rm $OHB_HTDOCS_DVC >/dev/null
    RETVAL=$?
    return $RETVAL
}

get_current_http_port() {
    DOCKER_HTTP_PORT=$(docker inspect $CONTAINER 2>/dev/null | jq -r '.[0].HostConfig.PortBindings."80/tcp"[0].HostPort')
    DOCKER_HTTP_IP=$(docker inspect $CONTAINER 2>/dev/null | jq -r '.[0].HostConfig.PortBindings."80/tcp"[0].HostIp')
    if [ "$DOCKER_HTTP_PORT" != 'null' ]; then
        if [ "$DOCKER_HTTP_IP" != 'null' ]; then
            CURRENT_HTTP_PORT=$DOCKER_HTTP_IP:$DOCKER_HTTP_PORT
        else
            CURRENT_HTTP_PORT=:$DOCKER_HTTP_PORT
        fi
    fi
}

get_current_image_tag() {
    CURRENT_DOCKER_IMAGE=$(docker inspect open-hamclock-backend 2>/dev/null | jq -r '.[0].Config.Image')
    if [ "$CURRENT_DOCKER_IMAGE" != 'null' ]; then
        CURRENT_TAG=${CURRENT_DOCKER_IMAGE#*:}
        CURRENT_IMAGE_BASE=${CURRENT_DOCKER_IMAGE%:*}
    fi
}

determine_port() {
    get_current_http_port

    # first precedence
    if [ -n "$REQUESTED_HTTP_PORT" ]; then
        HTTP_PORT=$REQUESTED_HTTP_PORT

    # second precedence
    elif [ -n "$CURRENT_HTTP_PORT" -a "$CURRENT_HTTP_PORT" != ':' ]; then
        HTTP_PORT=$CURRENT_HTTP_PORT

    # third precedence
    else
        HTTP_PORT=$DEFAULT_HTTP_PORT

    fi

    # if there was a :, it was probably IP:PORT; otherwise make sure there's a colon for port only
    [[ $HTTP_PORT =~ : ]] || HTTP_PORT=":$HTTP_PORT"
}

determine_tag() {
    get_current_image_tag

    # first precedence
    if [ -n "$REQUESTED_TAG" ]; then
        TAG=$REQUESTED_TAG
        return
    fi

    # upgrade wouldn't use the current tag unless it's latest. 
    # GIT_TAG would be empty and we'll get DEFAULT_TAG

    # second precedence
    # FUNCNAME is a stack of nested function calls
    if [ -n "$CURRENT_TAG" -a ${FUNCNAME[3]} != upgrade_ohb ]; then
        TAG=$CURRENT_TAG

    # third precedence
    elif [ -n "$GIT_TAG" ]; then 
        TAG=$GIT_TAG

    # forth precedence
    else
        TAG=$DEFAULT_TAG

    fi
}

docker_compose_yml() {
    determine_port

    determine_tag
    IMAGE=$IMAGE_BASE:$TAG

    if [ "$TAG" == "$CURRENT_TAG"  -a "$REQUEST_DOCKER_PULL" == true ]; then
        echo "Doing a docker pull of the image before docker compose."
        docker pull $IMAGE | sed 's/^/  /'
    fi

    # compose file in $DOCKER_COMPOSE_YML
    IFS= DOCKER_COMPOSE_YML=$(
        docker_compose_yml_tmpl | 
            sed "s/__DOCKER_PROJECT__/$DOCKER_PROJECT/" |
            sed "s|__IMAGE__|$IMAGE|" |
            sed "s/__CONTAINER__/$CONTAINER/" |
            sed "s/__HTTP_PORT__/$HTTP_PORT/"
    )
}

docker_compose_yml_tmpl() {
    cat<<EOF
name: __DOCKER_PROJECT__
services:
  web:
    container_name: __CONTAINER__
    image: __IMAGE__
    restart: unless-stopped
    networks:
      - ohb
    ports:
      - __HTTP_PORT__:80
    volumes:
      - ohb-htdocs:/opt/hamclock-backend/htdocs
    healthcheck:
      test: ["CMD", "curl", "-f", "-A", "healthcheck/1.0", "http://localhost:80/ham/HamClock/version.pl"]
      timeout: "5s"
      start_period: "20s"
    logging:
      options:
        max-size: "10m"
        max-file: "2"

networks:
  ohb:
    driver: bridge
    name: ohb
    enable_ipv6: true
    ipam:
     driver: default
    driver_opts:
      com.docker.network.bridge.name: ohb

volumes:
  ohb-htdocs:
    external: true
EOF
}

main "$@"
exit $RETVAL
