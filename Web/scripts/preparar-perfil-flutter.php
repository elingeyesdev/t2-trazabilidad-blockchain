<?php

// Datos ficticios para integrar perfil y permisos sin usar la base habitual.
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

$web = dirname(__DIR__);
$envPath = $web.'/.env.profilecheck';
if (is_file($envPath)) {
    fwrite(STDERR, "Ya existe .env.profilecheck. Se conserva el entorno anterior.\n");
    exit(1);
}
require $web.'/vendor/autoload.php';
$app = require $web.'/bootstrap/app.php';
if ($app->configurationIsCached()) {
    fwrite(STDERR, "La verificación requiere Laravel sin caché de configuración.\n");
    exit(1);
}
$directory = sys_get_temp_dir().'/agrofusion-perfil-flutter-'.bin2hex(random_bytes(8));
if (! mkdir($directory, 0700)) {
    throw new RuntimeException('No se pudo crear el directorio temporal.');
}
$database = str_replace('\\', '/', $directory.'/database.sqlite');
if (! touch($database)) {
    throw new RuntimeException('No se pudo crear la base de verificación.');
}
$environment = [
    'APP_NAME' => 'AgroFusion', 'APP_ENV' => 'profilecheck',
    'APP_KEY' => 'base64:'.base64_encode(random_bytes(32)),
    'APP_DEBUG' => 'false', 'APP_URL' => 'http://127.0.0.1:8009',
    'DB_CONNECTION' => 'sqlite', 'DB_URL' => '', 'DB_DATABASE' => $database,
    'CACHE_STORE' => 'array', 'SESSION_DRIVER' => 'array',
    'QUEUE_CONNECTION' => 'sync', 'MAIL_MAILER' => 'array', 'BCRYPT_ROUNDS' => '4',
];
$lines = [];
foreach ($environment as $key => $value) {
    $lines[] = $key.'="'.$value.'"';
    putenv($key.'='.$value);
    $_ENV[$key] = $_SERVER[$key] = $value;
}
if (file_put_contents($envPath, implode(PHP_EOL, $lines).PHP_EOL) === false) {
    throw new RuntimeException('No se pudo guardar .env.profilecheck.');
}
$app->loadEnvironmentFrom('.env.profilecheck');
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
if (! $app->environment('profilecheck') || config('database.default') !== 'sqlite'
    || str_replace('\\', '/', config('database.connections.sqlite.database')) !== $database) {
    throw new RuntimeException('El entorno no corresponde a la base aislada.');
}
if (Illuminate\Support\Facades\Artisan::call('migrate', ['--force' => true]) !== 0) {
    throw new RuntimeException('No se pudieron ejecutar las migraciones.');
}
(new Database\Seeders\RolePermissionSeeder)->run();
// El caso negativo usa el nombre admin sin permisos, solo en esta base vacía.
Spatie\Permission\Models\Role::findByName('admin', 'web')->syncPermissions([]);
$cases = [
    'campo' => ['Campo', ['agricultor'], []],
    'multirrol' => ['Equipo', ['agricultor', 'planta'], []],
    'directo' => ['Permiso directo', [], ['pedidos.view']],
    'sinpermisos' => ['Sin permisos', [], []],
    'adminvacio' => ['Admin sin permisos', ['admin'], []],
    'supervisor' => ['Supervisor', ['admin'], ['usuarios.admin']],
];
$users = [];
foreach ($cases as $key => [$name, $roles, $permissions]) {
    $user = App\Models\Usuario::create([
        'nombre' => $name, 'apellido' => 'Flutter',
        'email' => 'flutter.'.$key.'@example.test', 'nombreusuario' => 'flutter_'.$key,
        'passwordhash' => Illuminate\Support\Facades\Hash::make('Flutter-Perfil-2026'),
        'activo' => true, 'estado_cuenta' => App\Support\CuentaEstado::APROBADO,
        'bienvenida_vista' => true, 'nombreusuario_editado' => false,
    ]);
    $user->syncRoles($roles);
    $user->syncPermissions($permissions);
    $users[$key] = $user;
    echo $user->email.' | roles: '.implode(', ', $roles)
        .' | permisos: '.implode(', ', $user->getAllPermissions()->pluck('name')->sort()->all())."\n";
}
$cultivo = App\Models\Cultivo::create(['nombre' => 'Tomate de prueba']);
$estado = App\Models\EstadoLoteTipo::firstOrCreate(['nombre' => 'Planificado']);
foreach (['campo', 'multirrol'] as $key) {
    $lote = App\Models\Lote::create(App\Support\LoteDefaults::enrich([
        'usuarioid' => $users[$key]->usuarioid, 'nombre' => 'Lote Flutter '.$key,
        'superficie' => 1.5, 'ubicacion' => 'Entorno ficticio de verificación',
        'cultivoid' => $cultivo->cultivoid, 'estadolotetipoid' => $estado->estadolotetipoid,
    ]));
    App\Support\LoteDefaults::registrarHistorialInicial($lote);
}
$pedido = App\Models\Pedido::create([
    'numero_solicitud' => 'FLUTTER-PERFIL-001', 'nombre_planta' => 'Planta de prueba',
    'latitud' => 0, 'longitud' => 0, 'estado' => 'pendiente', 'fechapedido' => now(),
]);
$pedido->detalles()->create(['cultivo_personalizado' => 'Tomate de prueba', 'cantidad' => 5]);

echo "Perfil preparado: .env.profilecheck\nBase SQLite aislada: {$database}\n";
echo "Contraseña ficticia común: Flutter-Perfil-2026\n";
echo "Ejecuta: php artisan serve --env=profilecheck --host=127.0.0.1 --port=8009 --no-reload\n";
