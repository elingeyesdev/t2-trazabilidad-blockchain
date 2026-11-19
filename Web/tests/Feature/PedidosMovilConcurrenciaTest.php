<?php

namespace Tests\Feature;

use App\Models\Almacen;
use App\Models\DetallePedido;
use App\Models\DetallePedidoDistribucion;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Insumo;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\PuntoVenta;
use App\Models\TipoInsumo;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Symfony\Component\Process\Process;
use Tests\Support\CertificadosFixture;
use Tests\TestCase;

class PedidosMovilConcurrenciaTest extends TestCase
{
    public function test_dos_procesos_no_aceptan_mas_stock_que_el_disponible_en_ambos_tipos(): void
    {
        $db = tempnam(sys_get_temp_dir(), 'edt51db');
        $procesos = [];
        try {
            config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $db, 'cache.default' => 'array']);
            DB::purge('sqlite');
            DB::statement('PRAGMA busy_timeout = 20000');
            Artisan::call('migrate', ['--force' => true]);
            $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
            $f = CertificadosFixture::crear();
            $almAgr = Almacen::create(['nombre' => 'Agrícola concurrente', 'ubicacion' => 'Prueba', 'ambito' => 'agricola', 'activo' => true,
                'responsable_usuarioid' => $f['agricola']->getKey(), 'unidadmedidaid' => $f['kg']->getKey(), 'capacidad' => 1000]);
            $f['cosechas'][0]->update(['almacenid' => $almAgr->getKey(), 'cantidad' => 10, 'fechasalida' => null]);
            $mayorista = CertificadosFixture::usuario('mayorista', 'race51may');
            $minorista = CertificadosFixture::usuario('minorista', 'race51min');
            $almacen = Almacen::create(['nombre' => 'Mayorista concurrente', 'ubicacion' => 'Prueba', 'ambito' => 'mayorista', 'activo' => true,
                'responsable_usuarioid' => $mayorista->getKey(), 'unidadmedidaid' => $f['kg']->getKey(), 'capacidad' => 1000]);
            $insumo = Insumo::create(['nombre' => 'Producto concurrente', 'almacenid' => $almacen->getKey(), 'stock' => 10,
                'unidadmedidaid' => $f['kg']->getKey(), 'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Producto terminado'])->getKey()]);
            $presentacion = InsumoPresentacion::create(['insumoid' => $insumo->getKey(), 'nombre' => 'Bolsa 1 kg', 'tipo_envase' => 'bolsa', 'peso_neto_kg' => 1, 'activo' => true]);
            $partida = InventarioPresentacionLote::create(['insumoid' => $insumo->getKey(), 'almacenid' => $almacen->getKey(),
                'insumo_presentacionid' => $presentacion->getKey(), 'cantidad_unidades' => 10, 'cantidad_kg' => 10]);
            $pdv = PuntoVenta::create(['usuarioid' => $minorista->getKey(), 'nombre' => 'PDV concurrente', 'direccion' => 'Prueba', 'activo' => true]);
            foreach (['agricola', 'distribucion'] as $tipo) {
                $gate = $db.'.'.$tipo;
                $procesos = [];
                foreach ([0, 1] as $i) {
                    if ($tipo === 'agricola') {
                        $pedido = Pedido::create(['numero_solicitud' => 'AGR-RACE-'.$i, 'estado' => 'sin asignacion', 'creado_por_usuarioid' => $f['agricola']->getKey(),
                            'fechapedido' => now(), 'latitud' => -17, 'longitud' => -63]);
                        DetallePedido::create(['pedidoid' => $pedido->getKey(), 'producto_ref' => 'cosecha:'.$f['cosechas'][0]->getKey(), 'produccionalmacenamientoid' => $f['cosechas'][0]->getKey(), 'cultivo_personalizado' => 'Tomate', 'cantidad' => 6]);
                        EnvioAsignacionMultiple::create(['pedidoid' => $pedido->getKey(), 'externo_envio_id' => $pedido->numero_solicitud, 'estado' => 'pendiente', 'asignadopor_usuarioid' => $f['agricola']->getKey()]);
                        $actor = $f['agricola'];
                    } else {
                        $pedido = PedidoDistribucion::create(['numero_solicitud' => 'DIS-RACE-'.$i, 'puntoventaid' => $pdv->getKey(), 'almacen_mayorista_origenid' => $almacen->getKey(), 'estado' => 'pendiente', 'tipo_solicitud' => 'stock', 'fechapedido' => now()]);
                        DetallePedidoDistribucion::create(['pedidodistribucionid' => $pedido->getKey(), 'insumoid' => $insumo->getKey(), 'insumo_presentacionid' => $presentacion->getKey(),
                            'inventario_presentacion_loteid' => $partida->getKey(), 'almacen_mayorista_origenid' => $almacen->getKey(), 'producto_nombre' => 'Producto concurrente', 'cantidad' => 6,
                            'datos_solicitud' => ['unidad' => 'bolsas', 'cantidad_kg' => '6.000000']]);
                        $actor = $mayorista;
                    }
                    $p = new Process([PHP_BINARY, '-d', 'max_execution_time=0', base_path('tests/Fixtures/pedido_concurrent_worker.php'), $db, $gate, (string) $i, (string) $actor->getKey(), (string) $pedido->getKey(), $tipo], base_path());
                    $p->setTimeout(60)->start();
                    $procesos[] = $p;
                }
                $limite = microtime(true) + 45;
                while (! is_file($gate.'.ready.0') || ! is_file($gate.'.ready.1')) {
                    if (microtime(true) > $limite) {
                        $this->fail('Barrera: '.implode(' ', array_map(fn ($p) => $p->getErrorOutput(), $procesos)));
                    }
                    usleep(10000);
                }
                $this->assertNotSame($procesos[0]->getPid(), $procesos[1]->getPid());
                file_put_contents($gate, 'start');
                $estados = [];
                foreach ($procesos as $p) {
                    $p->wait();
                    $this->assertTrue($p->isSuccessful(), $p->getErrorOutput());
                    $estados[] = json_decode($p->getOutput(), true, 512, JSON_THROW_ON_ERROR)['status'];
                }
                sort($estados);
                $this->assertSame([200, 422], $estados);
            }
            $this->assertEquals(4, $f['cosechas'][0]->fresh()->getRawOriginal('cantidad'));
            $this->assertEquals(10, $partida->fresh()->getRawOriginal('cantidad_unidades'));
            $this->assertSame(1, PedidoDistribucion::where('estado', 'confirmado')->count());
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
