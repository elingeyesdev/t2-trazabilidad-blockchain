<?php

namespace Tests\Feature;

use App\Models\Actividad;
use App\Models\Almacen;
use App\Models\Insumo;
use App\Models\Lote;
use App\Models\LoteInsumo;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use App\Models\TipoAlmacen;
use App\Models\TipoInsumo;
use App\Models\TipoVehiculo;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Services\LoteUbicacionTerrestreService;
use App\Support\ActividadPermisos;
use App\Support\ActividadSecuenciaService;
use App\Support\LoteTrazabilidadService;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

class FlujoInicioLoteWebTest extends TestCase
{
    use RefreshDatabase;

    private Usuario $admin;

    private Usuario $jefe;

    private Usuario $agricultor;

    private Usuario $suplente;

    private Usuario $ajeno;

    private Insumo $semilla;

    private Almacen $almacen;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        Storage::fake('local');
        Storage::fake('public');
        $this->admin = $this->usuario('admin', 'admin');
        $this->jefe = $this->usuario('jefe_agricultor', 'jefe');
        $this->agricultor = $this->usuario('agricultor', 'agricultor', $this->jefe->usuarioid);
        $this->suplente = $this->usuario('agricultor', 'suplente', $this->jefe->usuarioid);
        $otroJefe = $this->usuario('jefe_agricultor', 'otroJefe');
        $this->ajeno = $this->usuario('agricultor', 'ajeno', $otroJefe->usuarioid);
        $this->almacen = Almacen::create(['nombre' => 'Almacén propio', 'capacidad' => 10000,
            'unidadmedidaid' => UnidadMedida::firstOrCreate(['nombre' => 'Kilogramo'], ['abreviatura' => 'kg', 'categoria' => 'peso'])->unidadmedidaid,
            'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Agrícola'])->tipoalmacenid,
            'ambito' => 'agricola', 'activo' => true, 'responsable_usuarioid' => $this->jefe->usuarioid]);
        $this->semilla = Insumo::create(['nombre' => 'Semilla de Papa', 'stock' => 10000,
            'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Material de Siembra'])->tipoinsumoid,
            'unidadmedidaid' => UnidadMedida::firstOrCreate(['nombre' => 'Kilogramo'], ['abreviatura' => 'kg', 'categoria' => 'peso'])->unidadmedidaid,
            'almacenid' => $this->almacen->almacenid]);
        $this->mock(LoteUbicacionTerrestreService::class)->shouldReceive('validarMarcador')->andReturn(['ok' => true]);
    }

    private function usuario(string $rol, string $nombre, ?int $supervisor = null): Usuario
    {
        $u = Usuario::create(['nombre' => $nombre, 'apellido' => 'Flujo', 'email' => $nombre.'@inicio.test',
            'nombreusuario' => $nombre, 'passwordhash' => bcrypt('prueba123'), 'role' => $rol, 'activo' => true,
            'estado_cuenta' => 'aprobado', 'supervisor_usuarioid' => $supervisor,
            'fecharegistro' => now(), 'fechamodificacion' => now()]);
        $u->syncRoles([$rol]);

        return $u;
    }

    private function datos(string $terreno = 'requiere_preparacion'): array
    {
        return ['solicitud_registro_id' => (string) Str::uuid(), 'nombre' => 'Parcela propia', 'superficie' => 1,
            'insumosemillaid' => $this->semilla->insumoid, 'cantidad_semilla_planificada' => 1,
            'preparacion_terreno' => $terreno, 'agricultor_inicial_usuarioid' => $this->agricultor->usuarioid,
            'latitud' => -17.7, 'longitud' => -63.1];
    }

    private function crear(string $terreno = 'requiere_preparacion'): Lote
    {
        $this->actingAs($this->jefe)->post(route('lotes.store'), $this->datos($terreno))
            ->assertSessionHasNoErrors()->assertRedirect(route('lotes.index'));

        return Lote::latest('loteid')->firstOrFail();
    }

    private function foto(): UploadedFile
    {
        return UploadedFile::fake()->image('trabajo.png', 8, 8);
    }

    private function cerrar(Actividad $actividad, array $extra = [], ?Usuario $actor = null)
    {
        return $this->actingAs($actor ?? $this->agricultor)->post(route('actividades.marcar-realizada', $actividad), $extra + [
            'resultado' => 'Trabajo realizado y registrado', 'evidencia_foto' => $this->foto(),
            'return' => route('lotes.trazabilidad', $actividad->loteid, absolute: false),
        ]);
    }

    private function actividad(Lote $lote, string $tipo, int $orden): Actividad
    {
        return Actividad::create(['loteid' => $lote->loteid, 'usuarioid' => $this->agricultor->usuarioid,
            'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => $tipo])->tipoactividadid,
            'descripcion' => $tipo, 'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->prioridadid,
            'fechainicio' => now(), 'orden_secuencia' => $orden]);
    }

    public function test_administrador_navega_desde_menu_y_registra_vehiculo_con_permisos_existentes(): void
    {
        $this->actingAs($this->admin)->get(route('dashboard'))->assertOk()->assertSee(route('envios.vehiculos'), false);
        $this->get(route('envios.vehiculos'))->assertOk()->assertSee(route('envios.vehiculos.create'), false);
        $this->get(route('envios.vehiculos.create'))->assertOk()->assertSee('Registrar vehículo');
        $tipo = TipoVehiculo::create(['nombre' => 'Camión del recorrido', 'activo' => true, 'capacidad_kg' => 1000]);
        $this->post(route('envios.vehiculos.store'), ['placa' => 'WEB-2601', 'tipovehiculoid' => $tipo->tipovehiculoid,
            'ambito_flota' => 'agricola', 'activo' => 1])->assertSessionHasNoErrors()->assertRedirect();
        $this->assertDatabaseHas('vehiculo', ['placa' => 'WEB-2601']);
        $this->admin->roles()->first()->revokePermissionTo('vehiculos.create');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();
        $this->actingAs($this->admin->fresh())->get(route('envios.vehiculos'))->assertOk()->assertDontSee(route('envios.vehiculos.create'), false);
        $this->get(route('envios.vehiculos.create'))->assertForbidden();
        $this->post(route('envios.vehiculos.store'), ['placa' => 'NO-AUTORIZADO'])->assertForbidden();
        $this->actingAs($this->agricultor)->get(route('envios.vehiculos.create'))->assertForbidden();
    }

    public function test_preparacion_primero_y_siembra_automatica_despues_del_cierre_desde_trazabilidad(): void
    {
        $lote = $this->crear();
        $this->assertSame($this->jefe->usuarioid, $lote->usuarioid);
        $preparacion = $lote->actividades()->sole();
        $this->assertSame($this->agricultor->usuarioid, $preparacion->usuarioid);
        $this->assertSame('Preparación del terreno', $preparacion->tipoActividad->nombre);
        $this->assertNull(app(LoteTrazabilidadService::class)->actividadSiembraPendiente($lote));
        $this->post(route('actividades.cancelar-preparacion', $preparacion), ['motivo' => 'Intento antes de sembrar'])->assertConflict();
        $vista = $this->actingAs($this->agricultor)->get(route('lotes.trazabilidad', $lote))->assertOk();
        $this->assertContains($preparacion->actividadid, $vista->viewData('actividades_marcables_ids'));
        $this->get(route('lotes.siembra.create', $lote))->assertRedirect()->assertSessionHas('error');
        $this->cerrar($preparacion)->assertSessionHasNoErrors()->assertRedirect();
        $siembra = app(LoteTrazabilidadService::class)->actividadSiembraPendiente($lote->fresh());
        $this->assertNotNull($siembra);
        $this->assertSame($this->agricultor->usuarioid, $siembra->usuarioid);
        $this->assertTrue(ActividadPermisos::puedeMarcarCompletada($this->agricultor, $siembra));
        $this->cerrar($siembra, ['consumos' => [['insumoid' => $this->semilla->insumoid, 'almacenid' => $this->almacen->almacenid, 'cantidad' => '1.000']]])
            ->assertSessionHasNoErrors()->assertRedirect();
        $this->assertSame('en_crecimiento', app(LoteTrazabilidadService::class)->resolverFaseActual($lote->fresh()));
        $this->assertEquals(9999, $this->semilla->fresh()->stock);
        $this->assertSame(2, $lote->actividades()->count());
    }

    public function test_terreno_ya_preparado_asigna_siembra_y_el_agricultor_la_cierra(): void
    {
        $lote = $this->crear('ya_preparado');
        $siembra = $lote->actividades()->sole();
        $this->assertSame('Siembra', $siembra->tipoActividad->nombre);
        $this->assertFalse($lote->preparacion_requerida);
        $this->assertSame('siembra', app(LoteTrazabilidadService::class)->resolverFaseActual($lote));
        $vista = $this->actingAs($this->agricultor)->get(route('lotes.trazabilidad', $lote))->assertOk();
        $this->assertContains($siembra->actividadid, $vista->viewData('actividades_marcables_ids'));
        $this->get(route('lotes.siembra.completar', $lote))->assertOk();
        $this->cerrar($siembra)->assertSessionHasNoErrors()->assertRedirect();
        $this->assertNotNull($siembra->fresh()->fechafin);
        $this->assertSame(1, $lote->actividades()->count());
    }

    public function test_historial_preparacion_conserva_numero_al_cerrar_y_crea_siembra_automaticamente(): void
    {
        $lote = $this->crear();
        $preparacion = $lote->actividades()->sole();
        $url = route('lotes.trazabilidad', $lote);
        $antes = $this->actingAs($this->agricultor)->get($url)->assertOk()->viewData('trazabilidad');
        $evento = $antes->firstWhere('actividadid', $preparacion->actividadid);
        $this->assertSame('En planificación', $antes->first()['titulo']);
        $this->assertSame(1, $antes->first()['paso']);
        $this->assertSame(2, $evento['paso']);
        $this->assertSame('preparacion', $evento['fase']);
        $this->assertSame('Preparación', $evento['fase_label']);
        $this->assertFalse($evento['completada']);

        $this->travel(1)->minutes();
        $this->cerrar($preparacion)->assertSessionHasNoErrors()->assertRedirect();
        $siembra = app(LoteTrazabilidadService::class)->actividadSiembraPendiente($lote->fresh());
        $this->assertNotNull($siembra);
        $this->assertSame($this->agricultor->usuarioid, $siembra->usuarioid);
        $vista = $this->get($url)->assertOk()->assertSee('Completada');
        $despues = $vista->viewData('trazabilidad');
        $this->assertSame([1, 2, 3], $despues->pluck('paso')->all());
        $this->assertSame(['En planificación', 'Preparación del terreno', 'Siembra de Papa'], $despues->pluck('titulo')->all());
        $this->assertSame(2, $despues->firstWhere('actividadid', $preparacion->actividadid)['paso']);
        $this->assertTrue($despues->firstWhere('actividadid', $preparacion->actividadid)['completada']);
        $this->assertContains($siembra->actividadid, $vista->viewData('actividades_marcables_ids'));

        $filtrado = $this->get($url.'?fase=preparacion')->assertOk()->viewData('trazabilidad');
        $this->assertSame(2, $filtrado->firstWhere('actividadid', $preparacion->actividadid)['paso']);
        $this->assertSame(2, $lote->actividades()->count());
    }

    public function test_historial_fresa_preparacion_antes_de_siembra_y_empates_por_id_sin_cambiar_registros(): void
    {
        $lote = $this->crear('ya_preparado');
        $siembra = $lote->actividades()->sole();
        $this->cerrar($siembra)->assertSessionHasNoErrors();
        $lote->update(['nombre' => 'Fresa - Parcela 01', 'preparacion_requerida' => null]);
        $this->travel(1)->minutes();
        $preparacion = $this->actividad($lote, 'Preparación del terreno', 2);
        $riego1 = $this->actividad($lote, 'Riego', 3);
        $riego2 = $this->actividad($lote, 'Riego', 4);
        $riego2->update(['fechainicio' => $riego1->fechainicio]);
        $capturar = fn () => [$lote->fresh()->getAttributes(), $lote->actividades()->orderBy('actividadid')->get()->map->getAttributes()->all(),
            LoteInsumo::where('loteid', $lote->loteid)->get()->map->getAttributes()->all(), $this->semilla->fresh()->stock];
        $antes = $capturar();

        foreach ([$this->agricultor, $this->jefe, $this->admin] as $usuario) {
            $vista = $this->actingAs($usuario)->get(route('lotes.trazabilidad', $lote))->assertOk();
            $eventos = $vista->viewData('trazabilidad');
            $this->assertSame(['En planificación', 'Preparación del terreno', 'Siembra de Papa', 'Riego', 'Riego'], $eventos->pluck('titulo')->all());
            $this->assertSame([1, 2, 3, 4, 5], $eventos->pluck('paso')->all());
            $this->assertSame([$preparacion->actividadid, $siembra->actividadid, $riego1->actividadid, $riego2->actividadid], $eventos->pluck('actividadid')->filter()->values()->all());
            $this->assertSame('preparacion', $eventos->firstWhere('actividadid', $preparacion->actividadid)['fase']);
            $xpath = new \DOMXPath(tap(new \DOMDocument, function ($dom) use ($vista) {
                @$dom->loadHTML('<?xml encoding="UTF-8">'.$vista->getContent());
            }));
            $numeros = array_map(fn ($nodo) => (int) $nodo->textContent, iterator_to_array($xpath->query('//*[contains(concat(" ", normalize-space(@class), " "), " trace-number ")]')));
            $this->assertSame([1, 2, 3, 4, 5], $numeros);
        }

        $this->assertSame($antes, $capturar());
    }

    public function test_modal_cierre_muestra_resultado_obligatorio_y_errores_al_reintentar(): void
    {
        $lote = $this->crear();
        $preparacion = $lote->actividades()->sole();
        $url = route('lotes.trazabilidad', $lote);
        $vista = $this->actingAs($this->agricultor)->get($url)->assertOk()->assertSee('Resultado de la actividad');
        $xpath = $this->xpathModal($vista->getContent());
        $campo = $xpath->query('//form[@id="formCompletarEvidencia"]//textarea[@name="resultado"]')->item(0);
        $this->assertNotNull($campo);
        $this->assertTrue($campo->hasAttribute('required'));
        $this->assertSame('250', $campo->getAttribute('maxlength'));

        foreach (['' => 'Describe el resultado de la actividad.', str_repeat('x', 251) => 'El resultado de la actividad no puede superar los 250 caracteres.'] as $resultado => $mensaje) {
            $this->from($url)->post(route('actividades.marcar-realizada', $preparacion), [
                'resultado' => $resultado, 'evidencia_foto' => $this->foto(), 'scroll_to' => 'historial-eventos',
            ])->assertRedirect($url.'#historial-eventos')->assertSessionHasErrors('resultado')
                ->assertSessionHas('actividad_cierre_error_id', $preparacion->actividadid);
            $error = $this->get($url)->assertOk()->assertSee($mensaje);
            $xpath = $this->xpathModal($error->getContent());
            $form = $xpath->query('//form[@id="formCompletarEvidencia"]')->item(0);
            $alerta = $xpath->query('//*[@id="actividadModalErrores"]')->item(0);
            $campo = $xpath->query('//textarea[@id="actividadModalResultado"]')->item(0);
            $this->assertSame(route('actividades.marcar-realizada', $preparacion), $form->getAttribute('action'));
            $this->assertFalse($alerta->hasAttribute('hidden'));
            $this->assertStringContainsString($mensaje, $alerta->textContent);
            $this->assertSame($resultado, $campo->textContent);
            $this->assertNull($preparacion->fresh()->fechafin);
            $this->assertSame(1, $lote->actividades()->count());
        }
        $this->assertSame([], Storage::disk('local')->allFiles());
    }

    public function test_modal_cierre_conserva_resultado_si_falta_la_fotografia(): void
    {
        $lote = $this->crear();
        $preparacion = $lote->actividades()->sole();
        $url = route('lotes.trazabilidad', $lote);
        $resultado = 'Terreno nivelado y preparado para la siembra.';
        $this->actingAs($this->agricultor)->from($url)->post(route('actividades.marcar-realizada', $preparacion), [
            'resultado' => $resultado, 'scroll_to' => 'historial-eventos',
        ])->assertSessionHasErrors('evidencia_foto')->assertSessionHas('actividad_cierre_error_id', $preparacion->actividadid);
        $vista = $this->get($url)->assertOk()->assertSee('Debe subir una foto del trabajo realizado.')
            ->assertSee('vuelva a seleccionar la foto');
        $xpath = $this->xpathModal($vista->getContent());
        $this->assertSame($resultado, $xpath->query('//textarea[@id="actividadModalResultado"]')->item(0)->textContent);
        $this->assertFalse($xpath->query('//*[@id="actividadModalErrores"]')->item(0)->hasAttribute('hidden'));
        $this->assertNull($preparacion->fresh()->fechafin);
    }

    public function test_modal_cierre_preparacion_con_resultado_y_foto_aparece_completada_y_habilita_siembra(): void
    {
        $lote = $this->crear();
        $preparacion = $lote->actividades()->sole();
        $resultado = str_repeat('a', 250);
        $this->actingAs($this->suplente)->post(route('actividades.marcar-realizada', $preparacion), [
            'resultado' => $resultado, 'evidencia_foto' => $this->foto(),
        ])->assertForbidden();
        $this->actingAs($this->agricultor)->getJson(route('actividades.resumen-completar', $preparacion))->assertOk();
        $this->actingAs($this->agricultor)->post(route('actividades.marcar-realizada', $preparacion), [
            'resultado' => $resultado, 'evidencia_foto' => $this->foto(), 'scroll_to' => 'historial-eventos',
        ])->assertRedirect(route('lotes.trazabilidad', $lote).'#historial-eventos')->assertSessionHasNoErrors()->assertSessionHas('success');
        $preparacion->refresh();
        $this->assertNotNull($preparacion->fechafin);
        $this->assertSame($this->agricultor->usuarioid, $preparacion->usuarioid_ejecutor);
        $this->assertSame($resultado, json_decode($preparacion->detalle_json, true)['cierre']['resultado']);
        Storage::disk('local')->assertExists($preparacion->evidencia_foto_path);
        $vista = $this->get(route('lotes.trazabilidad', $lote))->assertOk()->assertSee('Completada')->assertSee($resultado);
        $evento = collect($vista->viewData('trazabilidad'))->firstWhere('actividadid', $preparacion->actividadid);
        $this->assertTrue($evento['completada']);
        $this->assertSame('siembra', $vista->viewData('fase_actual'));
        $this->assertTrue($vista->viewData('puede_completar_siembra'));
        $this->get(route('lotes.siembra.completar', $lote))->assertOk();
        $this->assertSame(2, $lote->actividades()->count());
    }

    private function xpathModal(string $html): \DOMXPath
    {
        $estadoLibxml = libxml_use_internal_errors(true);
        $documento = new \DOMDocument;
        $documento->loadHTML('<?xml encoding="UTF-8">'.$html);
        libxml_clear_errors();
        libxml_use_internal_errors($estadoLibxml);

        return new \DOMXPath($documento);
    }

    public function test_reintento_del_formulario_no_duplica_lote_ni_primera_tarea(): void
    {
        foreach (['requiere_preparacion', 'ya_preparado'] as $terreno) {
            $datos = $this->datos($terreno);
            $antes = Lote::count();
            $this->actingAs($this->jefe)->post(route('lotes.store'), $datos)->assertSessionHasNoErrors();
            $this->post(route('lotes.store'), $datos)->assertSessionHasNoErrors();
            $this->assertSame($antes + 1, Lote::count());
            $this->assertSame(1, Lote::latest('loteid')->first()->actividades()->count());
            $this->post(route('lotes.store'), array_replace($datos, ['nombre' => 'Otro nombre']))->assertConflict();
        }
    }

    public function test_eleccion_y_agricultor_son_obligatorios_y_solo_del_equipo_aprobado(): void
    {
        $datos = $this->datos();
        unset($datos['preparacion_terreno'], $datos['agricultor_inicial_usuarioid']);
        $this->actingAs($this->jefe)->post(route('lotes.store'), $datos)->assertSessionHasErrors(['preparacion_terreno', 'agricultor_inicial_usuarioid']);
        foreach ([$this->ajeno, $this->jefe, $this->admin] as $invalido) {
            $this->post(route('lotes.store'), array_replace($this->datos(), ['agricultor_inicial_usuarioid' => $invalido->usuarioid]))
                ->assertSessionHasErrors('agricultor_inicial_usuarioid');
        }
        $this->agricultor->update(['estado_cuenta' => 'pendiente']);
        $this->post(route('lotes.store'), $this->datos())->assertSessionHasErrors('agricultor_inicial_usuarioid');
        $this->assertDatabaseCount('lote', 0);
    }

    public function test_jefe_tiene_selector_y_nueva_actividad_y_agricultor_no_puede_asignar(): void
    {
        $this->actingAs($this->jefe)->get(route('lotes.create'))->assertOk()
            ->assertSee('agricultor_inicial_usuarioid', false)->assertSee('El terreno requiere preparación')->assertSee('El terreno ya está preparado');
        $this->get(route('actividades.index'))->assertOk()->assertSee('Nueva actividad')->assertSee(route('actividades.create'), false);
        $this->get(route('actividades.create'))->assertOk()->assertSee('fecha_planificada', false);
        $this->actingAs($this->agricultor)->get(route('actividades.index'))->assertOk()->assertDontSee('Nueva actividad');
        $this->get(route('actividades.create'))->assertForbidden();
    }

    public function test_reasignacion_visible_solo_pendiente_y_servidor_rechaza_personas_ajenas(): void
    {
        $lote = $this->crear();
        $a = $lote->actividades()->sole();
        $this->actingAs($this->jefe)->get(route('actividades.index'))->assertOk()->assertSee(route('actividades.edit', $a), false);
        $this->get(route('actividades.show', $a))->assertOk()->assertSee('Reasignar actividad');
        $this->get(route('actividades.edit', $a))->assertOk();
        $datos = $a->only(['loteid', 'tipoactividadid', 'descripcion', 'prioridadid']) + ['usuarioid' => $this->ajeno->usuarioid];
        $this->put(route('actividades.update', $a), $datos)->assertSessionHasErrors('usuarioid');
        $this->put(route('actividades.update', $a), array_replace($datos, ['usuarioid' => $this->suplente->usuarioid]))->assertSessionHasNoErrors();
        $this->assertSame($this->suplente->usuarioid, $a->fresh()->usuarioid);
        $this->assertCount(1, json_decode($a->fresh()->detalle_json, true)['historial_asignaciones']);
        $this->assertFalse(ActividadPermisos::puedeMarcarCompletada($this->agricultor, $a->fresh()));
        $this->assertTrue(ActividadPermisos::puedeMarcarCompletada($this->suplente, $a->fresh()));
        $this->actingAs($this->agricultor)->put(route('actividades.update', $a), $datos)->assertForbidden();
        $this->cerrar($a, [], $this->suplente)->assertSessionHasNoErrors()->assertRedirect();
        $this->assertSame($this->suplente->usuarioid, app(LoteTrazabilidadService::class)->actividadSiembraPendiente($lote->fresh())->usuarioid);
        $antes = $a->fresh()->getAttributes();
        $this->actingAs($this->jefe)->get(route('actividades.edit', $a))->assertForbidden();
        $this->put(route('actividades.update', $a), $datos)->assertSessionHas('error');
        $this->assertSame($antes, $a->fresh()->getAttributes());
    }

    public function test_fresa_legacy_cancelar_preparacion_libera_riego_sin_tocar_siembra_evidencia_consumos(): void
    {
        $lote = $this->crear('ya_preparado');
        $siembra = $lote->actividades()->sole();
        $this->cerrar($siembra)->assertSessionHasNoErrors()->assertRedirect();
        $lote->update(['nombre' => 'Fresa - Parcela 01', 'preparacion_requerida' => null]);
        $consumo = LoteInsumo::where('actividadid', $siembra->actividadid)->sole();
        $preparacion = $this->actividad($lote, 'Preparación del terreno', 2);
        $riego = $this->actividad($lote, 'Riego', 3);
        $antes = [$siembra->fresh()->getAttributes(), $consumo->fresh()->getAttributes(), $this->semilla->fresh()->stock];
        $vista = $this->actingAs($this->agricultor)->get(route('lotes.trazabilidad', $lote))->assertOk();
        $this->assertNotContains($preparacion->actividadid, $vista->viewData('actividades_marcables_ids'));
        $this->assertNotContains($riego->actividadid, $vista->viewData('actividades_marcables_ids'));
        $this->cerrar($preparacion)->assertSessionHasErrors('actividadid');
        $this->post(route('actividades.cancelar-preparacion', $preparacion), ['motivo' => 'No corresponde'])->assertForbidden();
        $this->actingAs($this->jefe)->get(route('lotes.trazabilidad', $lote))->assertOk()->assertSee('Cancelar preparación incompatible');
        $this->post(route('actividades.cancelar-preparacion', $preparacion), [])->assertSessionHasErrors('motivo');
        $this->post(route('actividades.cancelar-preparacion', $preparacion), ['motivo' => 'Preparación pendiente incompatible: la siembra ya fue realizada.'])
            ->assertSessionHasNoErrors()->assertRedirect(route('lotes.trazabilidad', $lote));
        $this->assertNotNull($preparacion->fresh()->cancelada_en);
        $this->assertNull($preparacion->fresh()->fechafin);
        $this->assertSame($this->jefe->usuarioid, $preparacion->fresh()->cancelada_por_usuarioid);
        $cancelacion = $preparacion->fresh()->getAttributes();
        $this->post(route('actividades.cancelar-preparacion', $preparacion), ['motivo' => 'Preparación pendiente incompatible: la siembra ya fue realizada.'])->assertSessionHasNoErrors();
        $this->assertSame($cancelacion, $preparacion->fresh()->getAttributes());
        $this->patchJson('/api/actividades/'.$preparacion->actividadid, ['descripcion' => 'No debe cambiar'])->assertConflict();
        $this->deleteJson('/api/actividades/'.$preparacion->actividadid)->assertConflict();
        $this->assertSame($riego->actividadid, app(ActividadSecuenciaService::class)->siguientePendiente($lote->fresh())->actividadid);
        $vista = $this->actingAs($this->agricultor)->get(route('lotes.trazabilidad', $lote))->assertOk()->assertSee('Preparación cancelada')->assertSee('la siembra ya fue realizada');
        $this->assertContains($riego->actividadid, $vista->viewData('actividades_marcables_ids'));
        $this->getJson('/api/actividades/'.$preparacion->actividadid)->assertOk()
            ->assertJsonPath('data.estado_tarea', 'cancelada')->assertJsonPath('data.pendiente', false)->assertJsonPath('data.completada', false);
        $calendario = $this->getJson(route('actividades.calendario', ['start' => now()->startOfMonth()->toDateString(),
            'end' => now()->addMonth()->startOfMonth()->toDateString()]))->assertOk();
        $eventoCancelado = collect($calendario->json('eventos'))->firstWhere('id', (string) $preparacion->actividadid);
        $this->assertSame('Cancelada', $eventoCancelado['extendedProps']['estado']);
        $this->cerrar($riego)->assertSessionHasNoErrors()->assertRedirect();
        $this->assertSame($antes, [$siembra->fresh()->getAttributes(), $consumo->fresh()->getAttributes(), $this->semilla->fresh()->stock]);
        Storage::disk('local')->assertExists($siembra->fresh()->evidencia_foto_path);
    }

    public function test_crear_riego_solo_en_su_fase_y_lote_propio(): void
    {
        $lote = $this->crear();
        $riego = TipoActividad::firstOrCreate(['nombre' => 'Riego']);
        $datos = ['loteid' => $lote->loteid, 'tipoactividadid' => $riego->tipoactividadid,
            'usuarioid' => $this->agricultor->usuarioid, 'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->prioridadid,
            'fecha_planificada' => '2026-11-28', 'detalle_actividad_json' => json_encode(['modo' => 'riego', 'riego' => ['key' => 'goteo', 'label' => 'Goteo']])];
        $this->actingAs($this->jefe)->getJson(route('actividades.tipos-permitidos', ['loteid' => $lote->loteid]))->assertOk()->assertJsonMissing(['id' => $riego->tipoactividadid]);
        $this->post(route('actividades.store'), $datos)->assertSessionHas('error');
        $lote->update(['fechasiembra' => now()->toDateString()]);
        $this->getJson(route('actividades.tipos-permitidos', ['loteid' => $lote->loteid]))->assertOk()->assertJsonFragment(['id' => $riego->tipoactividadid]);
        $this->post(route('actividades.store'), $datos)->assertSessionHasNoErrors()->assertRedirect();
        $this->assertDatabaseHas('actividad', ['loteid' => $lote->loteid, 'tipoactividadid' => $riego->tipoactividadid,
            'usuarioid' => $this->agricultor->usuarioid, 'fecha_planificada' => '2026-11-28 00:00:00']);
        $this->actingAs($this->ajeno)->getJson(route('actividades.tipos-permitidos', ['loteid' => $lote->loteid]))->assertForbidden();
    }
}
