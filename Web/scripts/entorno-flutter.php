<?php

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

function prepararEntornoFlutter(string $perfil, int $puerto, string $prefijoTemporal): string
{
    $web = dirname(__DIR__);
    $envFile = '.env.'.$perfil;
    $envPath = $web.'/'.$envFile;
    if (is_file($envPath)) {
        fwrite(STDERR, "Ya existe {$envFile}. Se conserva el entorno anterior sin modificarlo.\n");
        exit(1);
    }

    require_once $web.'/vendor/autoload.php';
    $app = require $web.'/bootstrap/app.php';
    if ($app->configurationIsCached()) {
        fwrite(STDERR, "La verificación requiere Laravel sin caché de configuración.\n");
        exit(1);
    }

    $directory = sys_get_temp_dir().'/'.$prefijoTemporal.bin2hex(random_bytes(8));
    if (! mkdir($directory, 0700)) {
        throw new RuntimeException('No se pudo crear el directorio temporal de verificación.');
    }
    $database = str_replace('\\', '/', $directory.'/database.sqlite');
    if (! touch($database)) {
        throw new RuntimeException('No se pudo crear la base de verificación.');
    }

    $environment = [
        'APP_NAME' => 'AgroFusion',
        'APP_ENV' => $perfil,
        'APP_KEY' => 'base64:'.base64_encode(random_bytes(32)),
        'APP_DEBUG' => 'false',
        'APP_URL' => 'http://127.0.0.1:'.$puerto,
        'DB_CONNECTION' => 'sqlite',
        'DB_URL' => '',
        'DB_DATABASE' => $database,
        'CACHE_STORE' => 'array',
        'SESSION_DRIVER' => 'array',
        'QUEUE_CONNECTION' => 'sync',
        'MAIL_MAILER' => 'array',
        'BCRYPT_ROUNDS' => '4',
    ];
    $lines = [];
    foreach ($environment as $key => $value) {
        $lines[] = $key.'="'.$value.'"';
        putenv($key.'='.$value);
        $_ENV[$key] = $_SERVER[$key] = $value;
    }
    if (file_put_contents($envPath, implode(PHP_EOL, $lines).PHP_EOL) === false) {
        throw new RuntimeException('No se pudo guardar '.$envFile.'.');
    }

    $app->loadEnvironmentFrom($envFile);
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    if (! $app->environment($perfil)
        || config('database.default') !== 'sqlite'
        || str_replace('\\', '/', config('database.connections.sqlite.database')) !== $database) {
        throw new RuntimeException('El entorno no corresponde a la base aislada; se cancela la preparación.');
    }
    if (Illuminate\Support\Facades\Artisan::call('migrate', ['--force' => true]) !== 0) {
        throw new RuntimeException('No se pudieron ejecutar las migraciones de la base aislada.');
    }
    (new Database\Seeders\RolePermissionSeeder)->run();

    return $database;
}
