#######################################################
# Build the real image
#######################################################
FROM debian:13.3-slim

USER root
WORKDIR /opt

# Install prerequisites
COPY docker/package-list.txt /opt
RUN apt update && \
    apt install -y --no-install-recommends $(grep -v '^#' package-list.txt) && \
    apt-get clean && \
    rm -rf package-list.txt /var/lib/apt/lists/* 

# Install hamclock-backend
COPY . /opt/hamclock-backend/
RUN cd /opt/hamclock-backend && \
    # \
    # make directory structure \
    mkdir -p \
        tmp \
        logs \
        cache \
        data \
        htdocs && \
    mv  docker/run.sh /opt && \
    # \
    # cron is tightly coupled to the type of python install. cron is written for pyenv. however \
    # when there is no pip or pyenv, python runs from /usr. \
    sed -i 's|^VENV=.*|VENV=/usr|' scripts/crontab && \
    # \
    # This crazy line takes the crontab file, removes the stderr redirect and adds echos to track progress. \
    # It generates a file that will be run only once on a fresh install \
    awk '/^[0-9\*]/ {full=$0; $1=$2=$3=$4=$5=""; sub(/^[ \t]+/, "", $0); exec=$0; sub(/[[:space:]]*[>|].*$/, "", exec); print "echo \"Running: " exec "\""; print $0; next} {print}' scripts/crontab | sed 's/[[:space:]]*2>&1//g' > prime_crontabs.sh && \
    # \
    # set permissions \
    chown -R www-data:www-data . && \
    chmod +x scripts/* prime_crontabs.sh /opt/run.sh /opt/hamclock-backend/lighttpd-conf/env-gen.sh && \
    # \
    # fontconfig needs a writeable cache directory \
    mkdir -p /var/www/.fontconfig && \
    chown -R www-data:www-data /var/www/.fontconfig && \
    # \
    # set up cron \
    mv scripts/crontab /var/spool/cron/crontabs/www-data && \
    chown www-data:crontab /var/spool/cron/crontabs/www-data && \
    chmod 600 /var/spool/cron/crontabs/www-data && \
    # \
    # set up logrotate \
    mv ohb.logrotate /etc/logrotate.d/ohb && \
    # \
    # set up lighttpd \
    cp lighttpd-conf/*.conf /etc/lighttpd/conf-available/ && \
    /usr/sbin/lighty-enable-mod accesslog && \
    /usr/sbin/lighttpd-enable-mod hamclock && \
    /usr/sbin/lighttpd-enable-mod ohb-dashboard

# let's rock!
CMD ["/opt/run.sh"]
