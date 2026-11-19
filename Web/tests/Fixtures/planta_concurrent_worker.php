<?php

require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $argv[1], 'cache.default' => 'array']);
Illuminate\Support\Facades\DB::purge('sqlite');
Illuminate\Support\Facades\DB::statement('PRAGMA busy_timeout = 10000');
Illuminate\Support\Carbon::setTestNow($argv[8]);
$usuario = App\Models\Usuario::findOrFail($argv[2]);
$modelo = $argv[6] === 'etapa' ? App\Models\AsignacionEtapaPlanta::findOrFail($argv[7]) : App\Models\Pedido::findOrFail($argv[7]);
$datos = json_decode($argv[4], true, 512, JSON_THROW_ON_ERROR);
$retenido = false;
Illuminate\Support\Facades\DB::listen(function ($query) use (&$retenido) {
    if (! $retenido && preg_match('/^update "(?:pedido|lote_produccion_pedido)"/i', $query->sql)) {
        $retenido = true;
        usleep(250000);
    }
});
file_put_contents($argv[3].'.ready.'.$argv[5], 'ready');
$limite = microtime(true) + 100;
while (! is_file($argv[3])) {
    if (microtime(true) > $limite) {
        throw new RuntimeException('Barrera sin abrir.');
    }
    usleep(10000);
}
try {
    if ($argv[6] === 'etapa') {
        app(App\Support\AsignacionEtapaPlantaService::class)->completar($modelo, $datos, $usuario);
    } else {
        app(App\Services\RecepcionPlantaEnvioService::class)->confirmarDesdePedido($modelo, $usuario, $datos);
    }
    echo 'CONFIRMADO';
} catch (App\Exceptions\PlantaConflictoException $e) {
    echo 'CONFLICTO';
}
