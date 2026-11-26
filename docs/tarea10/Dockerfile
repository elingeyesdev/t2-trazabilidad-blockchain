FROM node:22-bookworm-slim AS assets
WORKDIR /build
COPY Web/package.json Web/package-lock.json ./
RUN npm ci
COPY Web/resources/ ./resources/
COPY Web/vite.config.js ./
RUN npm run build

FROM php:8.3-apache-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
      git unzip libpq-dev libzip-dev libpng-dev \
      libjpeg62-turbo-dev libfreetype6-dev libonig-dev libxml2-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" pdo_pgsql zip gd mbstring bcmath dom \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
WORKDIR /var/www/html
COPY Web/ ./
COPY --from=assets /build/public/build/ ./public/build/
COPY docs/tarea10/apache.conf /etc/apache2/sites-available/000-default.conf

ENV APP_ENV=production APP_DEBUG=false COMPOSER_ALLOW_SUPERUSER=1 \
    XDG_CONFIG_HOME=/var/www/html/storage/framework
RUN mkdir -p storage/framework/cache/data storage/framework/sessions \
      storage/framework/views storage/logs storage/app/public bootstrap/cache \
    && composer install --no-dev --no-interaction --prefer-dist \
      --optimize-autoloader --no-scripts \
    && php artisan package:discover --ansi \
    && ln -s ../storage/app/public public/storage \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R u=rwX,g=rX,o= storage bootstrap/cache

EXPOSE 80
CMD ["apache2-foreground"]
