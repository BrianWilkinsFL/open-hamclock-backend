#!/bin/bash

OHB_HTDOCS=ohb-htdocs
WAS_SETUP=0

# Get our directory locations in order
HERE="$(realpath -s "$(dirname "$0")")"
THIS="$(basename "$0")"
cd $HERE


RETVAL=0

main() {
    case $1 in
        rm)
            rm_setup
            ;;
        recreate)
            rm_setup && echo && setup
            ;;
        '')
            setup
            ;;
    esac
}

setup() {
    check_was_setup
        
    echo "Setting up OHB prerequisites in docker. This only needs to be done for a fresh install."

    create_volume

    echo
    echo "Done! When you are ready, bring up the container with docker compose:"
    echo "  docker compose up -d"
}

rm_setup() {
    docker volume rm $OHB_HTDOCS
    RETVAL=$?

    echo
    if [ $RETVAL -eq 0 ]; then
        echo "docker volume container '$OHB_HTDOCS' removed."
    else
        echo "Failed to remove docker volume '$OHB_HTDOCS'. Probably the docker container needs to be stopped and removed."
    fi
    return $RETVAL
}

check_was_setup() {
    if check_dvc; then
        WAS_SETUP=1
    fi
        
    if [ $WAS_SETUP -ne 0 ]; then
        echo "OHB prerequisites were previously set up."
        echo
        echo "If you want to remove the OHB configuration, run:"
        echo " docker compose down -v"
        echo " ./$THIS rm"
        exit 1
    fi
}

check_dvc() {
    docker volume ls | grep -qsw $OHB_HTDOCS
    return $?
}

create_volume() {
    docker volume create $OHB_HTDOCS >/dev/null
}

main "$@"
exit $RETVAL
