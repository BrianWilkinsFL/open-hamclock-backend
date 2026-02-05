#!/bin/sh

# start the web server
/usr/sbin/lighttpd -f /etc/lighttpd/lighttpd.conf

# only needs to be primed when container is instantiated
if [ ! -e /opt/hamclock-backend/prime_crontabs.done ]; then
    /usr/sbin/runuser -u www-data /opt/hamclock-backend/prime_crontabs.sh
    touch /opt/hamclock-backend/prime_crontabs.done
fi

# start cron
/usr/sbin/cron

# hold the script to keep the container running
tail --pid=$(pidof cron) -f /dev/null
