<?php

require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $argv[1], 'cache.default' => 'array']);
Illuminate\Support\Facades\DB::purge('sqlite');
Illuminate\Support\Facades\DB::statement('PRAGMA busy_timeout = 20000');
config(['filesystems.disks.local.root' => $argv[1].'.firmas']);
$usuario = App\Models\Usuario::findOrFail($argv[4]);
auth()->setUser($usuario);
$qr = App\Models\RecepcionQrEnvio::findOrFail($argv[5]);
$service = app(App\Services\EnvioRecepcionQrService::class);
$lineas = array_map(fn ($l) => ['id' => $l['id'], 'cantidad_recibida' => $l['cantidad_enviada']], app(App\Services\EnvioMovilConsultaService::class)->lineas($service->operacion($qr), $usuario));
file_put_contents($argv[2].'.ready.'.$argv[3], 'ready');
$limite = microtime(true) + 45;
while (! is_file($argv[2])) {
    if (microtime(true) > $limite) {
        throw new RuntimeException('La barrera no se abrió.');
    }
    usleep(10000);
}
try {
    $service->confirmar($qr, $usuario, $lineas, Tests\Support\EnvioQrFixture::firma());
    echo json_encode(['status' => 201]);
} catch (Symfony\Component\HttpKernel\Exception\HttpException $e) {
    echo json_encode(['status' => $e->getStatusCode()]);
}
