## PLEASE DON'T CHANGE ANYTHING IN THIS FILE UNLESS YOU'RE developing.
## REFER TO THE DOCUMENTATION FOR CONFIGURATION OF YOUR HAMCLOCK!
FROM debian:13.3-slim

USER root
WORKDIR /opt
COPY package-list.txt /opt
# Install prerequisites
RUN apt update && \
    apt install -y $(grep -v '^#' package-list.txt) && \
    apt-get clean && \
    rm -rf package-list.txt /var/lib/apt/lists/* 

COPY hamclock-backend.tar.gz /opt
COPY 50-hamclock.conf /opt
COPY scripts/crontab /var/spool/cron/crontabs/www-data
RUN cd /opt && \
    tar xzf hamclock-backend.tar.gz -C /opt && \
    rm -f hamclock-backend.tar.gz && \
    chown www-data:crontab /var/spool/cron/crontabs/www-data && \
    chmod 600 /var/spool/cron/crontabs/www-data && \
    chown -R www-data:www-data /opt/hamclock-backend && \
    chmod +x /opt/hamclock-backend/htdocs/ham/HamClock/*.pl && \
    mv 50-hamclock.conf /etc/lighttpd/conf-available/50-hamclock.conf && \
    /usr/sbin/lighty-enable-mod accesslog && \
    /usr/sbin/lighttpd-enable-mod hamclock && \
    rm -f /var/www/html/index.lighttpd.html && \
    cat <<EOF >>/etc/lighttpd/lighttpd.conf
server.modules += (
  "mod_cgi"
)
EOF

COPY voacap-v.0.7.6.tgz /opt
RUN cd /opt && \
    tar xzf voacap-v.0.7.6.tgz && \
    rm -f voacap-v.0.7.6.tgz && \
    cd voacapl-v.0.7.6 && \
    ./configure && \
    make install && \
    mkdir /var/www/itshfbc && \
    chown www-data:www-data /var/www/itshfbc && \
    runuser -u www-data makeitshfbc

## temp to get latest before tgz was made
COPY scripts/* /opt/hamclock-backend/scripts/
RUN cd /opt && \
    sed 's/.*\* \(\/[^ ]*\)\( >> [^ ]*\)\?.*/\1\2/p' /opt/hamclock-backend/scripts/crontab > run_crontabs_once.sh && \
    chown -R www-data:www-data /opt/hamclock-backend/scripts run_crontabs_once.sh && \
    chmod +x /opt/hamclock-backend/scripts/* run_crontabs_once.sh
    #runuser -u www-data ./run_crontabs_once.sh
## temp

COPY run.sh /opt
RUN chmod +x /opt/run.sh

CMD ["/opt/run.sh"]

