<?php

namespace Tests\Feature;

use App\Models\PedidoDistribucion;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Symfony\Component\Process\Process;
use Tests\Support\PedidoDecisionFixture as Fixture;
use Tests\TestCase;

class PedidoDecisionConcurrenciaTest extends TestCase
{
    public function test_decisiones_simultaneas_sobre_el_mismo_pedido_y_saldo_compartido(): void
    {
        $db = tempnam(sys_get_temp_dir(), 'edt53');
        $procesos = [];
        try {
            config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $db, 'cache.default' => 'array']);
            DB::purge('sqlite');
            DB::statement('PRAGMA busy_timeout = 20000');
            Artisan::call('migrate', ['--force' => true]);
            $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
            $f = Fixture::crear();
            foreach (['agricolas', 'distribucion'] as $tipo) {
                foreach (['aceptaciones', 'rechazos', 'opuestas', 'saldo'] as $caso) {
                    // Cada caso comienza sin reservas de pruebas anteriores.
                    PedidoDistribucion::query()->where('estado', 'confirmado')->update(['estado' => 'cancelado']);
                    $f['cosechas'][0]->refresh()->update(['cantidad' => 10, 'fechasalida' => null]);
                    $p = Fixture::pedido($f, $tipo);
                    $pedidos = [$p, $caso === 'saldo' ? Fixture::pedido($f, $tipo) : $p];
                    $actor = $f[$tipo === 'agricolas' ? 'agricola' : 'mayorista'];
                    $gate = $db.'.'.$tipo.'.'.$caso;
                    $procesos = [];
                    foreach ([0, 1] as $i) {
                        $accion = $caso === 'rechazos' || ($caso === 'opuestas' && $i === 1) ? 'rechazar' : 'aceptar';
                        $worker = new Process([PHP_BINARY, '-d', 'max_execution_time=0', base_path('tests/Fixtures/pedido_concurrent_worker.php'),
                            $db, $gate, (string) $i, (string) $actor->getKey(), (string) $pedidos[$i]->getKey(),
                            $tipo === 'agricolas' ? 'agricola' : 'distribucion', $accion, 'Motivo concurrente'], base_path());
                        $worker->setTimeout(60)->start();
                        $procesos[] = $worker;
                    }
                    $limite = microtime(true) + 45;
                    while (! is_file($gate.'.ready.0') || ! is_file($gate.'.ready.1')) {
                        if (microtime(true) > $limite) {
                            $this->fail('No se alcanzó la barrera: '.implode(' ', array_map(fn ($p) => $p->getErrorOutput(), $procesos)));
                        }
                        usleep(10000);
                    }
                    $this->assertNotSame($procesos[0]->getPid(), $procesos[1]->getPid());
                    file_put_contents($gate, 'start');
                    $estados = [];
                    foreach ($procesos as $worker) {
                        $worker->wait();
                        $this->assertTrue($worker->isSuccessful(), $worker->getErrorOutput());
                        $estados[] = json_decode($worker->getOutput(), true, 512, JSON_THROW_ON_ERROR)['status'];
                    }
                    sort($estados);
                    $this->assertSame(match ($caso) {
                        'opuestas' => [200, 409], 'saldo' => [200, 422], default => [200, 200],
                    }, $estados, $tipo.' '.$caso);
                    $unicos = collect($pedidos)->unique(fn ($p) => $p->getKey());
                    $this->assertSame(1, $unicos->sum(fn ($p) => $p->decisiones()->count()));
                    $aceptados = $unicos->filter(fn ($p) => $p->fresh()->estado === 'confirmado')->count();
                    if ($tipo === 'agricolas') {
                        $this->assertEquals(10 - 6 * $aceptados, $f['cosechas'][0]->fresh()->cantidad);
                    } else {
                        $this->assertEquals(10, $f['producto']->fresh()->stock);
                        $this->assertEquals(10, $f['partida']->fresh()->cantidad_unidades);
                        $this->assertLessThanOrEqual(1, $aceptados);
                    }
                }
            }
        } finally {
            foreach ($procesos as $worker) {
                if ($worker->isRunning()) {
                    $worker->stop();
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
