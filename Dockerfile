FROM php:7.4.8-fpm-buster
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

## Install base dependencies
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
  apt-utils \
  sendmail-bin \
  sendmail \
  sudo \
  wget \
  unzip

## Install Tools
RUN apt update && apt install -y \
  git \
  lsof \
  vim \
  procps \
  watch

## Install PHP dependencies (required to configure the GD library)
RUN apt update && apt install -y \
  ## required to configure the GD library
  libfreetype6-dev \
  libjpeg62-turbo-dev \
  libpng-dev \
  zlib1g-dev \
  libwebp-dev \
  ## required to configure the LDAP
  libldb-dev \
  libldap2-dev \
  && rm -rf /var/lib/apt/lists/*

## Install required PHP extensions
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions && sync && install-php-extensions \
  bcmath \
  bz2 \
  calendar \
  exif \
  gd \
  gettext \
  gmp \
  igbinary \
  imagick \
  intl \
  ldap \
  mailparse \
  msgpack \
  mysqli \
  oauth \
  opcache \
  pcntl \
  pcov \
  pdo_mysql \
  pspell \
  raphf \
  redis \
  shmop \
  soap \
  sockets \
  sysvmsg \
  sysvsem \
  sysvshm \
  tidy \
  uuid \
  # Install the most recent xdebug 3.x version (for example 3.0.4)
  xdebug-^3 \
  xsl \
  yaml \
  zip \
  # Not available in PHP 8.0
  gnupg \
  propro \
  ssh2 \
  xmlrpc

## Configure the GD library
RUN docker-php-ext-configure \
  gd --enable-gd=/usr/include/ \
     --with-freetype=/usr/include/ \
     --with-jpeg=/usr/include/ \
     --with-webp=/usr/include/
RUN docker-php-ext-configure \
  ldap --with-libdir=lib/x86_64-linux-gnu
RUN docker-php-ext-configure \
  opcache --enable-opcache

## Install Blackfire
RUN curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/linux/amd64/$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;") \
  && mkdir -p /tmp/blackfire \
  && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
  && mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get ('extension_dir');")/blackfire.so \
  && ( echo extension=blackfire.so \
  && echo blackfire.agent_socket=tcp://blackfire:8707 ) > $(php -i | grep "additional .ini" | awk '{print $9}')/blackfire.ini \
  && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz

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

## Install Composer (version one and two)
RUN curl -o /usr/local/bin/composer -O https://getcomposer.org/composer-2.phar && \
    curl -o /usr/local/bin/composer1 -O https://getcomposer.org/composer-1.phar && \
    ln -s /usr/local/bin/composer /usr/local/bin/composer2 && \
    chmod +x /usr/local/bin/composer*


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
