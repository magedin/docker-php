FROM php:7.2-fpm-buster
MAINTAINER MagedIn Technology <support@magedin.com>

ARG GOSU_VERSION=1.11


# ENVIRONMENT VARIABLES ------------------------------------------------------------------------------------------------

ENV APP_ROOT /var/www/html
ENV APP_HOME /var/www
ENV APP_USER www
ENV APP_GROUP www

ENV DEBUG false
ENV UPDATE_UID_GID false
ENV SET_DOCKER_HOST false

ENV LS_OPTIONS "--color=auto"


# BASE INSTALLATION ----------------------------------------------------------------------------------------------------

## Install dependencies
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
  apt-utils \
  sendmail-bin \
  sendmail \
  sudo \
  libbz2-dev \
  libjpeg62-turbo-dev \
  libpng-dev \
  libwebp-dev \
  libfreetype6-dev \
  libgeoip-dev \
  wget \
  libgmp-dev \
  libgpgme11-dev \
  libmagickwand-dev \
  libmagickcore-dev \
  libicu-dev \
  libldap2-dev \
  libpspell-dev \
  libtidy-dev \
  libxslt1-dev \
  libyaml-dev \
  libzip-dev \
  zip \
  gzip \
  libmcrypt-dev \
  libonig-dev \
  libsodium-dev \
  libssh2-1-dev \
  default-mysql-client \
  && rm -rf /var/lib/apt/lists/*

## Install Tools
RUN apt update && apt install -y \
  git \
  lsof \
  vim \
  procps \
  watch

## Configure the gd library
RUN docker-php-ext-configure \
  gd --with-gd \
     --with-freetype-dir=/usr/include/ \
     --with-jpeg-dir=/usr/include/ \
     --with-webp-dir=/usr/include/
RUN docker-php-ext-configure \
  ldap --with-libdir=lib/x86_64-linux-gnu
RUN docker-php-ext-configure \
  opcache --enable-opcache

## Install required PHP extensions
RUN docker-php-ext-install -j$(nproc) \
  bcmath \
  bz2 \
  calendar \
  exif \
  gd \
  gettext \
  gmp \
  intl \
  ldap \
  mysqli \
  opcache \
  pdo_mysql \
  pspell \
  shmop \
  soap \
  sockets \
  sysvmsg \
  sysvsem \
  sysvshm \
  tidy \
  xmlrpc \
  xsl \
  zip \
  pcntl \
  mbstring \
  sodium

## Install PECL Extensions
RUN pecl install -o -f \
  geoip-1.1.1 \
  gnupg \
  igbinary \
  imagick \
  mailparse \
  msgpack \
  oauth \
  pcov \
  propro \
  raphf \
  redis \
  xdebug-2.9.8 \
  ssh2-1.2 \
  yaml

## Install Blackfire
RUN curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/linux/amd64/$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;") \
  && mkdir -p /tmp/blackfire \
  && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
  && mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get ('extension_dir');")/blackfire.so \
  && ( echo extension=blackfire.so \
  && echo blackfire.agent_socket=tcp://blackfire:8707 ) > $(php -i | grep "additional .ini" | awk '{print $9}')/blackfire.ini \
  && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz

## Install Sodium
RUN rm -f /usr/local/etc/php/conf.d/*sodium.ini \
  && rm -f /usr/local/lib/php/extensions/*/*sodium.so \
  && apt-get remove libsodium* -y  \
  && mkdir -p /tmp/libsodium  \
  && curl -sL https://github.com/jedisct1/libsodium/archive/1.0.18-RELEASE.tar.gz | tar xzf - -C  /tmp/libsodium \
  && cd /tmp/libsodium/libsodium-1.0.18-RELEASE/ \
  && ./configure \
  && make && make check \
  && make install  \
  && cd / \
  && rm -rf /tmp/libsodium  \
  && pecl install -o -f libsodium

## Install Ioncube
RUN cd /tmp \
  && curl -O https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz \
  && tar zxvf ioncube_loaders_lin_x86-64.tar.gz \
  && export PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;") \
  && export PHP_EXT_DIR=$(php-config --extension-dir) \
  && cp "./ioncube/ioncube_loader_lin_${PHP_VERSION}.so" "${PHP_EXT_DIR}/ioncube.so" \
  && rm -rf ./ioncube \
  && rm ioncube_loaders_lin_x86-64.tar.gz

## Install Sendmail for MailHog
RUN curl -sSLO https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 \
  && chmod +x mhsendmail_linux_amd64 \
  && mv mhsendmail_linux_amd64 /usr/local/bin/mhsendmail

## Enable PHP Extensions
RUN docker-php-ext-enable \
  bcmath \
  blackfire \
  bz2 \
  calendar \
  exif \
  gd \
  geoip \
  gettext \
  gmp \
  gnupg \
  igbinary \
  imagick \
  intl \
  ldap \
  mailparse \
  msgpack \
  mysqli \
  oauth \
  opcache \
  pcov \
  pdo_mysql \
  propro \
  pspell \
  raphf \
  redis \
  shmop \
  soap \
  sockets \
  sodium \
  sysvmsg \
  sysvsem \
  sysvshm \
  tidy \
  xdebug \
  xmlrpc \
  xsl \
  yaml \
  zip \
  pcntl \
  ssh2 \
  ioncube

## Install Composer
RUN curl -sS https://getcomposer.org/installer | \
  php -- --version=1.10.19 --install-dir=/usr/local/bin --filename=composer


# BASE CONFIGURATION ---------------------------------------------------------------------------------------------------

## Add user www with ID 1000. It means that the user in your local machine will be the same user in Docker container.
RUN groupadd -g 1000 ${APP_GROUP} && useradd -g 1000 -u 1000 -d ${APP_HOME} -s /bin/bash ${APP_USER}

COPY conf/conf.d/*.ini /usr/local/etc/php/conf.d/
COPY conf/php.ini /usr/local/etc/php/php.ini
COPY conf/php-fpm.conf /usr/local/etc/

## Disable XDebug by default
RUN sed -i -e 's/^zend_extension/\;zend_extension/g' /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

COPY fpm-healthcheck.sh /usr/local/bin/fpm-healthcheck.sh
RUN ["chmod", "+x", "/usr/local/bin/fpm-healthcheck.sh"]

HEALTHCHECK --retries=3 CMD ["bash", "/usr/local/bin/fpm-healthcheck.sh"]

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN ["chmod", "+x", "/docker-entrypoint.sh"]

RUN touch ${APP_HOME}/.bashrc \
  && echo "alias ll=\"ls $LS_OPTIONS -lah\"" >> ${APP_HOME}/.bashrc \
  && echo "alias l=\"ll\"" >> ${APP_HOME}/.bashrc

RUN mkdir -p ${APP_ROOT} \
  && chown -R ${APP_USER}:${APP_GROUP} ${APP_HOME} /usr/local/etc/php/conf.d

VOLUME ${APP_HOME}

ENTRYPOINT ["/docker-entrypoint.sh"]

USER root

WORKDIR ${APP_ROOT}

CMD ["php-fpm", "-R"]

#-----------------------------------------------------------------------------------------------------------------------
