FROM php:8.5-apache

ARG BUILD_ID=Entwicklung

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl default-mysql-client openssl \
    && docker-php-ext-install pdo_mysql \
    && a2enmod headers rewrite ssl \
    && sed -ri 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf \
    && openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout /etc/ssl/private/ssl-cert-snakeoil.key \
      -out /etc/ssl/certs/ssl-cert-snakeoil.pem \
      -subj '/CN=localhost' \
    && a2ensite default-ssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
COPY . .
RUN printf '%s\n' "$BUILD_ID" > .build-id
