<?php

namespace Tests\Feature;

use App\Models\AlmacenajeLoteProduccion;
use App\Models\EvaluacionFinalLoteProduccion;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\LoteProduccionPedido;
use App\Services\CertificadoDocumentoService;
use App\Services\CertificadoEmisionService;
use App\Services\LoteProduccionPlantaService;
use App\Services\ProduccionPlantaRecorridoService;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\Support\CertificadosFixture;
use Tests\TestCase;

class ProduccionPlantaRecorridoTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $this->f = CertificadosFixture::crear();
    }

    private function datos(): array
    {
        return app(ProduccionPlantaRecorridoService::class)->consultar($this->f['lote']->fresh(), $this->f['planta']);
    }

    private function url(?LoteProduccionPedido $lote = null): string
    {
        return '/api/planta/lotes-produccion/'.($lote ?? $this->f['lote'])->getKey();
    }

    private function salida(string $cantidad = '12.123456', ?int $almacenId = null, string $producto = 'Tomate terminado'): array
    {
        $almacenId ??= $this->f['almacen']->getKey();
        $insumo = $this->f['lote']->materiasPrimas()->first()->insumo->replicate();
        $insumo->fill(['nombre' => $producto, 'almacenid' => $almacenId, 'stock' => 0])->save();
        $presentacion = InsumoPresentacion::create(['insumoid' => $insumo->getKey(), 'nombre' => 'Bolsa 500 g', 'tipo_envase' => 'bolsa', 'peso_neto_kg' => '0.5', 'activo' => true]);
        $partida = InventarioPresentacionLote::create(['almacenid' => $almacenId, 'insumoid' => $insumo->getKey(),
            'insumo_presentacionid' => $presentacion->getKey(), 'loteproduccionpedidoid' => $this->f['lote']->getKey(),
            'cantidad_unidades' => $cantidad, 'cantidad_kg' => '6.061728']);
        $ingreso = AlmacenajeLoteProduccion::create(['loteproduccionpedidoid' => $this->f['lote']->getKey(),
            'almacenid' => $almacenId, 'ubicacion' => 'Destino de prueba', 'condicion' => \App\Support\AlmacenajeLoteCondiciones::opciones()[0], 'cantidad' => $cantidad, 'fecha_almacenaje' => now()]);
        $ingreso->forceFill(['insumoid' => $insumo->getKey(), 'insumo_presentacionid' => $presentacion->getKey(),
            'inventario_presentacion_loteid' => $partida->getKey(), 'datos_ingreso' => [
                'producto' => $producto, 'presentacion' => $presentacion->nombre, 'unidad' => 'bolsas',
                'cantidad_unidades' => $cantidad, 'cantidad_kg' => '6.061728',
                'almacenid' => $almacenId, 'almacen' => $this->f['almacen']->newQuery()->findOrFail($almacenId)->nombre,
                'fecha' => now()->toIso8601String(),
            ]])->save();

        return compact('insumo', 'presentacion', 'partida', 'ingreso');
    }

    public function test_varios_origenes_tienen_claves_consumo_real_unidades_y_recepcion_separada(): void
    {
        $datos = $this->datos();
        $this->assertCount(2, $datos['origenes']);
        foreach ($datos['origenes'] as $origen) {
            $this->assertSame('5.123000', $origen['cantidad_consumida']);
            $this->assertSame('100.123456', $origen['cantidad_recibida']);
            $this->assertSame('kg', $origen['unidad_registrada']);
            $this->assertNotNull($origen['movimiento_consumo_id']);
            $this->assertNotNull($origen['materiaprimaloteid']);
        }
        $this->assertCount(2, array_unique(array_column($datos['origenes'], 'consumo_id')));
        $lineas = $this->f['lote']->materiasPrimas()->orderBy('loteproduccionmateriaid')->get()
            ->map(fn ($m, $i) => ['insumoid' => $m->insumoid, 'materiaprimaloteid' => $m->materiaprimaloteid,
                'cantidad' => $i === 0 ? '1.001' : '2.002'])->all();
        $otro = app(LoteProduccionPlantaService::class)->crear($this->f['planta'], 'Tomate', null, null, $this->f['kg']->getKey(), $lineas);
        $recorrido = app(ProduccionPlantaRecorridoService::class)->consultar($otro, $this->f['planta']);
        $this->assertSame(['1.001000', '2.002000'], array_column($recorrido['origenes'], 'cantidad_consumida'));
    }

    public function test_origen_unico_compartido_entre_lotes_conserva_su_consumo_individual(): void
    {
        $m = $this->f['lote']->materiasPrimas()->first();
        $otro = app(LoteProduccionPlantaService::class)->crear($this->f['planta'], 'Tomate', null, null, $this->f['kg']->getKey(),
            [['insumoid' => $m->insumoid, 'cantidad' => '0.001', 'materiaprimaloteid' => $m->materiaprimaloteid]]);
        $this->actingAs($this->f['planta'])->getJson($this->url($otro))->assertOk()
            ->assertJsonCount(1, 'data.origenes')->assertJsonPath('data.origenes.0.cantidad_consumida', '0.001000')
            ->assertJsonPath('data.origenes.0.materiaprimaloteid', (int) $m->materiaprimaloteid);
        $this->assertSame('5.123000', $this->datos()['origenes'][0]['cantidad_consumida']);
        $this->f['lote'] = $otro;
        $salida = $this->salida();
        $recorrido = $this->datos();
        $this->assertCount(1, $recorrido['origenes']);
        $this->assertCount(1, $recorrido['productos_obtenidos']);
        $this->assertSame((int) $salida['partida']->getKey(), $recorrido['productos_obtenidos'][0]['partida_id']);
        $this->assertSame((int) $this->f['almacen']->getKey(), $recorrido['ingresos_produccion'][0]['almacen_id']);
    }

    public function test_etapa_completada_no_inventa_productos_ni_destinos_desde_parametros(): void
    {
        $this->assertNotNull($this->f['registro']);
        $this->assertSame([], $this->datos()['productos_obtenidos']);
        $this->assertSame([], $this->datos()['ingresos_produccion']);
        $this->actingAs($this->f['planta'])->get(route('procesamiento.show', $this->f['lote']))->assertOk()
            ->assertSee('Sin productos obtenidos registrados')->assertSee('Almacén de destino no registrado');
    }

    public function test_varios_productos_destinos_y_etapas_no_duplican_consumos_o_ingresos(): void
    {
        $this->salida();
        $almacen = $this->f['almacen']->replicate();
        $almacen->nombre = 'Segundo destino';
        $almacen->save();
        $this->salida('2.000001', $almacen->getKey(), 'Tomate concentrado');
        $datos = $this->datos();
        $this->assertCount(2, $datos['origenes']);
        $this->assertCount(2, $datos['productos_obtenidos']);
        $this->assertCount(2, $datos['ingresos_produccion']);
        $this->assertSame('2.000001', $datos['ingresos_produccion'][1]['cantidad_ingresada']);
        $this->assertSame('Segundo destino', $datos['ingresos_produccion'][1]['almacen']);
    }

    public function test_mismo_producto_de_catalogo_en_otro_proceso_no_se_atribuye_al_consultado(): void
    {
        $s = $this->salida();
        $otro = $this->f['lote']->replicate();
        $otro->codigo_lote = 'OTRO-46';
        $otro->save();
        $partida = $s['partida']->replicate();
        $partida->loteproduccionpedidoid = $otro->getKey();
        $partida->save();
        $this->assertCount(1, $this->datos()['productos_obtenidos']);
        $this->assertCount(1, $this->datos()['ubicaciones_actuales']);
    }

    public function test_destino_original_y_cantidad_permanecen_despues_de_un_cambio_de_ubicacion_y_saldo(): void
    {
        $s = $this->salida();
        $otro = $this->f['almacen']->replicate();
        $otro->nombre = 'Ubicación posterior';
        $otro->save();
        $s['partida']->update(['almacenid' => $otro->getKey(), 'cantidad_unidades' => '0.000001', 'cantidad_kg' => '0.000001']);
        $s['ingreso']->update(['cantidad' => 0]);
        $datos = $this->datos();
        $this->assertSame($this->f['almacen']->nombre, $datos['ingresos_produccion'][0]['almacen']);
        $this->assertSame('12.123456', $datos['ingresos_produccion'][0]['cantidad_ingresada']);
        $this->assertSame('Ubicación posterior', $datos['ubicaciones_actuales'][0]['almacen']);
        $this->assertSame('0.000001', $datos['ubicaciones_actuales'][0]['cantidad_actual']);
    }

    public function test_legacy_no_reconstruye_produccion_desde_saldo_o_nombre_y_unidad_actual_es_explicita(): void
    {
        $s = $this->salida();
        DB::table('almacenaje_lote_produccion')->where('almacenajeloteid', $s['ingreso']->getKey())
            ->update(['datos_ingreso' => null, 'insumoid' => null, 'insumo_presentacionid' => null, 'inventario_presentacion_loteid' => null]);
        $this->f['lote']->materiasPrimas()->update(['almacen_movimientoid' => null]);
        $datos = $this->datos();
        $this->assertNull($datos['ingresos_produccion'][0]['cantidad_ingresada']);
        $this->assertNull($datos['ingresos_produccion'][0]['producto']);
        $this->assertCount(1, $datos['productos_obtenidos']);
        $this->assertNull($datos['origenes'][0]['unidad_registrada']);
        $this->assertSame('kg', $datos['origenes'][0]['unidad_catalogo_actual']);
    }

    public function test_ausencias_son_null_y_colecciones_vacias_no_ceros_inventados(): void
    {
        DB::table('lote_produccion_materia_prima')->where('loteproduccionpedidoid', $this->f['lote']->getKey())->delete();
        $datos = $this->datos();
        $this->assertSame([], $datos['origenes']);
        $this->assertSame([], $datos['productos_obtenidos']);
        $this->actingAs($this->f['planta'])->get(route('procesamiento.show', $this->f['lote']))
            ->assertOk()->assertSee('Sin materias primas vinculadas');
    }

    public function test_invitado_y_jefe_de_otra_planta_no_consultan_proceso_ajeno(): void
    {
        $this->getJson($this->url())->assertUnauthorized();
        $ajeno = CertificadosFixture::usuario('jefe_planta', 'ajeno46');
        $this->actingAs($ajeno)->getJson($this->url())->assertNotFound();
        $this->get(route('procesamiento.show', $this->f['lote']))->assertNotFound();
        $this->get(route('procesamiento.index'))->assertOk()->assertDontSee($this->f['lote']->codigo_lote);
    }

    public function test_usuario_puede_ver_proceso_sin_acceder_a_partidas_ajenas_ni_a_sus_conteos(): void
    {
        $m = $this->f['lote']->materiasPrimas()->first();
        $ajeno = CertificadosFixture::usuario('jefe_planta', 'dueno46');
        $almacen = $this->f['almacen']->replicate();
        $almacen->responsable_usuarioid = $ajeno->getKey();
        $almacen->nombre = 'Almacén secreto';
        $almacen->save();
        $m->insumo->update(['almacenid' => $almacen->getKey(), 'nombre' => 'Origen secreto']);
        $m->materiaPrimaLote->update(['almacenid' => $almacen->getKey()]);
        $this->actingAs($this->f['operario'])->getJson($this->url())->assertOk()
            ->assertJsonCount(1, 'data.origenes')->assertJsonPath('data.restricciones.origenes', true)
            ->assertDontSee('Origen secreto')->assertDontSee('Almacén secreto')->assertDontSee('proveedor_actorid');
        $this->get(route('procesamiento.show', $this->f['lote']))->assertOk()
            ->assertDontSee('Origen secreto')->assertSee('información de origen restringida');
    }

    public function test_relaciones_agricolas_no_amplian_permisos_y_admin_ve_claves_reales(): void
    {
        $this->assertNull($this->datos()['origenes'][0]['origen_agricola']);
        $this->assertTrue($this->datos()['origenes'][0]['antecedente_restringido']);
        $admin = CertificadosFixture::usuario('admin', 'admin46');
        $this->actingAs($admin)->getJson($this->url())->assertOk()
            ->assertJsonPath('data.origenes.0.origen_agricola.loteid', (int) $this->f['campos'][0]->getKey());
    }

    public function test_identificadores_anidados_de_otro_lote_y_operario_ajeno_se_rechazan(): void
    {
        $otro = $this->f['lote']->replicate();
        $otro->codigo_lote = 'ANIDADO-46';
        $otro->save();
        $this->actingAs($this->f['operario'])->getJson($this->url($otro).'/tareas/'.$this->f['asignacion']->getKey())->assertNotFound();
        $ajeno = CertificadosFixture::usuario('planta', 'operarioAjeno46');
        $this->actingAs($ajeno)->getJson($this->url())->assertNotFound();
    }

    public function test_web_api_y_detalle_tarea_comparten_datos_sin_romper_contrato(): void
    {
        $this->salida();
        $this->actingAs($this->f['operario']);
        $datos = app(ProduccionPlantaRecorridoService::class)->consultar($this->f['lote'], $this->f['operario']);
        $this->getJson($this->url())->assertOk()->assertExactJson(['data' => $datos]);
        $this->get(route('procesamiento.show', $this->f['lote']))->assertOk()->assertViewHas('recorridoProduccion', $datos);
        $this->getJson('/api/planta/tareas/'.$this->f['asignacion']->getKey())->assertOk()
            ->assertJsonPath('origen_destino', $datos)->assertJsonPath('meta.permite_parciales', false)
            ->assertJsonPath('data.asignacionetapaplantaid', (int) $this->f['asignacion']->getKey());
    }

    public function test_consultas_repetidas_no_escriben_movimientos_existencias_rutas_o_estados(): void
    {
        $this->salida();
        $this->actingAs($this->f['planta']);
        $escrituras = [];
        DB::listen(function ($q) use (&$escrituras) {
            if (preg_match('/^\s*(insert|update|delete|replace)\b/i', $q->sql)) {
                $escrituras[] = $q->sql;
            }
        });
        for ($i = 0; $i < 2; $i++) {
            $this->getJson($this->url())->assertOk();
            $this->get(route('procesamiento.show', $this->f['lote']))->assertOk();
        }
        $this->assertSame([], $escrituras);
    }

    public function test_consulta_y_nuevos_ingresos_no_modifican_emision_congelada_ni_archivo(): void
    {
        config(['blockchain.enabled' => false]);
        Storage::fake('local');
        $this->mock(CertificadoDocumentoService::class, fn ($m) => $m->shouldReceive('generar')->andReturn('%PDF-1.4 congelado'));
        $cert = app(CertificadoEmisionService::class)->emitirPlanta($this->f['planta'], $this->f['lote'], ['razon' => 'Certificado']);
        $antes = $cert->getAttributes();
        $archivos = Storage::disk('local')->allFiles();
        $hashes = array_map(fn ($f) => hash('sha256', Storage::disk('local')->get($f)), $archivos);
        $this->salida();
        $this->datos();
        $this->assertSame($antes, $cert->fresh()->getAttributes());
        $this->assertSame($hashes, array_map(fn ($f) => hash('sha256', Storage::disk('local')->get($f)), $archivos));
    }

    public function test_almacenaje_real_guarda_relaciones_y_cantidad_original_en_transaccion(): void
    {
        $lote = $this->f['lote'];
        $lote->update(['empaque_catalogo_slug' => 'bolsa', 'empaque_tipo_envase' => 'bolsa']);
        EvaluacionFinalLoteProduccion::create(['loteproduccionpedidoid' => $lote->getKey(), 'inspector_usuarioid' => $this->f['planta']->getKey(),
            'razon' => 'Certificado', 'fecha_evaluacion' => now()]);
        $this->actingAs($this->f['planta'])->post(route('procesamiento.almacenar', $lote),
            ['almacenid' => $this->f['almacen']->getKey(), 'condicion' => \App\Support\AlmacenajeLoteCondiciones::opciones()[0]])->assertSessionHasNoErrors()->assertRedirect();
        $ingreso = $lote->almacenajes()->firstOrFail();
        $this->assertNotNull($ingreso->datos_ingreso);
        $this->assertSame((int) $lote->getKey(), (int) $ingreso->partidaGenerada->loteproduccionpedidoid);
        $this->assertSame((int) $ingreso->insumoid, (int) $ingreso->partidaGenerada->insumoid);
        $this->assertSame($ingreso->datos_ingreso['cantidad_unidades'], $this->datos()['ingresos_produccion'][0]['cantidad_ingresada']);
    }

    public function test_almacenaje_rechaza_destino_ajeno_y_operario_sin_crear_salida(): void
    {
        $ajeno = CertificadosFixture::usuario('jefe_planta', 'destinoAjeno46');
        $almacen = $this->f['almacen']->replicate();
        $almacen->responsable_usuarioid = $ajeno->getKey();
        $almacen->save();
        $this->f['lote']->update(['empaque_catalogo_slug' => 'bolsa']);
        EvaluacionFinalLoteProduccion::create(['loteproduccionpedidoid' => $this->f['lote']->getKey(), 'inspector_usuarioid' => $this->f['planta']->getKey(), 'razon' => 'Certificado', 'fecha_evaluacion' => now()]);
        $datos = ['almacenid' => $almacen->getKey(), 'condicion' => \App\Support\AlmacenajeLoteCondiciones::opciones()[0]];
        $this->actingAs($this->f['planta'])->post(route('procesamiento.almacenar', $this->f['lote']), $datos)->assertForbidden();
        $this->actingAs($this->f['operario'])->post(route('procesamiento.almacenar', $this->f['lote']), $datos)->assertForbidden();
        $this->assertSame(0, AlmacenajeLoteProduccion::count());
    }

    public function test_sin_permiso_inventario_conserva_proceso_pero_no_revela_productos_ni_destinos(): void
    {
        $this->salida();
        $this->f['operario']->roles->first()->revokePermissionTo('inventario.view');
        $this->f['operario']->unsetRelation('roles')->unsetRelation('permissions');
        $this->actingAs($this->f['operario'])->getJson($this->url())->assertOk()
            ->assertJsonPath('data.origenes', [])->assertJsonPath('data.productos_obtenidos', [])
            ->assertJsonPath('data.ingresos_produccion', [])->assertJsonPath('data.ubicaciones_actuales', [])
            ->assertJsonPath('data.restricciones.origenes', true)->assertJsonPath('data.restricciones.destinos', true);
        $this->get(route('procesamiento.show', $this->f['lote']))->assertOk()
            ->assertDontSee('Tomate terminado')->assertDontSee('Sin productos obtenidos registrados');
    }

    public function test_nueva_referencia_de_movimiento_permite_eliminar_lote_sin_procesar_y_revertir_consumo(): void
    {
        $m = $this->f['lote']->materiasPrimas()->first();
        $antes = $m->materiaPrimaLote->getRawOriginal('cantidad_disponible');
        $service = app(LoteProduccionPlantaService::class);
        $otro = $service->crear($this->f['planta'], 'Tomate', null, null, $this->f['kg']->getKey(),
            [['insumoid' => $m->insumoid, 'cantidad' => '1.001', 'materiaprimaloteid' => $m->materiaprimaloteid]]);
        $service->eliminar($this->f['planta'], $otro);
        $this->assertNull($otro->fresh());
        $this->assertEquals($antes, $m->materiaPrimaLote->fresh()->getRawOriginal('cantidad_disponible'));
    }

    public function test_fallo_en_vinculo_de_ingreso_revierte_almacenaje_partida_y_stock(): void
    {
        $this->f['lote']->update(['empaque_catalogo_slug' => 'bolsa']);
        EvaluacionFinalLoteProduccion::create(['loteproduccionpedidoid' => $this->f['lote']->getKey(),
            'inspector_usuarioid' => $this->f['planta']->getKey(), 'razon' => 'Certificado', 'fecha_evaluacion' => now()]);
        $antes = DB::table('insumo')->orderBy('insumoid')->get()->toJson();
        $this->mock(\App\Services\InventarioPresentacionService::class,
            fn ($m) => $m->shouldReceive('ingresar')->once()->andThrow(new \RuntimeException('Fallo de prueba de ingreso')));
        $this->withoutExceptionHandling();
        try {
            $this->actingAs($this->f['planta'])->post(route('procesamiento.almacenar', $this->f['lote']),
                ['almacenid' => $this->f['almacen']->getKey(), 'condicion' => \App\Support\AlmacenajeLoteCondiciones::opciones()[0]]);
            $this->fail('El fallo debía propagarse.');
        } catch (\RuntimeException $e) {
            $this->assertSame('Fallo de prueba de ingreso', $e->getMessage());
        }
        $this->assertSame(0, AlmacenajeLoteProduccion::count());
        $this->assertSame(0, InventarioPresentacionLote::count());
        $this->assertSame($antes, DB::table('insumo')->orderBy('insumoid')->get()->toJson());
    }
}
