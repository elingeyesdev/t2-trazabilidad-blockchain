<?php

require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $argv[1], 'cache.default' => 'array']);
Illuminate\Support\Facades\DB::purge('sqlite');
Illuminate\Support\Facades\DB::statement('PRAGMA busy_timeout = 10000');
Illuminate\Support\Carbon::setTestNow($argv[6]);
$datos = json_decode($argv[4], true, 512, JSON_THROW_ON_ERROR);
file_put_contents($argv[3].'.ready.'.$argv[5], 'ready');
$limite = microtime(true) + 100;
while (! is_file($argv[3])) {
    if (microtime(true) > $limite) {
        throw new RuntimeException('La barrera de concurrencia no se abrió.');
    }
    usleep(10000);
}
try {
    Illuminate\Support\Facades\DB::transaction(function () use ($argv, $datos) {
        // Mantener la transacción abierta permite que el segundo proceso compita de verdad.
        app(App\Services\InventarioExistenciaService::class)->bloquear([$datos['insumoid']]);
        usleep(250000);
        app(App\Services\InventarioMovimientoService::class)->registrar(App\Models\Usuario::findOrFail($argv[2]), $datos, 'salida');
    }, 5);
    echo 'CONFIRMADO';
} catch (Illuminate\Validation\ValidationException $error) {
    echo 'RECHAZADO:'.json_encode($error->errors(), JSON_UNESCAPED_UNICODE);
}
