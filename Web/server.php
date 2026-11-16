<?php

// Match the production web-server restriction when using `artisan serve`.
$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?? '');
$target = realpath(getcwd().$uri);
$evidencias = realpath(__DIR__.'/storage/app/public/actividades_evidencia');
$normalizar = static fn (string $path) => strtolower(str_replace('\\', '/', $path));
if (preg_match('#^/storage/actividades_evidencia(?:/|$)#i', $uri)
    || ($target && $evidencias && str_starts_with($normalizar($target), $normalizar($evidencias).'/'))) {
    http_response_code(403);
    return;
}

return require __DIR__.'/vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php';
