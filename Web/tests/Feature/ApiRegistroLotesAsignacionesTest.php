<?php

namespace Tests\Feature;

use App\Models\{Actividad, Insumo, Lote, Prioridad, TipoActividad, TipoInsumo, UnidadMedida, Usuario};
use App\Services\LoteUbicacionTerrestreService;
use Database\Seeders\{CatalogosOperacionAgricolaSeeder, RolePermissionSeeder};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ApiRegistroLotesAsignacionesTest extends TestCase
{
    use RefreshDatabase;

    private Usuario $jefe;
    private Usuario $trabajador;
    private Usuario $otro;
    private Insumo $semilla;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $this->jefe = $this->usuario('jefe_agricultor', 'jefe');
        $this->trabajador = $this->usuario('agricultor', 'trabajador', $this->jefe->usuarioid);
        $this->otro = $this->usuario('jefe_agricultor', 'otro');
        $tipo = TipoInsumo::firstOrCreate(['nombre' => 'Material de Siembra']);
        $unidad = UnidadMedida::firstOrCreate(['nombre' => 'Kilogramo'], ['abreviatura' => 'kg', 'categoria' => 'peso']);
        $this->semilla = Insumo::create([
            'nombre' => 'Semilla de Papa', 'tipoinsumoid' => $tipo->tipoinsumoid,
            'unidadmedidaid' => $unidad->unidadmedidaid, 'stock' => 100000,
        ]);
        $this->mock(LoteUbicacionTerrestreService::class)->shouldReceive('validarMarcador')->andReturn(['ok' => true]);
        Sanctum::actingAs($this->jefe);
    }

    private function usuario(string $rol, string $nombre, ?int $supervisor = null): Usuario
    {
        $usuario = Usuario::create([
            'nombre' => $nombre, 'apellido' => 'Prueba', 'email' => $nombre.'@edt31.test',
            'nombreusuario' => $nombre, 'passwordhash' => bcrypt('test12345'), 'role' => $rol,
            'activo' => true, 'supervisor_usuarioid' => $supervisor,
            'fecharegistro' => now(), 'fechamodificacion' => now(),
        ]);
        $usuario->syncRoles([$rol]);
        return $usuario;
    }

    private function datosLote(): array
    {
        return ['nombre' => 'Lote móvil 24', 'superficie' => 2.75, 'ubicacion' => 'Parcela Norte',
            'insumosemillaid' => $this->semilla->insumoid, 'cantidad_semilla_planificada' => 1,
            'latitud' => -17.7, 'longitud' => -63.1];
    }

    private function crearLote(): Lote
    {
        $id = $this->postJson('/api/lotes', $this->datosLote())->assertCreated()->json('data.loteid');
        return Lote::findOrFail($id);
    }

    private function datosActividad(Lote $lote): array
    {
        $tipo = TipoActividad::firstOrCreate(['nombre' => 'Preparación del terreno'], ['descripcion' => 'Preparación']);
        $prioridad = Prioridad::firstOrCreate(['nombre' => 'Media']);
        return ['loteid' => $lote->loteid, 'usuarioid' => $this->trabajador->usuarioid,
            'tipoactividadid' => $tipo->tipoactividadid, 'prioridadid' => $prioridad->prioridadid,
            'descripcion' => 'Preparación móvil', 'fecha_planificada' => '2026-12-01'];
    }

    public function test_crear_consultar_y_editar_preserva_relaciones_y_web(): void
    {
        $lote = $this->crearLote();
        $this->assertSame($this->jefe->usuarioid, $lote->usuarioid);
        $this->assertSame($this->semilla->insumoid, $lote->insumosemillaid);
        $this->assertSame(2.75, $lote->superficie);
        $this->assertNotNull($lote->cultivo);
        $this->assertSame('ha', $lote->unidadSuperficie->abreviatura);
        $codigo = $lote->codigo_trazabilidad;
        $actividades = $lote->actividades->modelKeys();
        $this->patchJson('/api/lotes/'.$lote->loteid, ['nombre' => 'Nombre actualizado'])
            ->assertOk()->assertJsonPath('data.nombre', 'Nombre actualizado')
            ->assertJsonPath('data.insumosemillaid', $this->semilla->insumoid)
            ->assertJsonPath('data.superficie', 2.75)->assertJsonPath('data.codigo_trazabilidad', $codigo);
        $lote->refresh();
        $this->assertSame($actividades, $lote->actividades->modelKeys());
        $this->getJson('/api/lotes/'.$lote->loteid)->assertOk()->assertJsonPath('data.nombre', 'Nombre actualizado');
        $this->actingAs($this->jefe)->get('/lotes?q=Nombre')->assertOk()->assertSee('Nombre actualizado');
        $this->get('/lotes/'.$lote->loteid)->assertOk()->assertSee('Nombre actualizado');
    }

    public function test_campos_invalidos_y_protegidos_no_crean_registros(): void
    {
        $this->postJson('/api/lotes', [])->assertUnprocessable()->assertJsonValidationErrors(['superficie', 'insumosemillaid']);
        foreach ([['superficie' => -1], ['insumosemillaid' => 999999], ['latitud' => 100], ['nombre' => null], ['usuarioid' => $this->otro->usuarioid], ['cultivoid' => 1], ['estadolotetipoid' => 1]] as $cambio) {
            $this->postJson('/api/lotes', array_replace($this->datosLote(), $cambio))->assertUnprocessable()->assertJsonValidationErrors(array_keys($cambio));
        }
        $this->assertDatabaseCount('lote', 0);
    }

    public function test_edicion_no_transfiere_propiedad_ni_desconecta_semilla(): void
    {
        $lote = $this->crearLote();
        foreach ([['usuarioid' => $this->otro->usuarioid], ['insumosemillaid' => null], ['superficie' => null]] as $cambio) {
            $this->patchJson('/api/lotes/'.$lote->loteid, $cambio)->assertUnprocessable()->assertJsonValidationErrors(array_keys($cambio));
        }
        Sanctum::actingAs($this->otro);
        $this->patchJson('/api/lotes/'.$lote->loteid, ['nombre' => 'Ajeno'])->assertForbidden();
        $this->assertSame('Lote móvil 24', $lote->fresh()->nombre);
    }

    public function test_asignacion_persistida_y_rechazo_de_trabajador_ajeno(): void
    {
        $lote = $this->crearLote();
        // Creation uses the web workflow and can assign an initial sowing activity.
        $lote->actividades()->delete();
        $datos = $this->datosActividad($lote);
        $this->postJson('/api/actividades', array_replace($datos, ['usuarioid' => $this->otro->usuarioid]))
            ->assertUnprocessable()->assertJsonValidationErrors('usuarioid');
        $id = $this->postJson('/api/actividades', $datos)->assertCreated()
            ->assertJsonPath('data.usuarioid', $this->trabajador->usuarioid)->json('data.actividadid');
        $actividad = Actividad::findOrFail($id);
        $this->assertSame($lote->loteid, $actividad->loteid);
        $this->assertNull($actividad->fechafin);
        $this->getJson('/api/actividades/'.$id)->assertOk()->assertJsonPath('data.descripcion', 'Preparación móvil');
        $this->actingAs($this->jefe)->get('/actividades')->assertOk()->assertSee('Preparación móvil');
        $this->patchJson('/api/actividades/'.$id, ['usuarioid' => $this->otro->usuarioid])
            ->assertUnprocessable()->assertJsonValidationErrors('usuarioid');
        Sanctum::actingAs($this->otro);
        $this->postJson('/api/actividades', $datos)->assertForbidden();
        Sanctum::actingAs($this->trabajador);
        $this->postJson('/api/actividades', $datos)->assertForbidden();
    }

    public function test_fallo_en_historial_revierte_lote_y_relaciones(): void
    {
        \App\Models\HistorialEstadoLote::creating(fn () => throw new \RuntimeException('fallo de prueba'));
        $this->withoutExceptionHandling();
        try {
            $this->postJson('/api/lotes', $this->datosLote());
            $this->fail('Se esperaba un fallo al guardar el historial.');
        } catch (\RuntimeException $e) {
            $this->assertSame('fallo de prueba', $e->getMessage());
        } finally {
            \App\Models\HistorialEstadoLote::flushEventListeners();
        }
        $this->assertDatabaseCount('lote', 0);
        $this->assertDatabaseCount('actividad', 0);
    }

    public function test_null_explicito_y_campos_omitidos_tienen_semantica_distinta(): void
    {
        $lote = $this->crearLote();
        $this->patchJson('/api/lotes/'.$lote->loteid, ['cantidad_semilla_planificada' => 1.23456])
            ->assertOk()->assertJsonPath('data.cantidad_semilla_planificada', 1.235);
        $this->patchJson('/api/lotes/'.$lote->loteid, ['ubicacion' => null, 'cantidad_semilla_planificada' => null])
            ->assertOk()->assertJsonPath('data.ubicacion', null)->assertJsonPath('data.cantidad_semilla_planificada', null);
        $this->putJson('/api/lotes/'.$lote->loteid, ['nombre' => 'Con nulos'])
            ->assertOk()->assertJsonPath('data.ubicacion', null)->assertJsonPath('data.cantidad_semilla_planificada', null)
            ->assertJsonPath('data.latitud', -17.7)->assertJsonPath('data.longitud', -63.1);
        $this->patchJson('/api/lotes/'.$lote->loteid, ['latitud' => null])
            ->assertUnprocessable()->assertJsonValidationErrors(['latitud', 'longitud']);
        $this->patchJson('/api/lotes/'.$lote->loteid, ['latitud' => null, 'longitud' => null])
            ->assertOk()->assertJsonPath('data.latitud', null)->assertJsonPath('data.longitud', null);
    }

    public function test_lote_cerrado_no_se_edita_y_error_es_json(): void
    {
        $lote = $this->crearLote();
        $lote->update(['estadolotetipoid' => \App\Support\EstadoLoteCatalogo::idPorSlug('cosechado')]);
        $this->patchJson('/api/lotes/'.$lote->loteid, ['nombre' => 'Cambio prohibido'])
            ->assertUnprocessable()->assertJsonValidationErrors('loteid');
        $this->assertSame('Lote móvil 24', $lote->fresh()->nombre);
    }

    public function test_semilla_de_tipo_incorrecto_y_de_otro_almacen_se_rechazan(): void
    {
        $tipo = TipoInsumo::firstOrCreate(['nombre' => 'Fertilizantes']);
        $this->semilla->update(['tipoinsumoid' => $tipo->tipoinsumoid]);
        $this->postJson('/api/lotes', $this->datosLote())->assertUnprocessable()->assertJsonValidationErrors('insumosemillaid');
        $tipo = TipoInsumo::firstOrCreate(['nombre' => 'Material de Siembra']);
        $almacen = \App\Models\Almacen::create([
            'nombre' => 'Almacén ajeno', 'ubicacion' => 'Parcela Sur', 'capacidad' => 100,
            'unidadmedidaid' => $this->semilla->unidadmedidaid,
            'tipoalmacenid' => \App\Models\TipoAlmacen::firstOrCreate(['nombre' => 'Agrícola'])->tipoalmacenid,
            'ambito' => 'agricola', 'activo' => true, 'responsable_usuarioid' => $this->otro->usuarioid,
        ]);
        $this->semilla->update(['tipoinsumoid' => $tipo->tipoinsumoid, 'almacenid' => $almacen->almacenid]);
        $this->postJson('/api/lotes', $this->datosLote())->assertUnprocessable()->assertJsonValidationErrors('insumosemillaid');
        $this->assertDatabaseCount('lote', 0);
    }

    public function test_asignacion_invalida_no_escribe_y_no_mueve_actividad(): void
    {
        $lote = $this->crearLote();
        $datos = $this->datosActividad($lote);
        $cantidad = Actividad::count();
        foreach ([['usuarioid' => 999999], ['tipoactividadid' => 999999], ['fecha_planificada' => 'ayer-invalid'], ['fechafin' => '2026-12-10'], ['usuarioid_ejecutor' => $this->jefe->usuarioid]] as $cambio) {
            $this->postJson('/api/actividades', array_replace($datos, $cambio))
                ->assertUnprocessable()->assertJsonValidationErrors(array_keys($cambio));
        }
        $this->assertSame($cantidad, Actividad::count());
        $id = $this->postJson('/api/actividades', $datos)->assertCreated()->json('data.actividadid');
        $otroLote = $this->crearLote();
        $this->patchJson('/api/actividades/'.$id, ['loteid' => $otroLote->loteid])
            ->assertUnprocessable()->assertJsonValidationErrors('loteid');
        $this->assertSame($lote->loteid, Actividad::findOrFail($id)->loteid);
    }

    public function test_fallo_de_secuencia_no_deja_asignacion_parcial(): void
    {
        $lote = $this->crearLote();
        $datos = $this->datosActividad($lote);
        $cantidad = Actividad::count();
        Actividad::updating(fn () => throw new \RuntimeException('fallo secuencia'));
        $this->withoutExceptionHandling();
        try {
            $this->postJson('/api/actividades', $datos);
            $this->fail('Se esperaba un fallo al asignar la secuencia.');
        } catch (\RuntimeException $e) {
            $this->assertSame('fallo secuencia', $e->getMessage());
        } finally {
            Actividad::flushEventListeners();
        }
        $this->assertSame($cantidad, Actividad::count());
    }

    public function test_permisos_y_errores_json_sin_cabecera_accept(): void
    {
        $lote = $this->crearLote();
        $datos = $this->datosActividad($lote);
        $lector = $this->usuario('admin', 'lector');
        Sanctum::actingAs($lector);
        $this->postJson('/api/lotes', $this->datosLote())->assertForbidden();
        $this->patchJson('/api/lotes/'.$lote->loteid, ['nombre' => 'No permitido'])->assertForbidden();
        $this->postJson('/api/actividades', $datos)->assertForbidden();
        Sanctum::actingAs($this->jefe);
        $this->post('/api/lotes', [])->assertUnprocessable()->assertJsonValidationErrors('superficie');
    }

    public function test_sin_autenticacion_se_rechazan_las_tres_escrituras_en_json(): void
    {
        $this->app['auth']->forgetGuards();
        $this->post('/api/lotes', [])->assertUnauthorized()->assertJsonStructure(['message']);
        $this->patch('/api/lotes/999999', [])->assertUnauthorized()->assertJsonStructure(['message']);
        $this->post('/api/actividades', [])->assertUnauthorized()->assertJsonStructure(['message']);
    }

    public function test_actividad_incompatible_y_detalle_de_riego_validado_sin_prohibir_repeticiones(): void
    {
        $lote = $this->crearLote();
        $datos = $this->datosActividad($lote);
        $cosecha = TipoActividad::firstOrCreate(['nombre' => 'Cosecha'], ['descripcion' => 'Cosecha']);
        $this->postJson('/api/actividades', array_replace($datos, ['tipoactividadid' => $cosecha->tipoactividadid]))
            ->assertUnprocessable()->assertJsonValidationErrors('tipoactividadid');
        $lote->actividades()->update(['fechafin' => now()]);
        $lote->update(['estadolotetipoid' => \App\Support\EstadoLoteCatalogo::idPorSlug('en_crecimiento'), 'fechasiembra' => '2026-11-01']);
        $riego = TipoActividad::firstOrCreate(['nombre' => 'Riego'], ['descripcion' => 'Riego']);
        $datos['tipoactividadid'] = $riego->tipoactividadid;
        $this->postJson('/api/actividades', $datos)->assertUnprocessable()->assertJsonValidationErrors('detalle_actividad_json');
        $datos['detalle_actividad_json'] = json_encode(['riego' => ['key' => 'goteo', 'label' => 'Riego por goteo']]);
        $ids = [];
        foreach ([1, 2] as $vez) {
            $ids[] = $this->postJson('/api/actividades', $datos)->assertCreated()
                ->assertJsonPath('data.descripcion', 'Riego por goteo')->json('data.actividadid');
        }
        $this->assertNotSame($ids[0], $ids[1]);
        $this->assertSame(2, Actividad::whereIn('actividadid', $ids)->where('usuarioid', $this->trabajador->usuarioid)->count());
    }

    public function test_cambio_de_semilla_devuelve_cultivo_y_relacion_actualizados(): void
    {
        $lote = $this->crearLote();
        $semilla = $this->semilla->replicate();
        $semilla->nombre = 'Semilla de Tomate';
        $semilla->save();
        $cultivo = \App\Models\Cultivo::firstOrCreate(['nombre' => 'Tomate']);
        $this->patchJson('/api/lotes/'.$lote->loteid, ['insumosemillaid' => $semilla->insumoid])
            ->assertOk()->assertJsonPath('data.insumosemillaid', $semilla->insumoid)
            ->assertJsonPath('data.insumo_semilla.nombre', 'Semilla de Tomate')
            ->assertJsonPath('data.cultivoid', $cultivo->cultivoid)
            ->assertJsonPath('data.cultivo.nombre', 'Tomate');
        $this->assertSame($cultivo->cultivoid, $lote->fresh()->cultivoid);
        $this->assertSame($semilla->insumoid, $lote->fresh()->insumoSemilla->insumoid);
    }

    public function test_trabajador_inactivo_no_puede_recibir_asignacion(): void
    {
        $lote = $this->crearLote();
        $this->trabajador->update(['activo' => false]);
        $cantidad = Actividad::count();
        $this->postJson('/api/actividades', $this->datosActividad($lote))
            ->assertUnprocessable()->assertJsonValidationErrors('usuarioid');
        $this->assertSame($cantidad, Actividad::count());
    }
}
