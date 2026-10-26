<?php

// Entorno local reproducible para verificar Flutter sin usar la base habitual.
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

$web = dirname(__DIR__);
$envPath = $web.'/.env.authcheck';
if (is_file($envPath)) {
    fwrite(STDERR, "Ya existe .env.authcheck. Se conserva el entorno anterior sin modificarlo.\n");
    exit(1);
}

require $web.'/vendor/autoload.php';
$app = require $web.'/bootstrap/app.php';
if ($app->configurationIsCached()) {
    fwrite(STDERR, "La verificación requiere Laravel sin caché de configuración.\n");
    exit(1);
}

$directory = sys_get_temp_dir().'/agrofusion-auth-flutter-'.bin2hex(random_bytes(8));
if (! mkdir($directory, 0700)) {
    throw new RuntimeException('No se pudo crear el directorio temporal de verificación.');
}
$database = str_replace('\\', '/', $directory.'/database.sqlite');
if (! touch($database)) {
    throw new RuntimeException('No se pudo crear la base de verificación.');
}

$environment = [
    'APP_NAME' => 'AgroFusion',
    'APP_ENV' => 'authcheck',
    'APP_KEY' => 'base64:'.base64_encode(random_bytes(32)),
    'APP_DEBUG' => 'false',
    'APP_URL' => 'http://127.0.0.1:8008',
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
    throw new RuntimeException('No se pudo guardar .env.authcheck.');
}

$app->loadEnvironmentFrom('.env.authcheck');
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
if (! $app->environment('authcheck')
    || config('database.default') !== 'sqlite'
    || str_replace('\\', '/', config('database.connections.sqlite.database')) !== $database) {
    throw new RuntimeException('El entorno no corresponde a la base aislada; se cancela la preparación.');
}

if (Illuminate\Support\Facades\Artisan::call('migrate', ['--force' => true]) !== 0) {
    throw new RuntimeException('No se pudieron ejecutar las migraciones de la base aislada.');
}
(new Database\Seeders\RolePermissionSeeder)->run();
$user = App\Models\Usuario::create([
    'nombre' => 'Cuenta Flutter',
    'apellido' => 'Prueba',
    'email' => 'flutter.autorizado@example.test',
    'nombreusuario' => 'flutter_autorizado',
    'passwordhash' => Illuminate\Support\Facades\Hash::make('Flutter-Prueba-2026'),
    'activo' => true,
    'estado_cuenta' => App\Support\CuentaEstado::APROBADO,
    'bienvenida_vista' => true,
    'nombreusuario_editado' => false,
]);
$user->assignRole('agricultor');

echo "Entorno preparado: .env.authcheck\n";
echo "Base SQLite aislada: {$database}\n";
echo "Cuenta ficticia aprobada: flutter.autorizado@example.test\n";
echo "Contraseña de prueba: Flutter-Prueba-2026\n";
echo "Ejecuta: php artisan serve --env=authcheck --host=127.0.0.1 --port=8008 --no-reload\n";
