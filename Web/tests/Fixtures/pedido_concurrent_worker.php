<?php

require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $argv[1], 'cache.default' => 'array']);
Illuminate\Support\Facades\DB::purge('sqlite');
Illuminate\Support\Facades\DB::statement('PRAGMA busy_timeout = 20000');
$user = App\Models\Usuario::findOrFail($argv[4]);
auth()->setUser($user);
$request = Illuminate\Http\Request::create('/prueba-concurrente', 'POST');
$request->setUserResolver(fn () => $user);
$app->instance('request', $request);
$modelo = $argv[6] === 'agricola' ? App\Models\Pedido::class : App\Models\PedidoDistribucion::class;
$pedido = $modelo::findOrFail($argv[5]);
file_put_contents($argv[2].'.ready.'.$argv[3], 'ready');
$limite = microtime(true) + 45;
while (! is_file($argv[2])) {
    if (microtime(true) > $limite) {
        throw new RuntimeException('Barrera sin abrir.');
    }
    usleep(10000);
}
try {
    $pedido = app(App\Services\PedidoTransicionService::class)->ejecutar($pedido, $user, 'aceptar');
    echo json_encode(['status' => 200, 'estado' => $pedido->estado]);
} catch (InvalidArgumentException|Illuminate\Validation\ValidationException $e) {
    echo json_encode(['status' => 422, 'message' => $e->getMessage()]);
}
