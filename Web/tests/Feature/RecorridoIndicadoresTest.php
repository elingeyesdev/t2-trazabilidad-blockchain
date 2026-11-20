<?php

namespace Tests\Feature;

use App\Models\AlmacenajeLoteProduccion;
use App\Models\Insumo;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\MateriaPrimaLote;
use App\Services\CertificadoDocumentoService;
use App\Services\CertificadoEmisionService;
use App\Services\ProductoRecorridoConsultaService;
use App\Support\RecorridoFiltros;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\CertificadosFixture;
use Tests\Support\EnvioQrFixture;
use Tests\TestCase;

class RecorridoIndicadoresTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $this->f = CertificadosFixture::crear();
    }

    private function url(array $f = []): string
    {
        return '/api/consulta-recorrido?'.http_build_query($f);
    }

    private function salida(string $nombre, ?int $almacen = null): InventarioPresentacionLote
    {
        $almacen ??= $this->f['almacen']->getKey();
        $insumo = $this->f['lote']->materiasPrimas()->first()->insumo->replicate();
        $insumo->fill(['nombre' => $nombre, 'stock' => 0, 'almacenid' => $almacen])->save();
        $p = InsumoPresentacion::create(['insumoid' => $insumo->getKey(), 'nombre' => 'Bolsa 1 kg', 'tipo_envase' => 'bolsa', 'peso_neto_kg' => 1, 'activo' => true]);
        $partida = InventarioPresentacionLote::create(['almacenid' => $almacen, 'insumoid' => $insumo->getKey(),
            'insumo_presentacionid' => $p->getKey(), 'loteproduccionpedidoid' => $this->f['lote']->getKey(),
            'cantidad_unidades' => '2.123456', 'cantidad_kg' => '2.123456']);
        AlmacenajeLoteProduccion::create(['loteproduccionpedidoid' => $this->f['lote']->getKey(), 'almacenid' => $almacen,
            'ubicacion' => 'Destino', 'condicion' => \App\Support\AlmacenajeLoteCondiciones::opciones()[0],
            'cantidad' => '2.123456', 'fecha_almacenaje' => '2026-11-20 23:59:59']);

        return $partida;
    }

    public function test_recorrido_multiples_origenes_destinos_etapas_y_partidas_sin_mezclas(): void
    {
        $admin = CertificadosFixture::usuario('admin', 'admin55');
        $salida = $this->salida('Producto terminado A');
        $otroAlmacen = $this->f['almacen']->replicate();
        $otroAlmacen->nombre = 'Segundo destino';
        $otroAlmacen->save();
        $this->salida('Producto terminado B', $otroAlmacen->getKey());
        $otroLote = $this->f['lote']->replicate();
        $otroLote->codigo_lote = 'PARTIDA-DISTINTA';
        $otroLote->save();
        $ajena = $salida->replicate();
        $ajena->loteproduccionpedidoid = $otroLote->getKey();
        $ajena->cantidad_unidades = 99;
        $ajena->save();
        $this->actingAs($admin)->getJson($this->url(['tipo' => 'planta', 'partida' => $this->f['lote']->getKey()]))
            ->assertOk()->assertJsonCount(2, 'data.recorrido.antecedentes.origenes')
            ->assertJsonCount(2, 'data.recorrido.antecedentes.ubicaciones_actuales')
            ->assertJsonPath('data.recorrido.antecedentes.origenes.0.cantidad_consumida', '5.123000');
        $r = app(ProductoRecorridoConsultaService::class)->consultar('planta', $this->f['lote']->getKey(), $admin, []);
        $elementos = collect($r['elementos']);
        $this->assertCount(10, $elementos->where('tipo', 'actividad_agricola'));
        $this->assertCount(1, $elementos->where('tipo', 'etapa_planta'));
        $this->assertCount(2, $elementos->where('tipo', 'ingreso_produccion'));
        $this->assertSame($this->f['registro']->getKey(), $elementos->firstWhere('tipo', 'etapa_planta')['id']);
        $this->assertNotEmpty($elementos->firstWhere('tipo', 'etapa_planta')['datos']['parametros']);
        $this->assertSame('2.123456', $elementos->firstWhere('tipo', 'ubicacion_actual')['datos']['cantidad_actual']);
        $this->assertNotContains((int) $ajena->getKey(), $elementos->where('tipo', 'ubicacion_actual')->pluck('id')->all());
        foreach ($r['antecedentes']['origenes'] as $o) {
            $this->assertContains($o['origen_agricola']['loteid'], array_map(fn ($l) => $l->getKey(), $this->f['campos']));
            $this->assertNotNull($o['movimiento_consumo_id']);
        }
    }

    public function test_cosecha_concreta_no_agrega_otras_cosechas_del_lote(): void
    {
        $cosecha = $this->f['campos'][0]->producciones()->first();
        $otra = $cosecha->replicate();
        $otra->cantidad = 999;
        $otra->save();
        $this->actingAs($this->f['agricola'])->getJson($this->url(['tipo' => 'cosecha', 'partida' => $cosecha->getKey()]))
            ->assertOk()->assertJsonPath('data.recorrido.antecedentes.cosecha.cantidad', '100.123456')
            ->assertJsonPath('data.recorrido.antecedentes.cosecha.loteid', $this->f['campos'][0]->getKey())
            ->assertJsonPath('data.recorrido.entidad.id', $cosecha->getKey());
        $this->assertSame(1, collect($this->getJson($this->url(['tipo' => 'cosecha', 'partida' => $cosecha->getKey()]))->json('data.recorrido.elementos'))->where('tipo', 'cosecha')->count());
    }

    public function test_pendientes_por_usuario_estado_fecha_y_conteo_antes_de_paginar(): void
    {
        foreach (['pendiente', 'pendiente', 'programada', 'cancelada', 'completada'] as $estado) {
            $a = $this->f['asignacion']->replicate();
            $a->fill(['estado' => $estado, 'creado_en' => '2026-11-20 23:59:59', 'registroprocesomaquinaplantaid' => null, 'completada_en' => null])->save();
        }
        $otro = CertificadosFixture::usuario('planta', 'otro55');
        $a = $this->f['asignacion']->replicate();
        $a->fill(['operador_usuarioid' => $otro->getKey(), 'estado' => 'pendiente', 'creado_en' => '2026-11-20 12:00:00'])->save();
        $f = ['desde' => '2026-11-20', 'hasta' => '2026-11-20', 'per_page' => 1];
        $this->actingAs($this->f['operario'])->getJson($this->url($f))->assertOk()
            ->assertJsonPath('data.indicadores.tareas_pendientes', 2)->assertJsonPath('data.pendientes.total', 2)
            ->assertJsonCount(1, 'data.pendientes.data')->assertJsonPath('data.pendientes.data.0.estado', 'pendiente');
        $this->getJson($this->url([...$f, 'pendientes_page' => 2]))->assertOk()->assertJsonPath('data.indicadores.tareas_pendientes', 2)->assertJsonCount(1, 'data.pendientes.data');
        $this->getJson($this->url(['desde' => '2026-11-21', 'hasta' => '2026-11-21']))->assertOk()->assertJsonPath('data.indicadores.tareas_pendientes', 0);
    }

    public function test_actividad_sin_cierre_es_pendiente_y_almacen_no_se_inventa(): void
    {
        $a = $this->f['campos'][0]->actividades()->first();
        $a->update(['fechafin' => null, 'fecha_planificada' => '2026-11-20']);
        $otro = $this->f['campos'][1]->actividades()->first();
        $otro->update(['fechafin' => null, 'fecha_planificada' => '2026-11-21']);
        $this->actingAs($this->f['agricola'])->getJson($this->url(['desde' => '2026-11-20', 'hasta' => '2026-11-20']))->assertOk()
            ->assertJsonPath('data.indicadores.tareas_pendientes', 1)->assertJsonPath('data.pendientes.data.0.id', $a->getKey())
            ->assertJsonPath('data.pendientes.data.0.almacen_filtro_aplica', false);
        $ajeno = CertificadosFixture::usuario('jefe_agricultor', 'ajenoCampo55');
        $this->actingAs($ajeno)->getJson($this->url())->assertOk()->assertJsonPath('data.indicadores.tareas_pendientes', 0);
    }

    public function test_alertas_minimos_distintos_cero_null_igualdad_y_totales_paginas(): void
    {
        $modelo = $this->f['lote']->materiasPrimas()->first()->insumo;
        $otroAlmacen = $this->f['almacen']->replicate();
        $otroAlmacen->nombre = 'Otro mínimo';
        $otroAlmacen->save();
        // El resto del catálogo no participa en las alertas de este escenario.
        Insumo::query()->update(['stockminimo' => null]);
        foreach ([[0, 0], [5, 5], [5, null], [5, 4]] as $i => [$stock, $minimo]) {
            $insumo = $modelo->replicate();
            $insumo->fill(['nombre' => 'Mismo producto', 'stock' => $stock, 'stockminimo' => $minimo,
                'almacenid' => $i === 1 ? $otroAlmacen->getKey() : $this->f['almacen']->getKey()])->save();
        }
        $this->actingAs($this->f['planta'])->getJson($this->url(['per_page' => 1, 'desde' => '2020-01-01', 'hasta' => '2020-01-01']))
            ->assertOk()->assertJsonPath('data.indicadores.registros_producto_almacen_bajos', 2)
            ->assertJsonPath('data.existencias_bajas.total', 2)->assertJsonCount(1, 'data.existencias_bajas.data')
            ->assertJsonPath('data.existencias_bajas.data.0.minimo', '0.000000')->assertJsonPath('data.existencias_bajas.data.0.cantidad_disponible', '0.000000')
            ->assertSee('NO aplica', false);
        $this->getJson($this->url(['almacenid' => $otroAlmacen->getKey()]))->assertOk()->assertJsonPath('data.indicadores.registros_producto_almacen_bajos', 1)
            ->assertJsonPath('data.existencias_bajas.data.0.minimo', '5.000000');
        $this->getJson($this->url(['bajas_page' => 2, 'per_page' => 1]))->assertOk()->assertJsonPath('data.existencias_bajas.total', 2)->assertJsonPath('data.existencias_bajas.data.0.cantidad_disponible', '5.000000');
    }

    public function test_intervalos_invalidos_almacen_ajeno_y_entidad_ajena(): void
    {
        $this->getJson($this->url())->assertUnauthorized();
        $this->actingAs($this->f['planta']);
        foreach ([['desde' => '2026-02-30', 'hasta' => '2026-03-01'], ['desde' => '2026-11-20'],
            ['desde' => '2026-11-20', 'hasta' => '2026-11-19'], ['desde' => '2020-01-01', 'hasta' => '2026-11-20'],
            ['tipo' => 'planta'], ['per_page' => 100]] as $f) {
            $this->getJson($this->url($f))->assertUnprocessable();
        }
        $this->getJson($this->url(['almacenid' => 999999]))->assertNotFound();
        $ajeno = CertificadosFixture::usuario('jefe_planta', 'ajeno55');
        $this->actingAs($ajeno)->getJson($this->url(['tipo' => 'planta', 'partida' => $this->f['lote']->getKey()]))->assertNotFound();
        $ajeno->syncRoles([]);
        $this->getJson($this->url())->assertForbidden();
    }

    public function test_contexto_conservado_ausencias_fechas_y_zona_horaria(): void
    {
        $this->assertTrue(RecorridoFiltros::coincide('2026-11-21T03:59:59Z', null, ['desde' => '2026-11-20', 'hasta' => '2026-11-20']));
        $this->assertFalse(RecorridoFiltros::coincide('2026-11-21T04:00:00Z', null, ['desde' => '2026-11-20', 'hasta' => '2026-11-20']));
        $this->assertTrue(RecorridoFiltros::coincide('2026-11-20', null, ['desde' => '2026-11-20', 'hasta' => '2026-11-20']));
        $r = app(ProductoRecorridoConsultaService::class)->consultar('planta', $this->f['lote']->getKey(), $this->f['planta'], ['desde' => '2020-01-01', 'hasta' => '2020-01-01']);
        $this->assertCount(2, $r['antecedentes']['origenes']);
        $this->assertSame(0, $r['coincidencias']);
        $this->assertSame([], $r['antecedentes']['productos_obtenidos']);
        $this->assertFalse($r['elementos'][0]['coincide_filtros']);
        $vacio = $this->f['lote']->replicate();
        $vacio->codigo_lote = 'VACIO-55';
        $vacio->save();
        $admin = CertificadosFixture::usuario('admin', 'adminVacio55');
        $r = app(ProductoRecorridoConsultaService::class)->consultar('planta', $vacio->getKey(), $admin, []);
        $this->assertSame([], $r['elementos']);
        $this->assertSame([], $r['antecedentes']['origenes']);
    }

    public function test_no_filtra_relaciones_ajenas_por_nombres_ni_expone_identidades(): void
    {
        $m = $this->f['lote']->materiasPrimas()->first();
        $ajeno = CertificadosFixture::usuario('jefe_planta', 'secreto55');
        $a = $this->f['almacen']->replicate();
        $a->fill(['nombre' => 'Almacén secreto EDT55', 'responsable_usuarioid' => $ajeno->getKey()])->save();
        $m->insumo->update(['almacenid' => $a->getKey(), 'nombre' => 'Insumo secreto EDT55', 'stockminimo' => 1000]);
        $m->materiaPrimaLote->update(['almacenid' => $a->getKey()]);
        $this->actingAs($this->f['operario'])->getJson($this->url(['tipo' => 'planta', 'partida' => $this->f['lote']->getKey()]))
            ->assertOk()->assertJsonCount(1, 'data.recorrido.antecedentes.origenes')->assertDontSee('Insumo secreto EDT55')->assertDontSee('Almacén secreto EDT55');
        $this->getJson($this->url(['almacenid' => $a->getKey()]))->assertNotFound();
    }

    public function test_web_api_coinciden_y_repeticion_no_modifica_ninguna_tabla(): void
    {
        config(['blockchain.enabled' => false]);
        \Illuminate\Support\Facades\Storage::fake('local');
        $this->mock(CertificadoDocumentoService::class, fn ($mock) => $mock->shouldReceive('generar')->andReturn('%PDF-1.4 antecedente EDT55'));
        $emision = app(CertificadoEmisionService::class)->emitirPlanta($this->f['planta'], $this->f['lote'], ['razon' => 'Certificado']);
        $pendiente = $this->f['asignacion']->replicate();
        $pendiente->fill(['estado' => 'pendiente', 'registroprocesomaquinaplantaid' => null, 'completada_en' => null])->save();
        $bajo = $this->f['lote']->materiasPrimas()->first()->insumo->replicate();
        $bajo->fill(['nombre' => 'Insumo bajo para consulta', 'stock' => 0, 'stockminimo' => 0])->save();
        $antes = $this->contenidoBase();
        $this->actingAs($this->f['planta']);
        $f = ['tipo' => 'planta', 'partida' => $this->f['lote']->getKey()];
        $api = $this->getJson($this->url($f))->assertOk()->json('data');
        $this->assertSame(1, $api['indicadores']['tareas_pendientes']);
        $this->assertSame(1, $api['indicadores']['registros_producto_almacen_bajos']);
        $web = $this->get(route('consulta-recorrido', $f))->assertOk()->assertSee('Recorrido e indicadores')
            ->assertViewHas('indicadores', $api['indicadores'])->assertViewHas('recorrido', $api['recorrido']);
        $this->assertSame((int) $emision->getKey(), $api['recorrido']['emisiones_historicas'][0]['id']);
        if (getenv('EDT55_CAPTURAR')) {
            \Illuminate\Support\Facades\File::ensureDirectoryExists(storage_path('app/private'));
            file_put_contents(storage_path('app/private/edt55-recorrido.html'), $web->getContent());
        }
        $this->getJson($this->url($f))->assertOk();
        $this->assertSame($antes, $this->contenidoBase());
    }

    public function test_disponible_descuenta_vencidas_y_bloqueadas_sin_agregar_saldos_heterogeneos(): void
    {
        Insumo::query()->update(['stockminimo' => null]);
        $i = $this->f['lote']->materiasPrimas()->first()->insumo->replicate();
        $i->fill(['nombre' => 'Existencia con vencimientos', 'stock' => '10.000000', 'stockminimo' => '5.000000'])->save();
        foreach ([['4.000000', '2020-01-01', true], ['2.000000', null, false]] as [$cantidad, $fecha, $conforme]) {
            MateriaPrimaLote::create(['insumoid' => $i->getKey(), 'almacenid' => $i->almacenid,
                'cantidad' => $cantidad, 'cantidad_disponible' => $cantidad, 'fecha_vencimiento' => $fecha,
                'fecha_recepcion' => '2020-01-01', 'conformidad_recepcion' => $conforme]);
        }
        $this->actingAs($this->f['planta'])->getJson($this->url())->assertOk()
            ->assertJsonPath('data.indicadores.registros_producto_almacen_bajos', 1)
            ->assertJsonPath('data.existencias_bajas.data.0.cantidad_fisica', '10.000000')
            ->assertJsonPath('data.existencias_bajas.data.0.cantidad_disponible', '4.000000')
            ->assertJsonPath('data.existencias_bajas.data.0.cantidad_vencida', '4.000000')
            ->assertJsonPath('data.existencias_bajas.data.0.cantidad_bloqueada', '2.000000');
    }

    public function test_envios_y_recepciones_conservan_linea_partida_y_cantidad_sin_duplicarlas(): void
    {
        \Illuminate\Support\Facades\Storage::fake('local');
        $admin = CertificadosFixture::usuario('admin', 'adminEnvio55');
        foreach (['traslado', 'distribucion'] as $tipo) {
            $f = EnvioQrFixture::crear($tipo);
            $f['partida']->update(['loteproduccionpedidoid' => $this->f['lote']->getKey()]);
            if ($tipo === 'traslado') {
                $f['detalle']->update(['loteproduccionpedidoid' => $this->f['lote']->getKey()]);
            }
            $antes = app(ProductoRecorridoConsultaService::class)->consultar('planta', $this->f['lote']->getKey(), $admin, []);
            $this->assertCount(0, collect($antes['elementos'])->where('tipo', 'recepcion_'.$tipo));
            $cantidad = $tipo === 'traslado' ? '5.000000' : '5.123456';
            app(\App\Services\EnvioRecepcionQrService::class)->confirmar($f['qr'], $f['receptor'],
                [['id' => $f['detalle']->getKey(), 'cantidad_recibida' => $tipo === 'traslado' ? '5.0000' : $cantidad]], EnvioQrFixture::firma());
            $r = app(ProductoRecorridoConsultaService::class)->consultar('planta', $this->f['lote']->getKey(), $admin, []);
            $recepciones = collect($r['elementos'])->where('tipo', 'recepcion_'.$tipo);
            $this->assertCount(1, $recepciones);
            $this->assertSame((int) $f['detalle']->getKey(), $recepciones->first()['id']);
            $this->assertSame($cantidad, $recepciones->first()['datos']['cantidad_recibida']);
            $this->assertSame((int) $f['qr']->getKey(), $recepciones->first()['datos']['recepcion_id']);
            $this->assertNotEmpty($recepciones->first()['datos']['comprobante_url']);
        }
    }

    private function contenidoBase(): array
    {
        $tablas = array_column(DB::select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"), 'name');
        $datos = [];
        foreach ($tablas as $tabla) {
            // Authentication/session mechanics are not operational traceability writes.
            if (! in_array($tabla, ['sessions', 'cache', 'cache_locks'], true)) {
                $datos[$tabla] = DB::table($tabla)->get()->map(fn ($r) => (array) $r)->all();
            }
        }

        return $datos;
    }
}
