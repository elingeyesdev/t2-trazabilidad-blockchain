<?php

namespace Tests\Feature;

use App\Models\Actividad;
use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\Cultivo;
use App\Models\Insumo;
use App\Models\Lote;
use App\Models\MateriaPrimaLote;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use App\Models\TipoAlmacen;
use App\Models\TipoInsumo;
use App\Models\TipoMovimientoAlmacen;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Services\InventarioExistenciaService;
use App\Services\InventarioMovimientoService;
use App\Support\EstadoLoteCatalogo;
use App\Support\InventarioDecimal;
use App\Support\LoteDefaults;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ExistenciasAlmacenTest extends TestCase
{
    use RefreshDatabase;

    private Usuario $jefe;

    private Usuario $otro;

    private Almacen $almacen;

    private Insumo $insumo;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->setDate(2026, 11, 18)->setTime(12, 0));
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $this->jefe = $this->usuario('jefe_agricultor', 'jefe');
        $this->otro = $this->usuario('jefe_agricultor', 'otro');
        $unidad = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
        $this->almacen = Almacen::create(['nombre' => 'Almacén de prueba', 'ubicacion' => 'Parcela', 'capacidad' => 100000,
            'unidadmedidaid' => $unidad->unidadmedidaid, 'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Agrícola'])->tipoalmacenid,
            'ambito' => 'agricola', 'activo' => true, 'responsable_usuarioid' => $this->jefe->usuarioid]);
        $this->insumo = Insumo::create(['nombre' => 'Fertilizante', 'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Fertilizantes'])->tipoinsumoid,
            'unidadmedidaid' => $unidad->unidadmedidaid, 'almacenid' => $this->almacen->almacenid, 'stock' => '10.000000', 'stockminimo' => null]);
        foreach (['Compra' => 'ingreso', 'Ajuste positivo' => 'ingreso', 'Ajuste negativo' => 'salida', 'Consumo interno' => 'salida', 'Merma' => 'salida'] as $nombre => $naturaleza) {
            TipoMovimientoAlmacen::firstOrCreate(['nombre' => $nombre, 'naturaleza' => $naturaleza], ['activo' => true]);
        }
        Sanctum::actingAs($this->jefe);
    }

    private function usuario(string $rol, string $nombre, ?int $supervisor = null): Usuario
    {
        $usuario = Usuario::create(['nombre' => $nombre, 'apellido' => 'Inventario', 'email' => $nombre.'@edt42.test',
            'nombreusuario' => $nombre, 'passwordhash' => bcrypt('prueba123'), 'role' => $rol, 'activo' => true,
            'supervisor_usuarioid' => $supervisor, 'fecharegistro' => now(), 'fechamodificacion' => now()]);
        $usuario->syncRoles([$rol]);

        return $usuario;
    }

    private function ruta(): string
    {
        return '/api/almacenes/'.$this->almacen->almacenid.'/existencias';
    }

    private function datos(string $nombre = 'Consumo interno', string $cantidad = '1.000000', array $extras = []): array
    {
        return array_replace(['almacenid' => $this->almacen->almacenid, 'insumoid' => $this->insumo->insumoid,
            'tipo_movimiento_almacenid' => TipoMovimientoAlmacen::where('nombre', $nombre)->value('tipo_movimiento_almacenid'),
            'fecha' => now()->toDateString(), 'cantidad' => $cantidad, 'destino_motivo' => 'Verificación de inventario'], $extras);
    }

    private function partida(string $cantidad, ?string $vencimiento, string $nombre = 'PARTIDA'): MateriaPrimaLote
    {
        return MateriaPrimaLote::create(['insumoid' => $this->insumo->insumoid, 'almacenid' => $this->almacen->almacenid,
            'lote_proveedor' => $nombre, 'fecha_recepcion' => '2026-11-01', 'fecha_vencimiento' => $vencimiento,
            'cantidad' => $cantidad, 'cantidad_disponible' => $cantidad, 'conformidad_recepcion' => true]);
    }

    public function test_minimos_por_almacen_limites_null_cero_y_reflejo_inmediato(): void
    {
        $url = $this->ruta().'/'.$this->insumo->insumoid.'/minimo';
        $this->getJson($this->ruta())->assertOk()->assertJsonPath('data.0.minimo', null)->assertJsonPath('data.0.existencias_bajas', false);
        foreach (['0' => false, '9.999999' => false, '10' => true, '10.000001' => true] as $minimo => $alerta) {
            $this->patchJson($url, ['stockminimo' => (string) $minimo])->assertOk()->assertJsonPath('existencias_bajas', $alerta);
            $this->getJson($this->ruta())->assertOk()->assertJsonPath('data.0.existencias_bajas', $alerta);
        }
        $this->patchJson($url, ['stockminimo' => null])->assertOk()->assertJsonPath('minimo', null);
        foreach (['-1', '1.0000001', '1,5', '1e2'] as $invalido) {
            $this->patchJson($url, ['stockminimo' => $invalido])->assertUnprocessable()->assertJsonValidationErrors('stockminimo');
        }
        $almacenB = $this->almacen->replicate();
        $almacenB->nombre = 'Almacén B';
        $almacenB->save();
        $productoB = $this->insumo->replicate();
        $productoB->almacenid = $almacenB->almacenid;
        $productoB->stockminimo = '20';
        $productoB->save();
        $this->getJson('/api/almacenes/'.$almacenB->almacenid.'/existencias')->assertOk()->assertJsonPath('data.0.minimo', '20.000000')->assertJsonPath('data.0.existencias_bajas', true);
        $this->getJson($this->ruta())->assertOk()->assertJsonPath('data.0.minimo', null)->assertJsonCount(1, 'data');
        $this->patchJson($url, ['stockminimo' => '0'])->assertOk();
        $this->insumo->update(['stock' => '0']);
        $this->getJson($this->ruta())->assertOk()->assertJsonPath('data.0.existencias_bajas', true);
    }

    public function test_fechas_granularidad_disponible_y_limites_de_dia(): void
    {
        $this->partida('2', '2026-11-17', 'VENCIDA');
        $this->partida('2', '2026-11-18', 'HOY');
        $this->partida('2', '2026-11-25', 'SIETE');
        $this->partida('1', '2026-11-26', 'OCHO');
        $this->partida('1', null, 'SIN FECHA');
        $r = $this->getJson($this->ruta())->assertOk()->assertJsonPath('data.0.cantidad_fisica', '10.000000')
            ->assertJsonPath('data.0.cantidad_disponible', '8.000000')->assertJsonPath('data.0.cantidad_vencida', '2.000000')
            ->assertJsonPath('data.0.cantidad_sin_partida', '2.000000')->assertJsonCount(5, 'data.0.partidas');
        $this->assertSame(['vencido', 'proximo_a_vencer', 'proximo_a_vencer', 'vigente', 'sin_fecha_registrada'], array_column($r->json('data.0.partidas'), 'vencimiento_estado'));
        $this->travelTo(now()->setTime(23, 59, 59));
        $this->assertSame('proximo_a_vencer', app(InventarioExistenciaService::class)->estadoFecha('2026-11-18'));
        $this->travel(1)->seconds();
        $this->assertSame('vencido', app(InventarioExistenciaService::class)->estadoFecha('2026-11-18'));
        $this->getJson($this->ruta().'?estado=vencido&per_page=1')->assertOk()->assertJsonPath('total', 1);
    }

    public function test_ajustes_variacion_auditoria_motivo_responsable_precision_y_rechazos(): void
    {
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Ajuste positivo', '0.123456'))->assertCreated()
            ->assertJsonPath('usuarioid', $this->jefe->usuarioid)->assertJsonPath('cantidad', 0.123456)->assertJsonPath('cantidad_decimal', '0.123456')
            ->assertJsonPath('saldo_anterior', '10.000000')->assertJsonPath('saldo_posterior', '10.123456');
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Ajuste negativo', '0.123456'))->assertCreated()->assertJsonPath('saldo_posterior', '10.000000');
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Ajuste negativo', '11'))->assertUnprocessable();
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Ajuste positivo', '1', ['destino_motivo' => ' ']))->assertUnprocessable()->assertJsonValidationErrors('destino_motivo');
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Ajuste positivo', '1', ['usuarioid' => $this->otro->usuarioid]))->assertUnprocessable();
        foreach (['0', '-1', '1,5', '1e2', '0.0000001'] as $cantidad) {
            $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Ajuste positivo', $cantidad))->assertUnprocessable();
        }
        $this->assertSame('10.000000', InventarioDecimal::texto(InventarioDecimal::unidades($this->insumo->fresh()->getRawOriginal('stock'))));
        $this->assertDatabaseCount('almacen_movimiento', 2);
        $this->getJson('/api/almacenes/'.$this->almacen->almacenid.'/movimientos?naturaleza=salida&per_page=1')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.usuario.usuarioid', $this->jefe->usuarioid)->assertJsonPath('data.0.unidad', 'kg')->assertJsonPath('meta.total', 1);
    }

    public function test_ingreso_partidas_consumo_exacto_insuficiente_y_merma_vencida(): void
    {
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Compra', '2', ['lote_proveedor' => 'Nueva', 'fecha_vencimiento' => '2026-11-17']))->assertCreated();
        $partida = MateriaPrimaLote::where('lote_proveedor', 'Nueva')->firstOrFail();
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno', '1', ['materiaprimaloteid' => $partida->materiaprimaloteid]))->assertUnprocessable()->assertJsonValidationErrors('materiaprimaloteid');
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno'))->assertUnprocessable()->assertJsonValidationErrors('materiaprimaloteid');
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Ajuste positivo', '1', ['materiaprimaloteid' => $partida->materiaprimaloteid]))->assertCreated();
        $this->assertSame('2026-11-17', $partida->fresh()->fecha_vencimiento->toDateString());
        $this->getJson($this->ruta())->assertOk()->assertJsonPath('data.0.cantidad_vencida', '3.000000')->assertJsonPath('data.0.cantidad_disponible', '10.000000');
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Merma', '3', ['materiaprimaloteid' => $partida->materiaprimaloteid]))->assertCreated()->assertJsonPath('saldo_posterior', '10.000000');
        $vigente = $this->partida('2', '2026-11-25');
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno', '2.000001', ['materiaprimaloteid' => $vigente->materiaprimaloteid]))->assertUnprocessable();
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno', '2', ['materiaprimaloteid' => $vigente->materiaprimaloteid]))->assertCreated();
        $this->assertSame('0.000000', $vigente->fresh()->cantidad_disponible);
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno', '8', ['materiaprimaloteid' => 0]))->assertCreated()->assertJsonPath('saldo_posterior', '0.000000');
    }

    public function test_permiso_consulta_configuracion_operaciones_y_ambito_anidado(): void
    {
        $b = $this->almacen->replicate();
        $b->nombre = 'Ajeno';
        $b->responsable_usuarioid = $this->otro->usuarioid;
        $b->save();
        $insumoB = $this->insumo->replicate();
        $insumoB->almacenid = $b->almacenid;
        $insumoB->save();
        $this->getJson('/api/almacenes/'.$b->almacenid.'/existencias')->assertNotFound();
        $this->patchJson($this->ruta().'/'.$insumoB->insumoid.'/minimo', ['stockminimo' => '1'])->assertNotFound();
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno', '1', ['insumoid' => $insumoB->insumoid]))->assertNotFound();
        $mov = app(InventarioMovimientoService::class)->registrar($this->jefe, $this->datos(), 'salida');
        $this->getJson('/api/almacenes/'.$b->almacenid.'/movimientos/'.$mov->almacen_movimientoid)->assertNotFound();
        $operario = $this->usuario('agricultor', 'operario', $this->jefe->usuarioid);
        Sanctum::actingAs($operario);
        $this->getJson($this->ruta())->assertOk();
        $this->patchJson($this->ruta().'/'.$this->insumo->insumoid.'/minimo', ['stockminimo' => '1'])->assertForbidden();
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Ajuste positivo'))->assertForbidden();
        Sanctum::actingAs($this->usuario('admin', 'admin'));
        $this->getJson($this->ruta())->assertOk();
        $this->postJson('/api/almacen-movimientos/salida', $this->datos())->assertForbidden();
        $this->app['auth']->forgetGuards();
        $this->get($this->ruta())->assertUnauthorized()->assertHeader('content-type', 'application/json');
    }

    public function test_fallo_en_movimiento_revierte_saldo_y_partida(): void
    {
        $partida = $this->partida('10', '2026-11-25');
        $dispatcher = clone AlmacenMovimiento::getEventDispatcher();
        AlmacenMovimiento::creating(fn () => throw new \RuntimeException('Fallo simulado'));
        try {
            app(InventarioMovimientoService::class)->registrar($this->jefe, $this->datos('Consumo interno', '4', ['materiaprimaloteid' => $partida->materiaprimaloteid]), 'salida');
            $this->fail('Debió revertir la operación.');
        } catch (\RuntimeException $e) {
            $this->assertSame('Fallo simulado', $e->getMessage());
        } finally {
            AlmacenMovimiento::setEventDispatcher($dispatcher);
        }
        $this->assertEquals(10, $this->insumo->fresh()->stock);
        $this->assertSame('10.000000', $partida->fresh()->cantidad_disponible);
        $this->assertDatabaseCount('almacen_movimiento', 0);
    }

    public function test_cierre_actividad_rechaza_vencida_y_reintento_no_duplica_consumos(): void
    {
        Storage::fake('local');
        Storage::fake('public');
        $operario = $this->usuario('agricultor', 'trabajador', $this->jefe->usuarioid);
        $lote = Lote::create(['usuarioid' => $this->jefe->usuarioid, 'nombre' => 'Lote actividad', 'superficie' => 1,
            'unidadsuperficieid' => LoteDefaults::unidadHectareaId(), 'cultivoid' => Cultivo::firstOrCreate(['nombre' => 'Papa'])->cultivoid,
            'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('en_crecimiento')]);
        $actividad = Actividad::create(['loteid' => $lote->loteid, 'usuarioid' => $operario->usuarioid, 'descripcion' => 'Fertilización',
            'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => 'Fertilización'])->tipoactividadid,
            'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->prioridadid, 'fechainicio' => now(), 'orden_secuencia' => 2]);
        Actividad::create(['loteid' => $lote->loteid, 'usuarioid' => $operario->usuarioid, 'descripcion' => 'Siembra previa',
            'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => 'Siembra'])->tipoactividadid,
            'prioridadid' => $actividad->prioridadid, 'fechainicio' => now()->subDays(2), 'fechafin' => now()->subDay(), 'orden_secuencia' => 1]);
        $vencida = $this->partida('5', '2026-11-17');
        $vigente = $this->partida('5', '2026-11-25', 'VIGENTE');
        $foto = UploadedFile::fake()->image('foto.png');
        $imagen = file_get_contents($foto->getRealPath());
        $datos = fn ($p) => ['resultado' => 'Aplicación realizada', 'evidencia_foto' => UploadedFile::fake()->createWithContent('foto.png', $imagen),
            'consumos' => [['insumoid' => $this->insumo->insumoid, 'almacenid' => $this->almacen->almacenid, 'cantidad' => '5.000', 'materiaprimaloteid' => $p->materiaprimaloteid]]];
        Sanctum::actingAs($operario);
        $this->post('/api/actividades/'.$actividad->actividadid.'/cerrar', $datos($vencida), ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('consumos.0.materiaprimaloteid');
        $this->assertNull($actividad->fresh()->fechafin);
        $this->post('/api/actividades/'.$actividad->actividadid.'/cerrar', $datos($vigente), ['Accept' => 'application/json'])->assertOk();
        $this->post('/api/actividades/'.$actividad->actividadid.'/cerrar', $datos($vigente), ['Accept' => 'application/json'])->assertOk();
        $this->assertEquals(5, $this->insumo->fresh()->stock);
        $this->assertDatabaseCount('almacen_movimiento', 1);
        $this->assertDatabaseHas('almacen_movimiento', ['materiaprimaloteid' => $vigente->materiaprimaloteid, 'usuarioid' => $operario->usuarioid]);
    }

    public function test_presentaciones_conservan_kg_envases_fecha_y_factor_historico(): void
    {
        $presentacion = \App\Models\InsumoPresentacion::create(['insumoid' => $this->insumo->insumoid, 'nombre' => 'Bolsa', 'tipo_envase' => 'bolsa', 'peso_neto_kg' => '0.5000', 'activo' => true]);
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Compra', '10', ['insumo_presentacionid' => $presentacion->insumo_presentacionid,
            'cantidad_unidades' => '20', 'fecha_vencimiento' => '2026-11-25', 'lote_proveedor' => 'ENV-1']))->assertCreated();
        $partida = \App\Models\InventarioPresentacionLote::where('referencia_lote', 'ENV-1')->firstOrFail();
        $presentacion->update(['peso_neto_kg' => '5']);
        app(\App\Services\InventarioPresentacionService::class)->descontar($partida, 2, 10);
        $this->assertSame('9.000000', $partida->fresh()->cantidad_kg);
        $this->assertSame('18.000000', $partida->fresh()->cantidad_unidades);
        $this->assertEquals(19, $this->insumo->fresh()->stock);
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Ajuste negativo', '1', ['partida' => 'p:'.$partida->inventario_presentacion_loteid]))->assertCreated();
        $this->assertSame('16.000000', $partida->fresh()->cantidad_unidades);
        $partida->update(['fecha_vencimiento' => '2026-11-17']);
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno', '1', ['inventario_presentacion_loteid' => $partida->inventario_presentacion_loteid]))->assertUnprocessable();
        $this->getJson($this->ruta())->assertOk()->assertJsonPath('data.0.cantidad_vencida', '8.000000')->assertJsonPath('data.0.cantidad_disponible', '10.000000');
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Ajuste positivo', '1', ['partida' => 'p:'.$partida->inventario_presentacion_loteid, 'cantidad_unidades' => '2']))->assertCreated();
        $this->assertSame('2026-11-17', $partida->fresh()->fecha_vencimiento->toDateString());
    }

    public function test_planta_consume_partida_identificada_y_revierte_en_la_misma_sin_cambiar_fecha(): void
    {
        $jefePlanta = $this->usuario('jefe_planta', 'planta');
        $this->almacen->update(['ambito' => 'planta', 'responsable_usuarioid' => $jefePlanta->usuarioid]);
        $vencida = $this->partida('5', '2026-11-17', 'VENCIDA-PLANTA');
        $vigente = $this->partida('5', '2026-11-25', 'VIGENTE-PLANTA');
        $servicio = app(\App\Services\LoteProduccionPlantaService::class);
        $linea = fn ($p) => [['insumoid' => $this->insumo->insumoid, 'cantidad' => '2.000', 'materiaprimaloteid' => $p->materiaprimaloteid]];
        try {
            $servicio->crear($jefePlanta, 'Papa procesada', null, 2, $this->insumo->unidadmedidaid, $linea($vencida));
            $this->fail('No debe consumir materia prima vencida.');
        } catch (ValidationException $e) {
            $this->assertArrayHasKey('materiaprimaloteid', $e->errors());
        }
        $this->assertDatabaseCount('lote_produccion_pedido', 0);
        $lote = $servicio->crear($jefePlanta, 'Papa procesada', null, 2, $this->insumo->unidadmedidaid, $linea($vigente));
        $this->assertSame('3.000000', $vigente->fresh()->cantidad_disponible);
        $this->assertDatabaseHas('lote_produccion_materia_prima', ['loteproduccionpedidoid' => $lote->loteproduccionpedidoid, 'materiaprimaloteid' => $vigente->materiaprimaloteid]);
        $this->travel(8)->days();
        $servicio->eliminar($jefePlanta, $lote);
        $this->assertSame('5.000000', $vigente->fresh()->cantidad_disponible);
        $this->assertSame('2026-11-25', $vigente->fresh()->fecha_vencimiento->toDateString());
        $this->assertSame('vencido', app(InventarioExistenciaService::class)->estadoFecha($vigente->fresh()->fecha_vencimiento->toDateString()));
    }

    public function test_web_formularios_preservan_entrada_y_conteo_final_requiere_motivo(): void
    {
        $this->actingAs($this->jefe, 'web')->get(route('almacen-agricola.existencias.index', $this->almacen))->assertOk()->assertSee('Sin configurar');
        $url = route('almacen-agricola.movimientos.store', ['naturaleza' => 'salida']);
        $this->from(route('almacen-agricola.existencias.index', $this->almacen))->post($url, $this->datos('Ajuste negativo', '20'))
            ->assertRedirect()->assertSessionHasErrors('cantidad')->assertSessionHasInput('cantidad', '20');
        $servicio = app(InventarioMovimientoService::class);
        try {
            $servicio->actualizarFicha($this->jefe, $this->insumo, ['stock' => '7'], null);
            $this->fail('Falta motivo.');
        } catch (ValidationException $e) {
            $this->assertArrayHasKey('motivo_ajuste', $e->errors());
        }
        $servicio->actualizarFicha($this->jefe, $this->insumo, ['stock' => '7'], 'Conteo físico verificado');
        $this->assertEquals(7, $this->insumo->fresh()->stock);
        $this->assertDatabaseHas('almacen_movimiento', ['cantidad' => '3', 'destino_motivo' => 'Conteo físico verificado', 'usuarioid' => $this->jefe->usuarioid]);
    }

    public function test_partida_ajena_bloqueada_y_parametros_invalidos_no_alteran_saldos(): void
    {
        $partida = $this->partida('2', '2026-11-25');
        $partida->update(['conformidad_recepcion' => false]);
        $this->getJson($this->ruta())->assertOk()->assertJsonPath('data.0.cantidad_bloqueada', '2.000000')->assertJsonPath('data.0.cantidad_disponible', '8.000000');
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno', '1', ['materiaprimaloteid' => $partida->materiaprimaloteid]))->assertUnprocessable();
        $this->postJson('/api/almacen-movimientos/salida', $this->datos('Consumo interno', '1', ['materiaprimaloteid' => 999999]))->assertUnprocessable();
        foreach (['per_page=101', 'page=0', 'estado=inventado'] as $consulta) {
            $this->getJson($this->ruta().'?'.$consulta)->assertUnprocessable();
        }
        $this->getJson('/api/almacenes/'.$this->almacen->almacenid.'/movimientos?desde=2026-11-20&hasta=2026-11-18')->assertUnprocessable();
        $this->postJson('/api/almacen-movimientos/ingreso', $this->datos('Ajuste positivo', '1', ['fecha_vencimiento' => '2028-01-01', 'materiaprimaloteid' => $partida->materiaprimaloteid]))->assertUnprocessable();
        $this->assertEquals(10, $this->insumo->fresh()->stock);
        $this->assertDatabaseCount('almacen_movimiento', 0);
    }

    public function test_migracion_reaplicable_preserva_cantidades_y_no_asigna_fechas_a_historicos(): void
    {
        $this->insumo->update(['stock' => '999999999999.999999', 'stockminimo' => null]);
        $partida = $this->partida('0.000001', null);
        $migracion = require database_path('migrations/2026_11_18_100000_vincular_partidas_existencias_almacen.php');
        $migracion->down();
        $migracion->up();
        $this->assertSame('999999999999.999999', $this->insumo->fresh()->getRawOriginal('stock'));
        $this->assertNull($this->insumo->fresh()->stockminimo);
        $this->assertNull($partida->fresh()->fecha_vencimiento);
        $this->assertSame('0.000001', $partida->fresh()->cantidad_disponible);
        $this->assertDatabaseCount('almacen_movimiento', 0);
    }

    public function test_stock_reservado_se_distingue_y_no_se_puede_retirar_ni_consumir_dos_veces(): void
    {
        $mayorista = $this->usuario('mayorista', 'mayorista');
        $minorista = $this->usuario('minorista', 'minorista');
        $this->almacen->update(['ambito' => 'mayorista', 'responsable_usuarioid' => $mayorista->usuarioid]);
        $punto = \App\Models\PuntoVenta::create(['nombre' => 'Punto reservado', 'usuarioid' => $minorista->usuarioid,
            'direccion' => 'Prueba', 'activo' => true]);
        $pedido = \App\Models\PedidoDistribucion::create(['numero_solicitud' => 'EDT42-RESERVA', 'puntoventaid' => $punto->puntoventaid,
            'almacen_mayorista_origenid' => $this->almacen->almacenid, 'estado' => \App\Support\PedidoDistribucionCatalogo::ESTADO_CONFIRMADO, 'fechapedido' => now()]);
        \App\Models\DetallePedidoDistribucion::create(['pedidodistribucionid' => $pedido->pedidodistribucionid, 'insumoid' => $this->insumo->insumoid,
            'almacen_mayorista_origenid' => $this->almacen->almacenid, 'producto_nombre' => $this->insumo->nombre, 'cantidad' => '7']);
        $resumen = app(InventarioExistenciaService::class)->resumen($this->insumo->fresh());
        $this->assertSame('7.000000', $resumen['cantidad_reservada']);
        $this->assertSame('3.000000', $resumen['cantidad_disponible']);
        foreach (['Consumo interno', 'Ajuste negativo'] as $tipo) {
            try {
                app(InventarioMovimientoService::class)->registrar($mayorista, $this->datos($tipo, '4'), 'salida');
                $this->fail('No puede utilizar stock reservado por otro pedido.');
            } catch (ValidationException $e) {
                $this->assertArrayHasKey('cantidad', $e->errors());
            }
        }
        $this->assertEquals(10, $this->insumo->fresh()->stock);
        $this->assertDatabaseCount('almacen_movimiento', 0);
        $this->insumo->decrementarStock('7', null, false, $pedido->pedidodistribucionid);
        $this->assertEquals(3, $this->insumo->fresh()->stock);
    }
}
