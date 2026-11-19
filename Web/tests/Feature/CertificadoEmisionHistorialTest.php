<?php

namespace Tests\Feature;

use App\Models\CertificacionLote;
use App\Models\EvaluacionFinalLoteProduccion;
use App\Services\Blockchain\CertificacionLotePayloadBuilder;
use App\Services\CertificadoDocumentoService;
use App\Services\CertificadoEmisionService;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\Support\CertificadosFixture;
use Tests\TestCase;

class CertificadoEmisionHistorialTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        config(['blockchain.enabled' => false]);
        Storage::fake('local');
        $this->f = CertificadosFixture::crear();
        $this->mock(CertificadoDocumentoService::class, fn ($m) => $m->shouldReceive('generar')->andReturnUsing(fn ($datos) => "%PDF-1.4\n".json_encode($datos, JSON_UNESCAPED_UNICODE)));
    }

    private function campo(array $datos = []): CertificacionLote
    {
        return app(CertificadoEmisionService::class)->emitirCampo($this->f['agricola'], $this->f['campoCertificable'], $datos);
    }

    private function planta(array $datos = []): EvaluacionFinalLoteProduccion
    {
        return app(CertificadoEmisionService::class)->emitirPlanta($this->f['planta'], $this->f['lote'], ['razon' => 'Certificado', ...$datos]);
    }

    public function test_primera_y_segunda_emision_conservan_ids_fechas_archivos_y_datos_independientes(): void
    {
        $primera = $this->campo(['observaciones' => 'Primera evaluación']);
        $antes = $primera->getAttributes();
        $bytes = Storage::disk('local')->get($primera->archivo_path);
        $segunda = $this->campo(['observaciones' => 'Segunda evaluación']);
        $this->assertNotSame($primera->getKey(), $segunda->getKey());
        $this->assertNotSame($primera->codigo_certificado, $segunda->codigo_certificado);
        $this->assertNotSame($primera->archivo_path, $segunda->archivo_path);
        $this->assertSame($antes, $primera->fresh()->getAttributes());
        $this->assertSame($bytes, Storage::disk('local')->get($primera->archivo_path));
        $this->assertSame('100.123456', $primera->datos_emision['recorrido']['cosechas'][0]['cantidad']);
        $this->assertEquals($this->f['agricola']->getKey(), $primera->usuarioid);
        $this->assertNotNull($primera->fecha_certificacion);
        $this->assertCount(2, Storage::disk('local')->allFiles('certificados'));
    }

    public function test_producto_parametros_responsables_y_relaciones_actuales_no_reescriben_emision(): void
    {
        $e = $this->planta();
        $datos = $e->datos_emision;
        $bytes = Storage::disk('local')->get($e->archivo_path);
        $this->f['lote']->update(['nombre' => 'Nombre actual diferente', 'cantidad_objetivo' => 40]);
        $this->f['planta']->update(['nombre' => 'Emisor actual cambiado']);
        $this->f['registro']->update(['variables_ingresadas' => json_encode(['parametros' => []])]);
        $this->f['lote']->materiasPrimas()->first()->update(['cantidad_usada' => '1']);
        $this->assertSame($datos, $e->fresh()->datos_emision);
        $this->assertSame($bytes, Storage::disk('local')->get($e->archivo_path));
        $this->actingAs($this->f['planta'])->get(route('certificaciones-planta.show', $e))->assertOk()
            ->assertSee('10.123456')->assertDontSee('Nombre actual diferente')->assertSee('Emitido por:</strong> planta44 Antecedentes', false);
    }

    public function test_historial_ordenado_por_fecha_e_id_aunque_coincida_la_fecha(): void
    {
        $this->travelTo(now()->startOfSecond());
        $a = $this->campo();
        $b = $this->campo();
        $this->actingAs($this->f['agricola'])->getJson('/api/lotes/'.$a->loteid.'/certificados')->assertOk()
            ->assertJsonPath('data.0.certificacionid', $b->getKey())->assertJsonPath('data.1.certificacionid', $a->getKey());
        $this->get(route('lotes.certificados.index', $a->loteid))->assertOk()->assertSeeInOrder([$b->codigo_certificado, $a->codigo_certificado]);
        $this->travelBack();
    }

    public function test_descarga_recupera_bytes_seleccionados_sin_regenerar(): void
    {
        $a = $this->campo(['observaciones' => 'Archivo A']);
        $b = $this->campo(['observaciones' => 'Archivo B']);
        $this->actingAs($this->f['agricola']);
        foreach ([$a, $b] as $e) {
            $r = $this->get('/api/certificaciones/'.$e->getKey().'/archivo')->assertOk()->assertHeader('content-type', 'application/pdf');
            $this->assertSame(Storage::disk('local')->get($e->archivo_path), $r->streamedContent());
        }
        Storage::disk('local')->delete($a->archivo_path);
        $this->get('/api/certificaciones/'.$a->getKey().'/archivo')->assertNotFound();
        Storage::disk('local')->assertMissing($a->archivo_path);
    }

    public function test_antecedentes_son_solo_lectura_por_modelo_y_no_hay_update_delete_http(): void
    {
        $e = $this->campo();
        $antes = $e->getAttributes();
        foreach (['observaciones' => 'Reescritura', 'archivo_path' => 'otro.pdf', 'usuarioid' => $this->f['planta']->getKey(), 'datos_emision' => []] as $campo => $valor) {
            try {
                $e->fresh()->forceFill([$campo => $valor])->save();
                $this->fail('No debe permitirse reescribir una emisión.');
            } catch (\Illuminate\Validation\ValidationException $ex) {
                $this->assertArrayHasKey('certificado', $ex->errors());
            }
        }
        try {
            $e->fresh()->delete();
            $this->fail('No debe eliminarse un antecedente.');
        } catch (\App\Exceptions\EliminacionBloqueadaException $ex) {
            $this->assertStringContainsString('eliminar', $ex->getMessage());
        }
        $this->actingAs($this->f['agricola'])->putJson('/api/certificaciones/'.$e->getKey(), ['observaciones' => 'Reescribir'])->assertStatus(405);
        $this->deleteJson('/api/certificaciones/'.$e->getKey())->assertStatus(405);
        $this->assertSame($antes, $e->fresh()->getAttributes());
    }

    public function test_fk_impide_borrar_lote_con_certificado_aunque_se_use_query_builder(): void
    {
        $e = $this->campo();
        try {
            DB::table('lote')->where('loteid', $e->loteid)->delete();
            $this->fail('La FK debe conservar el antecedente.');
        } catch (\Illuminate\Database\QueryException) {
            $this->assertDatabaseHas('certificacion_lote', ['certificacionid' => $e->getKey()]);
        }
    }

    public function test_varios_origenes_recepciones_etapas_y_precision_sin_mezclar_otro_producto(): void
    {
        $e = $this->planta();
        $r = $e->datos_emision['recorrido'];
        $this->assertCount(2, $r['materias_primas']);
        $this->assertCount(1, $r['etapas']);
        $this->assertSame('10.123456', $r['etapas'][0]['parametros'][0]['valor_decimal']);
        $ids = array_column(array_column(array_column($r['materias_primas'], 'recepcion'), 'linea_recibida'), 'detallepedidoid');
        $this->assertCount(2, array_unique($ids));
        foreach ($r['materias_primas'] as $i => $m) {
            $this->assertSame($this->f['campos'][$i]->getKey(), $m['recepcion']['linea_recibida']['origen']['loteid']);
            $this->assertSame('5.123000', $m['cantidad_usada']);
        }
        $otro = \App\Models\LoteProduccionPedido::create(['pedidoid' => $this->f['pedido']->getKey(), 'codigo_lote' => 'LP-AJENO', 'nombre' => 'OTRO PRODUCTO', 'producto' => 'Ajeno', 'fecha_creacion' => now()]);
        $this->assertStringNotContainsString('OTRO PRODUCTO', json_encode($r));
    }

    public function test_sin_sesion_permiso_ni_ambito_no_consulta_metadatos_o_archivo(): void
    {
        $e = $this->campo();
        $this->get('/api/certificaciones/'.$e->getKey())->assertUnauthorized();
        $ajeno = CertificadosFixture::usuario('jefe_agricultor', 'ajeno44');
        $this->actingAs($ajeno)->getJson('/api/certificaciones/'.$e->getKey())->assertNotFound();
        $this->get('/api/certificaciones/'.$e->getKey().'/archivo')->assertNotFound();
        $this->getJson('/api/certificaciones')->assertOk()->assertExactJson([]);
        $ajeno->syncRoles([]);
        $this->getJson('/api/certificaciones/'.$e->getKey())->assertForbidden();
        $this->get('/storage/'.$e->archivo_path)->assertForbidden();
    }

    public function test_planta_ajena_y_operario_no_acceden_a_certificados(): void
    {
        $e = $this->planta();
        $ajeno = CertificadosFixture::usuario('jefe_planta', 'plantaAjena44');
        $url = '/api/planta/lotes-produccion/'.$e->loteproduccionpedidoid.'/certificados/'.$e->getKey();
        $this->actingAs($ajeno)->getJson($url)->assertNotFound();
        $this->get('/api/planta/certificados/'.$e->getKey().'/archivo')->assertNotFound();
        $this->get(route('certificaciones-planta.index'))->assertOk()->assertDontSee($e->codigo_certificado);
        $this->actingAs($this->f['operario'])->getJson($url)->assertNotFound();
    }

    public function test_ruta_anidada_no_acepta_certificado_de_otro_lote(): void
    {
        $e = $this->campo();
        $this->actingAs($this->f['agricola'])->getJson('/api/lotes/'.$this->f['campos'][1]->getKey().'/certificados/'.$e->getKey())->assertNotFound();
    }

    public function test_legacy_no_recibe_instantanea_fecha_emisor_o_archivo_inventados(): void
    {
        $e = CertificacionLote::create(['loteid' => $this->f['campoCertificable']->getKey(), 'usuarioid' => $this->f['agricola']->getKey(),
            'codigo_certificado' => 'CERT-LEGACY-44', 'resultado' => 'Certificado', 'observaciones' => 'Dato original', 'fecha_certificacion' => '2025-01-01 08:00:00']);
        $antes = $e->fresh()->getAttributes();
        $this->actingAs($this->f['agricola'])->getJson('/api/certificaciones/'.$e->getKey())->assertOk()->assertJsonPath('instantanea', null)->assertJsonPath('archivo_disponible', false);
        $this->get(route('certificaciones.show', $e))->assertOk()->assertSee('sin instantánea histórica')->assertSee('Dato original');
        $this->get('/api/certificaciones/'.$e->getKey().'/archivo')->assertNotFound();
        $this->assertSame($antes, $e->fresh()->getAttributes());
        $this->assertCount(0, Storage::disk('local')->allFiles('certificados'));
    }

    public function test_fallo_generacion_no_confirma_emision_y_no_deja_archivos(): void
    {
        $this->mock(CertificadoDocumentoService::class, fn ($m) => $m->shouldReceive('generar')->andThrow(new \RuntimeException('Fallo PDF de prueba')));
        try {
            $this->campo();
            $this->fail('Debe fallar la generación.');
        } catch (\RuntimeException $ex) {
            $this->assertSame('Fallo PDF de prueba', $ex->getMessage());
        }
        $this->assertDatabaseCount('certificacion_lote', 0);
        $this->assertCount(0, Storage::disk('local')->allFiles('certificados'));
    }

    public function test_fallo_persistencia_limpia_solo_archivo_nuevo_y_preserva_confirmado(): void
    {
        $anterior = $this->campo();
        $bytes = Storage::disk('local')->get($anterior->archivo_path);
        CertificacionLote::creating(fn () => throw new \RuntimeException('Fallo persistencia'));
        try {
            $this->campo();
            $this->fail('Debe fallar la persistencia.');
        } catch (\RuntimeException $ex) {
            $this->assertSame('Fallo persistencia', $ex->getMessage());
        } finally {
            CertificacionLote::flushEventListeners();
        }
        $this->assertDatabaseCount('certificacion_lote', 1);
        $this->assertCount(1, Storage::disk('local')->allFiles('certificados'));
        $this->assertSame($bytes, Storage::disk('local')->get($anterior->archivo_path));
    }

    public function test_reintento_identificado_reutiliza_y_nueva_solicitud_crea_otro_antecedente(): void
    {
        $id = (string) Str::uuid();
        $a = $this->campo(['solicitud_id' => $id]);
        $b = $this->campo(['solicitud_id' => $id]);
        $this->assertSame($a->getKey(), $b->getKey());
        $c = $this->campo(['solicitud_id' => (string) Str::uuid()]);
        $this->assertNotSame($a->getKey(), $c->getKey());
        $this->assertCount(2, Storage::disk('local')->allFiles('certificados'));
        try {
            $this->campo(['solicitud_id' => $id, 'observaciones' => 'Otro contenido']);
            $this->fail('Debe detectar el conflicto.');
        } catch (\Symfony\Component\HttpKernel\Exception\ConflictHttpException) {
            $this->assertDatabaseCount('certificacion_lote', 2);
        }
    }

    public function test_consultar_antecedentes_no_modifica_registros_y_distingue_actual_de_historico(): void
    {
        $e = $this->planta();
        $antes = $e->getAttributes();
        $this->f['lote']->update(['nombre' => 'Nombre actual']);
        $this->actingAs($this->f['planta'])->getJson('/api/planta/lotes-produccion/'.$e->loteproduccionpedidoid.'/antecedentes')->assertOk()->assertJsonPath('datos_actuales.producto.nombre', 'Nombre actual');
        $this->assertNotSame('Nombre actual', $e->fresh()->datos_emision['recorrido']['producto']['nombre']);
        $this->assertSame($antes, $e->fresh()->getAttributes());
    }

    public function test_blockchain_reutiliza_datos_de_emision_sin_recapturar_datos_actuales(): void
    {
        $e = $this->campo();
        $builder = app(CertificacionLotePayloadBuilder::class);
        $antes = $builder->construir($e);
        $this->f['campoCertificable']->update(['nombre' => 'Nombre cambiado']);
        $this->f['campoCertificable']->producciones()->first()->update(['cantidad' => '200']);
        $this->assertSame($antes, $builder->construir($e->fresh()));
        $this->assertSame($e->getKey(), $antes['payload']['certificacion']['certificacionId']);
    }

    public function test_api_y_web_emiten_por_servicio_compartido_y_rechazan_campos_protegidos(): void
    {
        $this->actingAs($this->f['agricola']);
        $body = ['loteid' => $this->f['campoCertificable']->getKey(), 'solicitud_id' => (string) Str::uuid()];
        $this->postJson('/api/certificaciones', [...$body, 'datos_emision' => []])->assertUnprocessable()->assertJsonValidationErrors('datos_emision');
        $api = $this->postJson('/api/certificaciones', $body)->assertCreated();
        $this->post(route('certificaciones.store'), $body)->assertSessionHasNoErrors()->assertRedirect();
        $this->assertDatabaseCount('certificacion_lote', 1);
        $this->assertNotNull(CertificacionLote::findOrFail($api->json('certificacionid'))->datos_emision);
    }

    public function test_documento_real_se_genera_con_el_formato_versionado_existente(): void
    {
        $this->app->forgetInstance(CertificadoDocumentoService::class);
        $this->app->forgetInstance(CertificadoEmisionService::class);
        $e = $this->planta();
        $pdf = Storage::disk('local')->get($e->archivo_path);
        $this->assertStringStartsWith('%PDF-', $pdf);
        $this->assertGreaterThan(1000, strlen($pdf));
        $this->assertSame(1, $e->formato_version);
    }

    public function test_cosechas_con_unidades_distintas_se_conservan_sin_sumarse(): void
    {
        $otra = $this->f['campoCertificable']->producciones()->first()->replicate();
        $unidad = \App\Models\UnidadMedida::create(['nombre' => 'Litro de prueba', 'abreviatura' => 'l', 'categoria' => 'volumen']);
        $otra->unidadmedidaid = $unidad->getKey();
        $otra->cantidad = '25.000001';
        $otra->save();
        $e = $this->campo();
        $this->assertSame(['100.123456', '25.000001'], array_column($e->datos_emision['recorrido']['cosechas'], 'cantidad'));
        $this->assertSame(['kg', 'l'], array_column($e->datos_emision['recorrido']['cosechas'], 'unidad'));
        $this->assertNull($e->datos_emision['blockchain_base']['resumenCosecha']['cantidadTotal']);
    }

    public function test_servicios_de_eliminacion_no_borran_antecedentes_aunque_cambie_estado_actual(): void
    {
        $campo = $this->campo();
        $planta = $this->planta();
        $this->f['campoCertificable']->update(['estadolotetipoid' => \App\Support\EstadoLoteCatalogo::idPorSlug('planificado')]);
        try {
            app(\App\Services\LoteEliminacionService::class)->eliminar($this->f['campoCertificable']->fresh());
            $this->fail('Debe proteger el lote certificado.');
        } catch (\App\Exceptions\EliminacionBloqueadaException) {
            $this->assertDatabaseHas('certificacion_lote', ['certificacionid' => $campo->getKey()]);
        }
        try {
            app(\App\Services\LoteProduccionPlantaService::class)->eliminar($this->f['planta'], $this->f['lote']);
            $this->fail('Debe proteger el lote industrial certificado.');
        } catch (\InvalidArgumentException) {
            $this->assertDatabaseHas('evaluacion_final_lote_produccion', ['evaluacionfinalloteid' => $planta->getKey()]);
        }
        Storage::disk('local')->assertExists([$campo->archivo_path, $planta->archivo_path]);
    }

    public function test_legacy_de_planta_no_se_reconstruye_con_datos_actuales(): void
    {
        $e = EvaluacionFinalLoteProduccion::create(['loteproduccionpedidoid' => $this->f['lote']->getKey(),
            'inspector_usuarioid' => null, 'razon' => 'Certificado', 'observaciones' => 'Antecedente industrial',
            'fecha_evaluacion' => '2025-03-01 10:00:00']);
        $antes = $e->fresh()->getAttributes();
        $this->actingAs($this->f['planta'])->get(route('certificaciones-planta.show', $e))->assertOk()
            ->assertSee('sin instantánea histórica')->assertSee('Antecedente industrial')->assertSee('No registrado');
        $this->get('/api/planta/certificados/'.$e->getKey().'/archivo')->assertNotFound();
        $this->assertSame($antes, $e->fresh()->getAttributes());
    }

    public function test_fallo_almacenamiento_no_confirma_emision(): void
    {
        $disk = Storage::disk('local');
        $mock = \Mockery::mock($disk)->makePartial();
        $mock->shouldReceive('put')->once()->andReturn(false);
        Storage::shouldReceive('disk')->with('local')->andReturn($mock);
        try {
            $this->campo();
            $this->fail('Debe fallar el almacenamiento.');
        } catch (\RuntimeException $e) {
            $this->assertStringContainsString('guardar', $e->getMessage());
        }
        $this->assertDatabaseCount('certificacion_lote', 0);
        $this->assertCount(0, $disk->allFiles('certificados'));
    }

    public function test_cambio_durante_generacion_no_confirma_datos_incompatibles(): void
    {
        $this->mock(CertificadoDocumentoService::class, function ($m) {
            $m->shouldReceive('generar')->andReturnUsing(function () {
                $this->f['campoCertificable']->update(['nombre' => 'Modificado mientras se generaba']);

                return '%PDF-1.4 prueba';
            });
        });
        try {
            $this->campo();
            $this->fail('Debe detectar el cambio del producto.');
        } catch (\Illuminate\Validation\ValidationException $e) {
            $this->assertArrayHasKey('certificado', $e->errors());
        }
        $this->assertDatabaseCount('certificacion_lote', 0);
        $this->assertCount(0, Storage::disk('local')->allFiles('certificados'));
    }

    public function test_dos_evaluaciones_planta_conservan_antecedentes_y_consulta_no_borra_almacenaje(): void
    {
        $a = $this->planta();
        $antes = $a->getAttributes();
        $b = $this->planta(['razon' => 'No conforme', 'observaciones' => 'Revisión posterior']);
        $this->assertNotSame($a->codigo_certificado, $b->codigo_certificado);
        $this->assertSame($antes, $a->fresh()->getAttributes());
        $this->assertDatabaseCount('evaluacion_final_lote_produccion', 2);
        $this->actingAs($this->f['planta'])->get(route('procesamiento.certificados.index', $this->f['lote']))->assertOk();
        $this->assertSame($antes, $a->fresh()->getAttributes());
        $this->assertCount(2, Storage::disk('local')->allFiles('certificados'));
    }
}
