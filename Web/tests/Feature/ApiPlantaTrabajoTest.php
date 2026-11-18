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
use App\Models\TipoInsumo;
use App\Models\TipoMovimientoAlmacen;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Models\VariableEstandar;
use App\Support\AsignacionEtapaPlantaService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class ApiPlantaTrabajoTest extends TestCase
{
    use RefreshDatabase;

    private Usuario $jefe;

    private Usuario $op;

    private Almacen $almacen;

    private UnidadMedida $kg;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        $this->jefe = $this->usuario('jefe_planta', 'jefe');
        $this->op = $this->usuario('planta', 'operario');
        $this->op->update(['supervisor_usuarioid' => $this->jefe->getKey()]);
        $this->kg = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
        $this->almacen = Almacen::create(['nombre' => 'Destino EDT43', 'ubicacion' => 'Prueba', 'ambito' => 'planta', 'activo' => true,
            'responsable_usuarioid' => $this->jefe->getKey(), 'capacidad' => 10000, 'unidadmedidaid' => $this->kg->getKey(),
            'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Planta'])->getKey()]);
        TipoMovimientoAlmacen::firstOrCreate(['nombre' => 'Producción recibida', 'naturaleza' => 'ingreso'], ['activo' => true]);
    }

    private function usuario(string $rol, string $sufijo): Usuario
    {
        $u = Usuario::create(['nombre' => 'Prueba', 'apellido' => $sufijo, 'email' => $sufijo.'@edt43.test',
            'nombreusuario' => $sufijo, 'passwordhash' => bcrypt('prueba123'), 'activo' => true, 'role' => $rol]);
        $u->syncRoles([$rol]);

        return $u;
    }

    private function pedido(): array
    {
        $p = Pedido::create(['numero_solicitud' => 'PED-'.uniqid(), 'nombre_planta' => $this->almacen->nombre,
            'direccion_texto' => $this->almacen->nombre.' · GPS', 'estado' => 'en_transito', 'latitud' => -17.7, 'longitud' => -63.1]);
        $d = DetallePedido::create(['pedidoid' => $p->getKey(), 'cultivo_personalizado' => 'Tomate EDT43', 'cantidad' => '100']);
        $e = EnvioAsignacionMultiple::create(['pedidoid' => $p->getKey(), 'externo_envio_id' => 'ENV-'.uniqid(), 'estado' => 'en_transporte_planta', 'fecha_asignacion' => now()]);

        return [$p, $d, $e];
    }

    private function tarea(int $pasos = 1): array
    {
        $p = Pedido::create(['numero_solicitud' => 'PROD-'.uniqid(), 'nombre_planta' => $this->almacen->nombre,
            'estado' => 'en produccion', 'latitud' => -17.7, 'longitud' => -63.1]);
        $l = LoteProduccionPedido::create(['pedidoid' => $p->getKey(), 'codigo_lote' => 'LP-'.uniqid(), 'nombre' => 'Lote API', 'producto' => 'Tomate', 'fecha_creacion' => now()]);
        $tareas = [];
        foreach (array_slice([['Preparación de Materias Primas', 'L-100'], ['Mezclado', 'MX-200']], 0, $pasos) as $i => [$nombre, $codigo]) {
            $proceso = ProcesoPlanta::firstOrCreate(['nombre' => $nombre], ['activo' => true]);
            $maq = MaquinaPlanta::firstOrCreate(['codigo' => $codigo], ['nombre' => $codigo, 'activo' => true]);
            $paso = LoteProduccionRutaPaso::create(['loteproduccionpedidoid' => $l->getKey(), 'orden' => $i + 1,
                'procesoplantaid' => $proceso->getKey(), 'maquinaplantaid' => $maq->getKey()]);
            $tareas[] = AsignacionEtapaPlanta::create(['loteproduccionpedidoid' => $l->getKey(), 'loteproduccionrutapasoid' => $paso->getKey(),
                'orden' => $i + 1, 'procesoplantaid' => $proceso->getKey(), 'maquinaplantaid' => $maq->getKey(), 'operador_usuarioid' => $this->op->getKey(),
                'asignado_por_usuarioid' => $this->jefe->getKey(), 'estado' => $i ? 'programada' : 'pendiente', 'creado_en' => now()]);
        }

        return [$l, $tareas];
    }

    private function completarUrl($l, $t): string
    {
        return '/api/planta/lotes-produccion/'.$l->getKey().'/tareas/'.$t->getKey().'/completar';
    }

    private function recibirUrl($p): string
    {
        return '/api/planta/recepciones/'.$p->getKey().'/confirmar';
    }

    public function test_autenticacion_json_incluso_sin_accept(): void
    {
        $this->get('/api/planta/tareas')->assertUnauthorized()->assertJsonStructure(['message']);
        $this->post('/api/planta/recepciones/1/confirmar')->assertUnauthorized()->assertJsonStructure(['message']);
    }

    public function test_token_lista_solo_tareas_propias_paginadas_y_protege_detalle(): void
    {
        [$l, [$t]] = $this->tarea();
        [, [$ajena]] = $this->tarea();
        $otro = $this->usuario('planta', 'otro');
        $ajena->update(['operador_usuarioid' => $otro->getKey()]);
        $token = $this->op->createToken('edt43')->plainTextToken;
        $this->withToken($token)->getJson('/api/planta/tareas?per_page=1')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.asignacionetapaplantaid', $t->getKey())->assertJsonPath('meta.total', 1);
        $this->getJson('/api/planta/tareas/'.$ajena->getKey())->assertNotFound();
        $this->getJson('/api/planta/tareas?usuarioid='.$otro->getKey())->assertUnprocessable()->assertJsonValidationErrors('usuarioid');
        $this->getJson('/api/planta/tareas/'.$t->getKey())->assertOk()->assertJsonPath('meta.puede_completar', true)->assertJsonPath('meta.permite_parciales', false);
    }

    public function test_sin_permiso_y_jefe_no_ejecuta_etapas(): void
    {
        [$l, [$t]] = $this->tarea();
        $this->actingAs($this->jefe)->postJson($this->completarUrl($l, $t), ['parametros' => []])->assertForbidden();
        $this->op->syncRoles([]);
        $this->actingAs($this->op)->getJson('/api/planta/tareas')->assertForbidden();
        $this->assertDatabaseCount('registro_proceso_maquina_planta', 0);
    }

    public function test_relacion_anidada_y_tarea_ajena_no_modifican(): void
    {
        [$l, [$t]] = $this->tarea();
        [$otro] = $this->tarea();
        $this->actingAs($this->op)->postJson($this->completarUrl($otro, $t), ['parametros' => []])->assertNotFound();
        $t->update(['operador_usuarioid' => $this->jefe->getKey()]);
        $this->postJson($this->completarUrl($l, $t), ['parametros' => []])->assertNotFound();
        $this->assertDatabaseCount('registro_proceso_maquina_planta', 0);
    }

    public function test_cierre_unico_reintento_conflicto_y_promocion_en_orden(): void
    {
        [$l, [$t, $siguiente]] = $this->tarea(2);
        $v = VariableEstandar::create(['codigo' => 'PESO-API', 'nombre' => 'Cantidad procesada', 'unidad' => 'kg', 'activo' => true]);
        LoteProduccionRutaPasoVariable::create(['loteproduccionrutapasoid' => $t->loteproduccionrutapasoid,
            'variableestandarid' => $v->getKey(), 'valor_minimo' => 1, 'valor_maximo' => 100, 'obligatorio' => true]);
        $body = ['parametros' => [['variableestandarid' => $v->getKey(), 'valor' => '95.123456']]];
        $this->actingAs($this->op)->postJson($this->completarUrl($l, $siguiente), ['parametros' => []])->assertUnprocessable();
        $this->postJson($this->completarUrl($l, $t), ['parametros' => []])->assertUnprocessable();
        $r = $this->postJson($this->completarUrl($l, $t), $body)->assertOk()->assertJsonPath('data.estado', 'completada');
        $id = $r->json('data.resultado.registroprocesomaquinaplantaid');
        $this->postJson($this->completarUrl($l, $t), $body)->assertOk()->assertJsonPath('data.resultado.registroprocesomaquinaplantaid', $id);
        $body['parametros'][0]['valor'] = '94';
        $this->postJson($this->completarUrl($l, $t), $body)->assertConflict();
        $this->assertDatabaseCount('registro_proceso_maquina_planta', 1);
        $this->assertSame('pendiente', $siguiente->fresh()->estado);
        $reg = RegistroProcesoMaquinaPlanta::findOrFail($id);
        $this->assertEquals($this->op->getKey(), $reg->usuarioid);
        $this->assertSame('95.123456', json_decode($reg->variables_ingresadas, true)['parametros'][0]['valor_decimal']);
        $this->get(route('tareas-planta.show', $t))->assertOk()->assertSee('Cantidad procesada');
        $this->get(route('procesamiento.show', $l))->assertOk()->assertSee('95.123456');
    }

    public function test_maquina_mantenimiento_incompatible_y_ruta_manipulada(): void
    {
        [$l, [$t]] = $this->tarea();
        $this->actingAs($this->op);
        $t->maquina->update(['activo' => false]);
        $this->postJson($this->completarUrl($l, $t), ['parametros' => []])->assertUnprocessable();
        $t->maquina->update(['activo' => true, 'codigo' => 'BD-500']);
        $this->postJson($this->completarUrl($l, $t), ['parametros' => []])->assertUnprocessable();
        $t->maquina->update(['codigo' => 'L-100']);
        $t->rutaPaso->update(['orden' => 2]);
        $this->postJson($this->completarUrl($l, $t), ['parametros' => []])->assertUnprocessable();
        $this->assertSame('pendiente', $t->fresh()->estado);
    }

    public function test_campos_protegidos_parametros_ajenos_repetidos_y_fuera_rango(): void
    {
        [$l, [$t]] = $this->tarea();
        $this->actingAs($this->op);
        $url = $this->completarUrl($l, $t);
        foreach (['usuarioid', 'maquinaplantaid', 'estado', 'hora_fin', 'cantidad_salida'] as $campo) {
            $this->postJson($url, ['parametros' => [], $campo => null])->assertUnprocessable()->assertJsonValidationErrors($campo);
        }
        $this->postJson($url, ['parametros' => [['variableestandarid' => 99999, 'valor' => 10]]])->assertUnprocessable()->assertJsonValidationErrors('parametros.0.variableestandarid');
        $v = VariableEstandar::create(['codigo' => 'V-API', 'nombre' => 'Medición', 'unidad' => 'kg', 'activo' => true]);
        LoteProduccionRutaPasoVariable::create(['loteproduccionrutapasoid' => $t->loteproduccionrutapasoid, 'variableestandarid' => $v->getKey(), 'valor_minimo' => 1, 'valor_maximo' => 10]);
        $fila = ['variableestandarid' => $v->getKey(), 'valor' => '10.000001'];
        $this->postJson($url, ['parametros' => [$fila]])->assertUnprocessable()->assertJsonValidationErrors('parametros.0.valor');
        $this->postJson($url, ['parametros' => [$fila, $fila]])->assertUnprocessable();
        $this->assertDatabaseCount('registro_proceso_maquina_planta', 0);
    }

    public function test_recepcion_pendiente_impide_etapa(): void
    {
        [$l, [$t]] = $this->tarea();
        EnvioAsignacionMultiple::create(['pedidoid' => $l->pedidoid, 'externo_envio_id' => 'SIN-PESAJE', 'estado' => 'en_transporte_planta']);
        $this->actingAs($this->op)->postJson($this->completarUrl($l, $t), ['parametros' => []])->assertUnprocessable();
        $this->assertDatabaseCount('registro_proceso_maquina_planta', 0);
    }

    public function test_fallo_resultado_revierte_estado_registro_y_promocion(): void
    {
        [$l, [$t, $siguiente]] = $this->tarea(2);
        AsignacionEtapaPlanta::updating(function ($a) {
            if ($a->estado === 'completada') {
                throw new \RuntimeException('Fallo aislado');
            }
        });
        try {
            app(AsignacionEtapaPlantaService::class)->completar($t, ['parametros' => []], $this->op);
            $this->fail('Debió fallar la escritura.');
        } catch (\RuntimeException $e) {
            $this->assertSame('Fallo aislado', $e->getMessage());
        } finally {
            AsignacionEtapaPlanta::flushEventListeners();
        }
        $this->assertDatabaseCount('registro_proceso_maquina_planta', 0);
        $this->assertSame('pendiente', $t->fresh()->estado);
        $this->assertSame('programada', $siguiente->fresh()->estado);
        $this->assertNull($l->fresh()->hora_inicio);
    }

    public function test_recepcion_exacta_trazabilidad_reintento_conflicto_y_web(): void
    {
        [$p, $d, $e] = $this->pedido();
        $body = ['cantidades' => [$d->getKey() => '95.123456']];
        $this->actingAs($this->jefe)->getJson('/api/planta/recepciones')->assertOk()->assertJsonPath('meta.total', 1);
        $r = $this->postJson($this->recibirUrl($p), $body)->assertOk();
        $this->assertSame('95.123456', $r->json('data.recepcion.0.cantidad_recibida'));
        $insumo = Insumo::findOrFail($r->json('data.recepcion.0.insumoid'));
        $this->assertEquals('95.123456', $insumo->stock);
        $this->assertDatabaseHas('materia_prima_lote', ['detallepedidoid' => $d->getKey(), 'fecha_vencimiento' => null]);
        $this->assertSame($this->jefe->getKey(), $e->fresh()->recepcion_usuarioid);
        $this->postJson($this->recibirUrl($p), $body)->assertOk();
        $this->assertDatabaseCount('almacen_movimiento', 1);
        $this->postJson($this->recibirUrl($p), ['cantidades' => [$d->getKey() => '94']])->assertConflict();
        $this->get(route('almacen-planta.existencias.index', $this->almacen))->assertOk()->assertSee('Tomate EDT43');
        $this->get(route('pedidos.show', $p))->assertOk()->assertSee('Recepción registrada en planta')->assertSee('Recibido en planta')->assertSee('95.123456');
    }

    public function test_recepcion_limites_lineas_manipuladas_precision_y_protegidos(): void
    {
        [$p, $d] = $this->pedido();
        $this->actingAs($this->jefe);
        $url = $this->recibirUrl($p);
        foreach (['0', '-1', '100.000001', '1.1234567', '1e2'] as $cantidad) {
            $this->postJson($url, ['cantidades' => [$d->getKey() => $cantidad]])->assertUnprocessable()->assertJsonValidationErrors('cantidades.'.$d->getKey());
        }
        $this->postJson($url, ['cantidades' => [99999 => '1']])->assertUnprocessable();
        $this->postJson($url, ['cantidades' => [$d->getKey() => '1'], 'estado' => null])->assertUnprocessable()->assertJsonValidationErrors('estado');
        $this->assertDatabaseCount('almacen_movimiento', 0);
        $this->assertDatabaseCount('materia_prima_lote', 0);
    }

    public function test_recepcion_otra_planta_y_operario_rechazados(): void
    {
        [$p, $d] = $this->pedido();
        $otro = $this->usuario('jefe_planta', 'jefeAjeno');
        $this->actingAs($otro)->getJson('/api/planta/recepciones')->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/planta/recepciones/'.$p->getKey())->assertNotFound();
        $this->postJson($this->recibirUrl($p), ['cantidades' => [$d->getKey() => 10]])->assertNotFound();
        $this->actingAs($this->op)->postJson($this->recibirUrl($p), ['cantidades' => [$d->getKey() => 10]])->assertForbidden();
        $this->assertDatabaseCount('almacen_movimiento', 0);
    }

    public function test_origen_vencido_bloqueado_fecha_conservada_y_sin_segundo_descuento(): void
    {
        [$p, $d] = $this->pedido();
        $origen = Insumo::create(['nombre' => 'Tomate origen', 'almacenid' => $this->almacen->getKey(), 'stock' => '5',
            'unidadmedidaid' => $this->kg->getKey(), 'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Materia prima'])->getKey()]);
        $d->update(['insumoid' => $origen->getKey()]);
        $partida = MateriaPrimaLote::create(['insumoid' => $origen->getKey(), 'almacenid' => $this->almacen->getKey(),
            'cantidad' => '105', 'cantidad_disponible' => '5', 'fecha_recepcion' => now()->subDays(10), 'fecha_vencimiento' => now()->subDay(), 'conformidad_recepcion' => true]);
        $tipo = TipoMovimientoAlmacen::create(['nombre' => 'Salida origen', 'naturaleza' => 'salida', 'activo' => true]);
        AlmacenMovimiento::create(['almacenid' => $this->almacen->getKey(), 'insumoid' => $origen->getKey(), 'usuarioid' => $this->jefe->getKey(),
            'tipo_movimiento_almacenid' => $tipo->getKey(), 'cantidad' => '100', 'fecha' => now(), 'referencia' => $p->numero_solicitud, 'materiaprimaloteid' => $partida->getKey()]);
        $this->actingAs($this->jefe)->postJson($this->recibirUrl($p), ['cantidades' => [$d->getKey() => 90]])->assertUnprocessable();
        $partida->update(['fecha_vencimiento' => now()->toDateString(), 'conformidad_recepcion' => false]);
        $this->postJson($this->recibirUrl($p), ['cantidades' => [$d->getKey() => 90]])->assertUnprocessable();
        $partida->update(['conformidad_recepcion' => true]);
        $r = $this->postJson($this->recibirUrl($p), ['cantidades' => [$d->getKey() => 90]])->assertOk();
        $nuevo = MateriaPrimaLote::findOrFail($r->json('data.recepcion.0.materiaprimaloteid'));
        $this->assertSame(now()->toDateString(), $nuevo->fecha_vencimiento->toDateString());
        $this->assertEquals(5, $origen->fresh()->stock);
        $this->assertEquals(5, $partida->fresh()->cantidad_disponible);
    }

    public function test_fallo_recepcion_revierte_todas_las_lineas_y_saldos(): void
    {
        [$p, $d, $e] = $this->pedido();
        $segunda = DetallePedido::create(['pedidoid' => $p->getKey(), 'cultivo_personalizado' => 'Segundo producto', 'cantidad' => 10]);
        $insumosAntes = Insumo::count();
        $contador = 0;
        AlmacenMovimiento::creating(function () use (&$contador) {
            if (++$contador === 2) {
                throw new \RuntimeException('Fallo segundo movimiento');
            }
        });
        try {
            app(\App\Services\RecepcionPlantaEnvioService::class)->confirmarDesdePedido($p, $this->jefe, [$d->getKey() => '90', $segunda->getKey() => '9']);
            $this->fail('Debió revertirse la recepción.');
        } catch (\RuntimeException $ex) {
            $this->assertSame('Fallo segundo movimiento', $ex->getMessage());
        } finally {
            AlmacenMovimiento::flushEventListeners();
        }
        $this->assertDatabaseCount('almacen_movimiento', 0);
        $this->assertDatabaseCount('materia_prima_lote', 0);
        $this->assertDatabaseCount('insumo', $insumosAntes);
        $this->assertNull($e->fresh()->fecha_recepcion_planta);
    }

    public function test_varios_lotes_agricolas_conservan_cantidades_atribuidas_sin_duplicar_origen(): void
    {
        [$p, $d] = $this->pedido();
        $lotes = [];
        foreach ([$d, DetallePedido::create(['pedidoid' => $p->getKey(), 'cultivo_personalizado' => 'Tomate EDT43', 'cantidad' => 10])] as $i => $detalle) {
            $lote = \App\Models\Lote::create(['usuarioid' => $this->jefe->getKey(), 'nombre' => 'Origen agrícola '.$i, 'superficie' => 1,
                'unidadsuperficieid' => \App\Support\LoteDefaults::unidadHectareaId(), 'cultivoid' => \App\Models\Cultivo::firstOrCreate(['nombre' => 'Tomate'])->getKey(),
                'estadolotetipoid' => \App\Support\LoteDefaults::estadoPlanificadoId()]);
            $produccion = \App\Models\Produccion::create(['loteid' => $lote->getKey(), 'cantidad' => '200', 'cantidad_base' => '200',
                'unidadmedidaid' => $this->kg->getKey(), 'fechacosecha' => now(),
                'destinoproduccionid' => \App\Models\DestinoProduccion::firstOrCreate(['nombre' => 'Almacenamiento'])->getKey()]);
            $almacenado = \App\Models\ProduccionAlmacenamiento::create(['produccionid' => $produccion->getKey(), 'almacenid' => $this->almacen->getKey(),
                'cantidad' => 5, 'unidadmedidaid' => $this->kg->getKey(), 'fechaentrada' => now()]);
            $detalle->update(['produccionalmacenamientoid' => $almacenado->getKey(), 'producto_ref' => 'cosecha:'.$almacenado->getKey()]);
            $lotes[] = [$lote, $almacenado, $detalle];
        }
        $body = ['cantidades' => [$lotes[0][2]->getKey() => '90.123456', $lotes[1][2]->getKey() => '9.000001']];
        $r = $this->actingAs($this->jefe)->postJson($this->recibirUrl($p), $body)->assertOk()->assertJsonCount(2, 'data.recepcion');
        foreach ($lotes as $i => [$lote, $almacenado]) {
            $this->assertSame($lote->getKey(), $r->json('data.recepcion.'.$i.'.origen.loteid'));
            $this->assertEquals(5, $almacenado->fresh()->cantidad);
        }
        $this->assertDatabaseCount('materia_prima_lote', 2);
        $this->assertDatabaseCount('almacen_movimiento', 2);
        $this->assertEquals('99.123457', Insumo::where('almacenid', $this->almacen->getKey())->where('nombre', 'Tomate EDT43')->firstOrFail()->stock);
    }

    public function test_web_confirma_y_api_devuelve_comprobante_con_fecha_responsable_y_reintento(): void
    {
        [$p, $d, $e] = $this->pedido();
        $body = ['cantidades' => [$d->getKey() => '99.000001']];
        $this->actingAs($this->jefe)->post(route('pedidos.confirmar-llegada-planta', $p), $body)->assertSessionHasNoErrors()->assertRedirect();
        $this->getJson('/api/planta/recepciones/'.$p->getKey())->assertOk()->assertJsonPath('data.recepcion.0.cantidad_recibida', '99.000001');
        $this->postJson($this->recibirUrl($p), $body)->assertOk();
        $this->assertDatabaseCount('almacen_movimiento', 1);
        $this->assertNotNull($e->fresh()->fecha_recepcion_planta);
        $this->assertSame($this->jefe->getKey(), $e->fresh()->recepcion_usuarioid);
    }

    public function test_web_registra_parametros_y_api_reutiliza_resultado_y_fechas_servidor(): void
    {
        [$l, [$t]] = $this->tarea();
        $v = VariableEstandar::create(['codigo' => 'WEB43', 'nombre' => 'Peso procesado', 'unidad' => 'kg', 'activo' => true]);
        LoteProduccionRutaPasoVariable::create(['loteproduccionrutapasoid' => $t->loteproduccionrutapasoid, 'variableestandarid' => $v->getKey(), 'valor_minimo' => 1, 'valor_maximo' => 100]);
        $body = ['parametros' => [['variableestandarid' => $v->getKey(), 'valor' => '99.123456']]];
        $this->actingAs($this->op)->get(route('tareas-planta.show', $t))->assertOk()->assertSee('name="parametros[0][valor]"', false);
        $this->post(route('tareas-planta.completar', $t), $body)->assertSessionHasNoErrors()->assertRedirect();
        $r = $this->postJson($this->completarUrl($l, $t), $body)->assertOk()->assertJsonPath('data.resultado.parametros.0.valor_decimal', '99.123456');
        $registro = RegistroProcesoMaquinaPlanta::findOrFail($r->json('data.resultado.registroprocesomaquinaplantaid'));
        $this->assertSame(now()->toDateString(), $registro->fecha_registro->toDateString());
        $this->assertSame($this->op->getKey(), $registro->usuarioid);
        $this->assertDatabaseCount('registro_proceso_maquina_planta', 1);
    }

    public function test_listados_paginados_no_hacen_consultas_por_cada_fila(): void
    {
        $this->tarea();
        $this->actingAs($this->op);
        DB::enableQueryLog();
        DB::flushQueryLog();
        $this->getJson('/api/planta/tareas')->assertOk();
        $una = count(DB::getQueryLog());
        for ($i = 0; $i < 4; $i++) {
            $this->tarea();
        }
        DB::flushQueryLog();
        $this->getJson('/api/planta/tareas')->assertOk()->assertJsonCount(5, 'data');
        $this->assertLessThanOrEqual($una + 2, count(DB::getQueryLog()));
        $this->pedido();
        $this->actingAs($this->jefe);
        DB::flushQueryLog();
        $this->getJson('/api/planta/recepciones')->assertOk();
        $una = count(DB::getQueryLog());
        for ($i = 0; $i < 4; $i++) {
            $this->pedido();
        }
        DB::flushQueryLog();
        $this->getJson('/api/planta/recepciones')->assertOk()->assertJsonCount(5, 'data');
        $this->assertLessThanOrEqual($una + 2, count(DB::getQueryLog()));
        DB::disableQueryLog();
    }
}
