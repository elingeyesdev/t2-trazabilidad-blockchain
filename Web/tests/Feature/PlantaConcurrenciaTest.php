<?php

namespace Tests\Feature;

use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\AsignacionEtapaPlanta;
use App\Models\DetallePedido;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Insumo;
use App\Models\LoteProduccionPedido;
use App\Models\LoteProduccionRutaPaso;
use App\Models\LoteProduccionRutaPasoVariable;
use App\Models\MaquinaPlanta;
use App\Models\MateriaPrimaLote;
use App\Models\Pedido;
use App\Models\ProcesoPlanta;
use App\Models\RegistroProcesoMaquinaPlanta;
use App\Models\TipoAlmacen;
use App\Models\TipoMovimientoAlmacen;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Models\VariableEstandar;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Symfony\Component\Process\Process;
use Tests\TestCase;

class PlantaConcurrenciaTest extends TestCase
{
    public function test_procesos_independientes_no_duplican_recepcion_ni_transicion(): void
    {
        $archivo = tempnam(sys_get_temp_dir(), 'edt43db');
        $barrera = $archivo.'.gate';
        $procesos = [];
        try {
            config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => $archivo]);
            DB::purge('sqlite');
            DB::statement('PRAGMA busy_timeout = 10000');
            Artisan::call('migrate', ['--force' => true]);
            $this->seed(RolePermissionSeeder::class);
            $jefe = Usuario::create(['nombre' => 'Jefe', 'apellido' => 'Prueba', 'nombreusuario' => 'jefe', 'email' => 'jefe@edt43.test', 'passwordhash' => bcrypt('prueba123'), 'activo' => true, 'role' => 'jefe_planta']);
            $jefe->syncRoles(['jefe_planta']);
            $op = Usuario::create(['nombre' => 'Operario', 'apellido' => 'Prueba', 'nombreusuario' => 'operario', 'email' => 'op@edt43.test', 'passwordhash' => bcrypt('prueba123'), 'activo' => true, 'role' => 'planta', 'supervisor_usuarioid' => $jefe->getKey()]);
            $op->syncRoles(['planta']);
            $kg = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
            $almacen = Almacen::create(['nombre' => 'Planta concurrente EDT43', 'ubicacion' => 'Prueba', 'ambito' => 'planta', 'activo' => true, 'responsable_usuarioid' => $jefe->getKey(), 'capacidad' => 1000, 'unidadmedidaid' => $kg->getKey(), 'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Planta'])->getKey()]);
            TipoMovimientoAlmacen::firstOrCreate(['nombre' => 'Producción recibida', 'naturaleza' => 'ingreso'], ['activo' => true]);
            $pedido = Pedido::create(['numero_solicitud' => 'CONC43', 'nombre_planta' => $almacen->nombre, 'direccion_texto' => $almacen->nombre.' · GPS', 'estado' => 'en_transito', 'latitud' => -17.7, 'longitud' => -63.1]);
            $detalle = DetallePedido::create(['pedidoid' => $pedido->getKey(), 'cultivo_personalizado' => 'Tomate concurrente', 'cantidad' => 100]);
            $envio = EnvioAsignacionMultiple::create(['pedidoid' => $pedido->getKey(), 'externo_envio_id' => 'ENV43-CONC', 'estado' => 'en_transporte_planta']);
            $lote = LoteProduccionPedido::create(['pedidoid' => $pedido->getKey(), 'codigo_lote' => 'LP43-CONC', 'nombre' => 'Lote concurrente', 'producto' => 'Tomate', 'fecha_creacion' => now()]);
            $proceso = ProcesoPlanta::create(['nombre' => 'Preparación de Materias Primas', 'activo' => true]);
            $maquina = MaquinaPlanta::create(['nombre' => 'Lavadora', 'codigo' => 'L-100', 'activo' => true]);
            $paso = LoteProduccionRutaPaso::create(['loteproduccionpedidoid' => $lote->getKey(), 'orden' => 1, 'procesoplantaid' => $proceso->getKey(), 'maquinaplantaid' => $maquina->getKey()]);
            $variable = VariableEstandar::create(['codigo' => 'KG43', 'nombre' => 'Cantidad medida', 'unidad' => 'kg', 'activo' => true]);
            LoteProduccionRutaPasoVariable::create(['loteproduccionrutapasoid' => $paso->getKey(), 'variableestandarid' => $variable->getKey(), 'valor_minimo' => 1, 'valor_maximo' => 100]);
            $tarea = AsignacionEtapaPlanta::create(['loteproduccionpedidoid' => $lote->getKey(), 'loteproduccionrutapasoid' => $paso->getKey(), 'orden' => 1, 'procesoplantaid' => $proceso->getKey(), 'maquinaplantaid' => $maquina->getKey(), 'operador_usuarioid' => $op->getKey(), 'asignado_por_usuarioid' => $jefe->getKey(), 'estado' => 'pendiente', 'creado_en' => now()]);
            foreach (['recepcion', 'etapa'] as $modo) {
                $procesos = [];
                foreach ([95, 94] as $indice => $valor) {
                    $datos = $modo === 'recepcion' ? [$detalle->getKey() => (string) $valor] : ['parametros' => [['variableestandarid' => $variable->getKey(), 'valor' => (string) $valor]]];
                    $p = new Process([PHP_BINARY, '-d', 'max_execution_time=0', base_path('tests/Fixtures/planta_concurrent_worker.php'), $archivo,
                        (string) ($modo === 'recepcion' ? $jefe->getKey() : $op->getKey()), $barrera, json_encode($datos), (string) $indice, $modo,
                        (string) ($modo === 'recepcion' ? $pedido->getKey() : $tarea->getKey()), now()->toDateTimeString()], base_path());
                    $p->setTimeout(120)->start();
                    $procesos[] = $p;
                }
                $limite = microtime(true) + 90;
                while (! is_file($barrera.'.ready.0') || ! is_file($barrera.'.ready.1')) {
                    if (microtime(true) > $limite) {
                        $this->fail('Los procesos no llegaron a la barrera: '.implode(' ', array_map(fn ($p) => $p->getErrorOutput(), $procesos)));
                    }
                    usleep(10000);
                }
                $this->assertNotSame($procesos[0]->getPid(), $procesos[1]->getPid());
                file_put_contents($barrera, 'start');
                $resultados = [];
                foreach ($procesos as $p) {
                    $p->wait();
                    $this->assertTrue($p->isSuccessful(), $p->getErrorOutput());
                    $resultados[] = $p->getOutput();
                }
                sort($resultados);
                $this->assertSame(['CONFIRMADO', 'CONFLICTO'], $resultados);
                foreach ([$barrera, $barrera.'.ready.0', $barrera.'.ready.1'] as $ruta) {
                    unlink($ruta);
                }
                if ($modo === 'recepcion') {
                    $this->assertSame(1, AlmacenMovimiento::count());
                    $this->assertSame(1, MateriaPrimaLote::count());
                    $recibida = $envio->fresh()->recepcion_planta_datos['lineas'][0]['cantidad_recibida'];
                    $this->assertContains($recibida, ['94.000000', '95.000000']);
                    $this->assertEquals($recibida, Insumo::where('nombre', 'Tomate concurrente')->firstOrFail()->stock);
                } else {
                    $this->assertSame(1, RegistroProcesoMaquinaPlanta::count());
                    $this->assertSame('completada', $tarea->fresh()->estado);
                }
            }
            if (getenv('EDT43_BROWSER_FIXTURE') === '1') {
                $jefe->update(['estado_cuenta' => 'aprobado', 'bienvenida_vista' => true]);
                $op->update(['estado_cuenta' => 'aprobado', 'bienvenida_vista' => true]);
                DB::disconnect('sqlite');
                copy($archivo, storage_path('app/private/edt43-navegador.sqlite'));
                file_put_contents(storage_path('app/private/edt43-navegador.json'), json_encode([
                    'pedidoid' => $pedido->getKey(), 'almacenid' => $almacen->getKey(), 'tareaid' => $tarea->getKey(),
                    'loteid' => $lote->getKey(), 'jefe_email' => $jefe->email, 'op_email' => $op->email,
                ]));
            }
        } finally {
            foreach ($procesos as $p) {
                if ($p->isRunning()) {
                    $p->stop();
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
