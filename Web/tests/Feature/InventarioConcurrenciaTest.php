<?php

namespace Tests\Feature;

use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\Insumo;
use App\Models\TipoAlmacen;
use App\Models\TipoInsumo;
use App\Models\TipoMovimientoAlmacen;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Symfony\Component\Process\Process;
use Tests\TestCase;

class InventarioConcurrenciaTest extends TestCase
{
    public function test_dos_procesos_compiten_en_consumos_y_en_ajuste_con_consumo_sin_saldos_negativos(): void
    {
        $archivo = tempnam(sys_get_temp_dir(), 'edt42db');
        $barrera = $archivo.'.gate';
        $procesos = [];
        try {
            config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $archivo]);
            DB::purge('sqlite');
            DB::statement('PRAGMA busy_timeout = 10000');
            Artisan::call('migrate', ['--force' => true]);
            $this->seed(RolePermissionSeeder::class);
            $usuario = Usuario::create(['nombre' => 'Jefe', 'apellido' => 'Concurrente', 'nombreusuario' => 'concurrente',
                'email' => 'concurrente@edt42.test', 'passwordhash' => bcrypt('prueba123'), 'activo' => true, 'role' => 'jefe_agricultor']);
            $usuario->syncRoles(['jefe_agricultor']);
            $unidad = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
            $almacen = Almacen::create(['nombre' => 'Almacén concurrente', 'ubicacion' => 'Prueba', 'ambito' => 'agricola',
                'responsable_usuarioid' => $usuario->usuarioid, 'capacidad' => 1000, 'activo' => true,
                'unidadmedidaid' => $unidad->unidadmedidaid, 'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Agrícola'])->tipoalmacenid]);
            $insumo = Insumo::create(['nombre' => 'Materia concurrente', 'stock' => '10', 'almacenid' => $almacen->almacenid,
                'unidadmedidaid' => $unidad->unidadmedidaid, 'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Fertilizantes'])->tipoinsumoid]);
            $consumo = TipoMovimientoAlmacen::firstOrCreate(['nombre' => 'Consumo interno', 'naturaleza' => 'salida'], ['activo' => true]);
            $ajuste = TipoMovimientoAlmacen::firstOrCreate(['nombre' => 'Ajuste negativo', 'naturaleza' => 'salida'], ['activo' => true]);
            foreach ([[$consumo, $consumo], [$ajuste, $consumo]] as $tipos) {
                $insumo->refresh()->update(['stock' => '10']);
                $anteriores = AlmacenMovimiento::count();
                $procesos = [];
                foreach ($tipos as $indice => $tipo) {
                    $datos = ['almacenid' => $almacen->almacenid, 'insumoid' => $insumo->insumoid,
                        'tipo_movimiento_almacenid' => $tipo->tipo_movimiento_almacenid, 'fecha' => now()->toDateString(),
                        'cantidad' => '7.000000', 'destino_motivo' => 'Competencia real entre procesos'];
                    $proceso = new Process([PHP_BINARY, '-d', 'max_execution_time=0', base_path('tests/Fixtures/inventario_concurrent_worker.php'),
                        $archivo, (string) $usuario->usuarioid, $barrera, json_encode($datos), (string) $indice, now()->toDateTimeString()], base_path());
                    $proceso->setTimeout(120)->start();
                    $procesos[] = $proceso;
                }
                $limite = microtime(true) + 90;
                while (! is_file($barrera.'.ready.0') || ! is_file($barrera.'.ready.1')) {
                    if (microtime(true) > $limite) {
                        $this->fail('Los dos procesos no llegaron a la barrera: '.implode(' ', array_map(fn ($p) => $p->getOutput().$p->getErrorOutput(), $procesos)));
                    }
                    usleep(10000);
                }
                $this->assertNotSame($procesos[0]->getPid(), $procesos[1]->getPid());
                file_put_contents($barrera, 'start');
                $resultados = [];
                foreach ($procesos as $proceso) {
                    $proceso->wait();
                    $this->assertTrue($proceso->isSuccessful(), $proceso->getErrorOutput());
                    $resultados[] = $proceso->getOutput();
                }
                $this->assertCount(1, array_filter($resultados, fn ($r) => $r === 'CONFIRMADO'), json_encode($resultados));
                $this->assertCount(1, array_filter($resultados, fn ($r) => str_starts_with($r, 'RECHAZADO:')), json_encode($resultados));
                $this->assertEquals(3, $insumo->fresh()->stock);
                $this->assertSame($anteriores + 1, AlmacenMovimiento::count());
                foreach ([$barrera, $barrera.'.ready.0', $barrera.'.ready.1'] as $ruta) {
                    unlink($ruta);
                }
            }
        } finally {
            foreach ($procesos as $proceso) {
                if ($proceso->isRunning()) {
                    $proceso->stop();
                }
            }
            DB::disconnect('sqlite');
            foreach ([$archivo, $archivo.'-wal', $archivo.'-shm', $barrera, $barrera.'.ready.0', $barrera.'.ready.1'] as $ruta) {
                if (is_file($ruta)) {
                    unlink($ruta);
                }
            }
        }
    }
}
