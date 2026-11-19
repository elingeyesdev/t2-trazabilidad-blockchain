<?php

namespace Tests\Feature;

use App\Models\CertificacionLote;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Symfony\Component\Process\Process;
use Tests\Support\CertificadosFixture;
use Tests\TestCase;

class CertificadoConcurrenciaTest extends TestCase
{
    public function test_procesos_reales_reintentan_sin_duplicar_y_emiten_numeros_independientes(): void
    {
        $db = tempnam(sys_get_temp_dir(), 'edt44db');
        $root = $db.'.files';
        $procesos = [];
        mkdir($root);
        try {
            config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $db,
                'filesystems.disks.local.root' => $root, 'cache.default' => 'array', 'blockchain.enabled' => false]);
            DB::purge('sqlite');
            Storage::forgetDisk('local');
            DB::statement('PRAGMA busy_timeout = 20000');
            Artisan::call('migrate', ['--force' => true]);
            $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
            $f = CertificadosFixture::crear();
            foreach (['reintento', 'intencional'] as $modo) {
                $gate = $db.'.'.$modo;
                $procesos = [];
                $key = (string) Str::uuid();
                foreach ([0, 1] as $i) {
                    $p = new Process([PHP_BINARY, '-d', 'max_execution_time=0', base_path('tests/Fixtures/certificado_concurrent_worker.php'),
                        $db, $root, $gate, (string) $i, (string) $f['agricola']->getKey(), (string) $f['campoCertificable']->getKey(),
                        $modo === 'reintento' ? $key : (string) Str::uuid()], base_path());
                    $p->setTimeout(120)->start();
                    $procesos[] = $p;
                }
                $deadline = microtime(true) + 90;
                while (! is_file($gate.'.ready.0') || ! is_file($gate.'.ready.1')) {
                    if (microtime(true) > $deadline) {
                        $this->fail('Barrera: '.implode(' ', array_map(fn ($p) => $p->getErrorOutput(), $procesos)));
                    }
                    usleep(10000);
                }
                $this->assertNotSame($procesos[0]->getPid(), $procesos[1]->getPid());
                file_put_contents($gate, 'start');
                $resultados = [];
                foreach ($procesos as $p) {
                    $p->wait();
                    $this->assertTrue($p->isSuccessful(), $p->getErrorOutput());
                    $resultados[] = json_decode($p->getOutput(), true, 512, JSON_THROW_ON_ERROR);
                }
                if ($modo === 'reintento') {
                    $this->assertSame($resultados[0], $resultados[1]);
                    $primero = CertificacionLote::firstOrFail();
                    $antes = $primero->getAttributes();
                    $bytes = Storage::disk('local')->get($primero->archivo_path);
                    $this->assertDatabaseCount('certificacion_lote', 1);
                    $this->assertCount(1, Storage::disk('local')->allFiles('certificados'));
                } else {
                    $this->assertNotSame($resultados[0]['id'], $resultados[1]['id']);
                    $this->assertNotSame($resultados[0]['codigo'], $resultados[1]['codigo']);
                    $this->assertDatabaseCount('certificacion_lote', 3);
                    $this->assertCount(3, Storage::disk('local')->allFiles('certificados'));
                    $this->assertSame($antes, $primero->fresh()->getAttributes());
                    $this->assertSame($bytes, Storage::disk('local')->get($primero->archivo_path));
                }
            }
        } finally {
            foreach ($procesos as $p) {
                if ($p->isRunning()) {
                    $p->stop();
                }
            }
            Storage::disk('local')->deleteDirectory('certificados');
            DB::disconnect('sqlite');
            foreach (glob($db.'.*') ?: [] as $path) {
                if (is_file($path)) {
                    unlink($path);
                }
            }
            foreach ([$db, $db.'-wal', $db.'-shm'] as $path) {
                if (is_file($path)) {
                    unlink($path);
                }
            }
            if (is_dir($root)) {
                rmdir($root);
            }
        }
    }
}
