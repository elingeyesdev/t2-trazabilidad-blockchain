<?php

namespace Tests\Feature;

use App\Models\AlmacenMovimiento;
use App\Models\RecepcionQrEnvio;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\File;
use Symfony\Component\Process\Process;
use Tests\Support\EnvioQrFixture;
use Tests\TestCase;

class RecepcionQrConcurrenciaTest extends TestCase
{
    public function test_dos_conexiones_independientes_consumen_cada_codigo_una_sola_vez(): void
    {
        $db = tempnam(sys_get_temp_dir(), 'edt52db');
        $procesos = [];
        try {
            config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $db, 'cache.default' => 'array']);
            DB::purge('sqlite');
            DB::statement('PRAGMA busy_timeout = 20000');
            Artisan::call('migrate', ['--force' => true]);
            $this->seed(RolePermissionSeeder::class);
            foreach (['agricola', 'distribucion'] as $tipo) {
                $f = EnvioQrFixture::crear($tipo);
                $antes = AlmacenMovimiento::count();
                $gate = $db.'.'.$tipo;
                $procesos = [];
                foreach ([0, 1] as $i) {
                    $p = new Process([PHP_BINARY, '-d', 'max_execution_time=0', base_path('tests/Fixtures/recepcion_qr_concurrent_worker.php'),
                        $db, $gate, (string) $i, (string) $f['receptor']->getKey(), (string) $f['qr']->getKey()], base_path(), ['APP_ENV' => 'testing', 'APP_KEY' => config('app.key')]);
                    $p->setTimeout(90)->start();
                    $procesos[] = $p;
                }
                $limite = microtime(true) + 60;
                while (! is_file($gate.'.ready.0') || ! is_file($gate.'.ready.1')) {
                    if (microtime(true) > $limite) {
                        $this->fail('No llegaron ambos procesos: '.implode(' ', array_map(fn ($p) => $p->getErrorOutput(), $procesos)));
                    }
                    usleep(10000);
                }
                $this->assertNotSame($procesos[0]->getPid(), $procesos[1]->getPid());
                file_put_contents($gate, 'start');
                $estados = [];
                foreach ($procesos as $p) {
                    $p->wait();
                    $this->assertTrue($p->isSuccessful(), $p->getErrorOutput().$p->getOutput());
                    $this->assertJson($p->getOutput(), $p->getOutput());
                    $estados[] = json_decode($p->getOutput(), true, 512, JSON_THROW_ON_ERROR)['status'];
                }
                sort($estados);
                $this->assertSame([201, 409], $estados);
                $this->assertNotNull($f['qr']->fresh()->utilizado_en);
                $this->assertSame($antes + 1, AlmacenMovimiento::count());
                $this->assertCount(1, $f['qr']->fresh()->datos_recepcion['lineas']);
            }
            $this->assertSame(2, RecepcionQrEnvio::whereNotNull('utilizado_en')->count());
            $this->assertCount(2, File::allFiles($db.'.firmas'));
        } finally {
            foreach ($procesos as $p) {
                if ($p->isRunning()) {
                    $p->stop();
                }
            }
            DB::disconnect('sqlite');
            File::deleteDirectory($db.'.firmas');
            foreach (array_merge(glob($db.'.*') ?: [], [$db, $db.'-wal', $db.'-shm']) as $path) {
                if (is_file($path)) {
                    unlink($path);
                }
            }
        }
    }
}
