<?php

require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $argv[1], 'cache.default' => 'array',
    'filesystems.disks.local.root' => $argv[2], 'blockchain.enabled' => false]);
Illuminate\Support\Facades\DB::purge('sqlite');
Illuminate\Support\Facades\DB::statement('PRAGMA busy_timeout = 20000');
$gate = $argv[3];
$index = $argv[4];
$app->instance(App\Services\CertificadoDocumentoService::class, new class($gate, $index) extends App\Services\CertificadoDocumentoService
{
    public function __construct(private string $gate, private string $index) {}

    public function generar(array $datos): string
    {
        file_put_contents($this->gate.'.pdf.'.$this->index, 'ready');
        $deadline = microtime(true) + 90;
        while (! is_file($this->gate.'.pdf.0') || ! is_file($this->gate.'.pdf.1')) {
            if (microtime(true) > $deadline) {
                throw new RuntimeException('No llegó el segundo generador.');
            }
            usleep(10000);
        }

        return '%PDF-1.4 '.json_encode($datos);
    }
});
$usuario = App\Models\Usuario::findOrFail($argv[5]);
$lote = App\Models\Lote::findOrFail($argv[6]);
file_put_contents($gate.'.ready.'.$index, 'ready');
$deadline = microtime(true) + 90;
while (! is_file($gate)) {
    if (microtime(true) > $deadline) {
        throw new RuntimeException('Barrera sin abrir.');
    }
    usleep(10000);
}
$e = app(App\Services\CertificadoEmisionService::class)->emitirCampo($usuario, $lote, ['solicitud_id' => $argv[7]]);
echo json_encode(['id' => $e->getKey(), 'codigo' => $e->codigo_certificado]);
