<?php

require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $argv[1], 'cache.default' => 'array']);
Illuminate\Support\Facades\DB::purge('sqlite');
Illuminate\Support\Facades\DB::statement('PRAGMA busy_timeout = 20000');
$usuario = App\Models\Usuario::findOrFail($argv[4]);
auth()->setUser($usuario);
file_put_contents($argv[2].'.ready.'.$argv[3], 'ready');
$limite = microtime(true) + 45;
while (! is_file($argv[2])) {
    if (microtime(true) > $limite) {
        throw new RuntimeException('La barrera de resolución no se abrió.');
    }
    usleep(10000);
}
try {
    app(App\Services\IncidenteSeguimientoService::class)->resolver($usuario, (int) $argv[5], $argv[6]);
    echo json_encode(['status' => 200]);
} catch (Symfony\Component\HttpKernel\Exception\HttpException $e) {
    echo json_encode(['status' => $e->getStatusCode()]);
}
