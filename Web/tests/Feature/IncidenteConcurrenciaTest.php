<?php

namespace Tests\Feature;

use App\Services\IncidenteSeguimientoService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Symfony\Component\Process\Process;
use Tests\Support\EnvioQrFixture;
use Tests\TestCase;

class IncidenteConcurrenciaTest extends TestCase
{
    public function test_dos_conexiones_no_sobrescriben_la_solucion_y_reintentos_equivalentes_no_duplican(): void
    {
        $db = tempnam(sys_get_temp_dir(), 'issue53db');
        $procesos = [];
        try {
            config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $db, 'cache.default' => 'array']);
            DB::purge('sqlite');
            DB::statement('PRAGMA busy_timeout = 20000');
            Artisan::call('migrate', ['--force' => true]);
            $this->seed(RolePermissionSeeder::class);
            $f = EnvioQrFixture::crear('agricola');
            $f['remitente']->givePermissionTo(['incidentes.view', 'incidentes.resolve']);
            foreach ([['Solución confirmada A', 'Solución confirmada B'], ['Misma solución', 'Misma solución']] as $caso => $notas) {
                $i = app(IncidenteSeguimientoService::class)->registrar($f['conductor'], [
                    'afectado_tipo' => 'envio_agricola', 'afectado_id' => $f['envio']->getKey(),
                    'responsable_usuarioid' => $f['remitente']->getKey(), 'tipo' => 'Retraso', 'descripcion' => 'Problema concurrente']);
                $gate = $db.'.caso'.$caso;
                $procesos = [];
                foreach ($notas as $indice => $nota) {
                    $p = new Process([PHP_BINARY, '-d', 'max_execution_time=0', base_path('tests/Fixtures/incidente_concurrent_worker.php'),
                        $db, $gate, (string) $indice, (string) $f['remitente']->getKey(), (string) $i->getKey(), $nota],
                        base_path(), ['APP_ENV' => 'testing', 'APP_KEY' => config('app.key')]);
                    $p->setTimeout(90)->start();
                    $procesos[] = $p;
                }
                $limite = microtime(true) + 60;
                while (! is_file($gate.'.ready.0') || ! is_file($gate.'.ready.1')) {
                    if (microtime(true) > $limite) {
                        $this->fail('No llegaron los procesos: '.implode(' ', array_map(fn ($p) => $p->getErrorOutput(), $procesos)));
                    }
                    usleep(10000);
                }
                file_put_contents($gate, 'start');
                $estados = [];
                foreach ($procesos as $p) {
                    $p->wait();
                    $this->assertTrue($p->isSuccessful(), $p->getErrorOutput().$p->getOutput());
                    $estados[] = json_decode($p->getOutput(), true, 512, JSON_THROW_ON_ERROR)['status'];
                }
                sort($estados);
                $this->assertSame($caso === 0 ? [200, 409] : [200, 200], $estados);
                $this->assertSame('resuelto', $i->fresh()->estado);
                $this->assertContains($i->fresh()->nota_resolucion, $notas);
                $this->assertSame($f['remitente']->getKey(), $i->fresh()->resueltopor_usuarioid);
            }
        } finally {
            foreach ($procesos as $p) {
                if ($p->isRunning()) {
                    $p->stop();
                }
            }
            DB::disconnect('sqlite');
            foreach (array_merge(glob($db.'.*') ?: [], [$db, $db.'-wal', $db.'-shm']) as $path) {
                if (is_file($path)) {
                    unlink($path);
                }
            }
        }
    }
}
