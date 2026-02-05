FROM debian:13.3-slim

USER root
WORKDIR /opt

# Install prerequisites
COPY docker/package-list.txt /opt
RUN apt update && \
    apt install -y $(grep -v '^#' package-list.txt) && \
    apt-get clean && \
    rm -rf package-list.txt /var/lib/apt/lists/* 

# Install voacap
COPY docker/voacap-v.0.7.6.tgz /opt
RUN cd /opt && \
    # \
    # tarball \
    tar xzf voacap-v.0.7.6.tgz && \
    cd voacapl-v.0.7.6 && \
    # \
    # build it \
    ./configure && \
    make install && \
    # \
    # configure it \
    mkdir /var/www/itshfbc && \
    chown www-data:www-data /var/www/itshfbc && \
    runuser -u www-data makeitshfbc && \
    # \
    # clean up \
    cd .. && \
    rm -Rf voacapl-v.0.7.6 voacap-v.0.7.6.tgz

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
    mv ham htdocs/ && \
    mv  docker/run.sh /opt && \
    sed 's/^\([^ #]\+[ ]\+\)\{5\}\([^>]\+\)\([> ]\+\)\?\([^ ]*\).*$/\2\3\4/' scripts/crontab > prime_crontabs.sh && \
    # \
    # set permissions \
    chown -R www-data:www-data . && \
    chmod +x scripts/* prime_crontabs.sh /opt/run.sh && \
    # \
    # set up cron \
    mv scripts/crontab /var/spool/cron/crontabs/www-data && \
    chown www-data:crontab /var/spool/cron/crontabs/www-data && \
    chmod 600 /var/spool/cron/crontabs/www-data && \
    # \
    # set up lighttpd \
    mv 50-hamclock.conf /etc/lighttpd/conf-available/50-hamclock.conf && \
    /usr/sbin/lighty-enable-mod accesslog && \
    /usr/sbin/lighttpd-enable-mod hamclock && \
    rm -f /var/www/html/index.lighttpd.html && \
    cat <<EOF >>/etc/lighttpd/lighttpd.conf
server.modules += (
  "mod_cgi"
)
EOF

# let's rock!
CMD ["/opt/run.sh"]
