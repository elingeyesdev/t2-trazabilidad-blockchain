<?php

// Match production restrictions when using artisan serve, including legacy symlinks.
$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?? '');
$target = realpath(getcwd().$uri);
$normalizar = static fn (string $path) => strtolower(str_replace('\\', '/', $path));
$carpetas = ['actividades_evidencia', 'documentos_entrega', 'certificados', 'recepciones-envio', 'evidencias_publicadas', 'actividades_privadas'];
$restringido = preg_match('#^/storage/(?:'.implode('|', $carpetas).')(?:/|$)#i', $uri);
foreach ($carpetas as $carpeta) {
    foreach (['public', 'private'] as $disco) {
        $base = realpath(__DIR__.'/storage/app/'.$disco.'/'.$carpeta);
        if ($target && $base && ($normalizar($target) === $normalizar($base)
            || str_starts_with($normalizar($target), $normalizar($base).'/'))) {
            $restringido = true;
        }
    }
}
if ($restringido) {
    http_response_code(403);
    return;
}

return require __DIR__.'/vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php';