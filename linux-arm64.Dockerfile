ARG BASE_IMAGE
FROM ${BASE_IMAGE:-library/alpine:3.21}

ENV S6_REL=2.2.0.3 S6_ARCH=aarch64 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 TZ=Etc/UTC

LABEL base.s6.rel=${S6_REL} base.s6.arch=${S6_ARCH}

LABEL org.label-schema.name="organizr/base" \
  org.label-schema.description="Baseimage for Organizr" \
  org.label-schema.url="https://organizr.app/" \
  org.label-schema.vcs-url="https://github.com/organizr/docker-base" \
  org.label-schema.schema-version="1.0"

# environment variables
ENV PS1="$(whoami)@$(hostname):$(pwd)$ " \
  HOME="/root" \
  TERM="xterm"

# Update packages and install build dependencies
RUN echo "**** install build packages ****" && \
  apk update && \
  apk upgrade && \
  apk add --no-cache --virtual=build-dependencies \
    tar && \
  apk add --no-cache \
    openssl \
    curl \
    ca-certificates

# Setup Nginx Repo
RUN printf "%s%s%s\n" \
  "http://nginx.org/packages/alpine/v" \
  `egrep -o '^[0-9]+\.[0-9]+' /etc/alpine-release` \
  "/main" \
  | tee -a /etc/apk/repositories

# Import Nginx Signing Key
RUN curl -o /tmp/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub
RUN mv /tmp/nginx_signing.rsa.pub /etc/apk/keys/

# Install runtime packages
RUN echo "**** install runtime packages ****" && \
  apk add --no-cache \
    apache2-utils \
    bash \
    coreutils \
    git \
    libressl4.0-libssl \
    logrotate \
    nano \
    nginx \
    php84 \
    php84-curl \
    php84-fileinfo \
    php84-fpm \
    php84-ftp \
    php84-ldap \
    php84-mbstring \
    php84-mysqli \
    php84-openssl \
    php84-pdo_sqlite \
    php84-session \
    php84-simplexml \
    php84-sqlite3 \
    php84-tokenizer \
    php84-xmlwriter \
    php84-xml \
    php84-zip \
    shadow \
    zlib \
    tzdata
  # apk add --no-cache  --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
  #   php81-pecl-xmlrpc

# Add s6 overlay
RUN echo "**** add s6 overlay ****" && \
  curl -o /tmp/s6-overlay.tar.gz -L \
    "https://github.com/just-containers/s6-overlay/releases/download/v${S6_REL}/s6-overlay-${S6_ARCH}.tar.gz" && \
  tar xfz /tmp/s6-overlay.tar.gz -C /

# Create user and make folders
RUN echo "**** create abc user and make folders ****" && \
  groupmod -g 1000 users && \
  useradd -u 911 -U -d /config -s /bin/false abc && \
  usermod -G users abc && \
  mkdir -p \
    /config \
    /defaults

# Configure Nginx
RUN echo "**** configure nginx ****" && \
  echo 'fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;' >> \
  /etc/nginx/fastcgi_params && \
  rm -f /etc/nginx/conf.d/default.conf

# Fix logrotate
RUN echo "**** fix logrotate ****" && \
  sed -i "s#/var/log/messages {}.*# #g" /etc/logrotate.conf && \
  sed -i 's#/usr/sbin/logrotate /etc/logrotate.conf#/usr/sbin/logrotate /etc/logrotate.conf -s /config/log/logrotate.status#g' /etc/periodic/daily/logrotate

# Enable and configure PHP-FPM
RUN echo "**** enable PHP-FPM ****" && \
  sed -i "s#listen = 127.0.0.1:9000#listen = '/var/run/php8-fpm.sock'#g" /etc/php84/php-fpm.d/www.conf && \
  sed -i "s#;listen.owner = nobody#listen.owner = abc#g" /etc/php84/php-fpm.d/www.conf && \
  sed -i "s#;listen.group = abc#listen.group = abc#g" /etc/php84/php-fpm.d/www.conf && \
  sed -i "s#;listen.mode = nobody#listen.mode = 0660#g" /etc/php84/php-fpm.d/www.conf

# Set recommended defaults
RUN echo "**** set our recommended defaults ****" && \
  sed -i "s#pm = dynamic#pm = ondemand#g" /etc/php84/php-fpm.d/www.conf && \
  sed -i "s#pm.max_children = 5#pm.max_children = 4000#g" /etc/php84/php-fpm.d/www.conf && \
  sed -i "s#pm.start_servers = 2#;pm.start_servers = 2#g" /etc/php84/php-fpm.d/www.conf && \
  sed -i "s#;pm.process_idle_timeout = 10s;#pm.process_idle_timeout = 10s;#g" /etc/php84/php-fpm.d/www.conf && \
  sed -i "s#;pm.max_requests = 500#pm.max_requests = 0#g" /etc/php84/php-fpm.d/www.conf && \
  sed -i "s#zlib.output_compression = Off#zlib.output_compression = On#g" /etc/php84/php.ini

# Cleanup
RUN echo "**** cleanup ****" && \
  apk del --purge \
    build-dependencies && \
  rm -rf \
    /var/cache/apk/* \
    /tmp/*

# add local files
COPY root/ /

# ports and volumes
EXPOSE 80 443
VOLUME /config

HEALTHCHECK --start-period=60s CMD curl -ILfSs http://localhost:8080/nginx_status > /dev/null && curl -ILfkSs http://localhost:8080/php_status > /dev/null || exit 1

ENTRYPOINT ["/init"]
