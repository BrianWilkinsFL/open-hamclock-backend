#!/bin/sh

# pull down latest server data files
#/usr/sbin/runuser -u www-data /opt/sync_server_data_files.sh

echo "This image is based on git: '$(cat hamclock-backend/git.version)'"
echo "Start up time: $(date -u +%H:%M:%S)"

# start the web server
echo "Starting lighttpd ..."
/usr/sbin/lighttpd -f /etc/lighttpd/lighttpd.conf

echo "Syncing the initial, static directory structure ..."
cp -a /opt/hamclock-backend/ham /opt/hamclock-backend/htdocs

# only needs to be primed when container is instantiated
if [ ! -e /opt/hamclock-backend/htdocs/prime_crontabs.done ]; then
    echo "Running OHB for the first time."

    echo "Priming the data set ..."
    /usr/sbin/runuser -u www-data /opt/hamclock-backend/prime_crontabs.sh

    touch /opt/hamclock-backend/htdocs/prime_crontabs.done
    echo "Done! OHB data has been primed."

    LAST_TIME_EPOCH=$(date +%s)
else
    echo "OHB was previously installed and does not need to be primed."

    LAST_TIME_EPOCH=$(find /opt/hamclock-backend/htdocs -type f -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d. -f1)
    echo "Last running timestamp found is: '$(date -d @$LAST_TIME_EPOCH)'"
fi

echo $LAST_TIME_EPOCH > /opt/hamclock-backend/last-ts-running.txt

# start cron
echo "Starting cron ..."
/usr/sbin/cron

echo "OHB is running and ready to use at: $(date -u +%H:%M:%S)"

# hold the script to keep the container running
tail --pid=$(pidof cron) -f /dev/null
