<?php

namespace Tests\Feature;

use App\Models\{Actividad, Almacen, AlmacenMovimiento, Cultivo, Insumo, Lote, LoteInsumo, Prioridad, TipoActividad, TipoAlmacen, TipoInsumo, UnidadMedida, Usuario};
use App\Support\{EstadoLoteCatalogo, InventarioDecimal, LoteDefaults};
use Database\Seeders\{CatalogosOperacionAgricolaSeeder, RolePermissionSeeder};
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ApiCierreActividadTest extends TestCase
{
    use RefreshDatabase;

    private Usuario $jefe;
    private Usuario $operario;
    private Usuario $otro;
    private Insumo $insumo;
    private Almacen $almacen;
    private Actividad $actividad;
    private string $imagen;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        Storage::fake('local');
        Storage::fake('public');
        $foto = UploadedFile::fake()->image('foto.png', 8, 8);
        $this->imagen = file_get_contents($foto->getRealPath());
        $this->jefe = $this->usuario('jefe_agricultor', 'jefe');
        $this->operario = $this->usuario('agricultor', 'operario', $this->jefe->usuarioid);
        $this->otro = $this->usuario('agricultor', 'otro', $this->jefe->usuarioid);
        $unidad = UnidadMedida::firstOrCreate(['nombre' => 'Kilogramo'], ['abreviatura' => 'kg', 'categoria' => 'peso']);
        $this->almacen = Almacen::create(['nombre' => 'Almacén campo', 'ubicacion' => 'Parcela', 'capacidad' => 1000,
            'unidadmedidaid' => $unidad->unidadmedidaid, 'tipoalmacenid' => TipoAlmacen::firstOrCreate(['nombre' => 'Agrícola'])->tipoalmacenid,
            'ambito' => 'agricola', 'activo' => true, 'responsable_usuarioid' => $this->jefe->usuarioid]);
        $this->insumo = Insumo::create(['nombre' => 'Fertilizante prueba', 'almacenid' => $this->almacen->almacenid,
            'unidadmedidaid' => $unidad->unidadmedidaid, 'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Fertilizantes'])->tipoinsumoid, 'stock' => '10.000000']);
        $lote = Lote::create(['usuarioid' => $this->jefe->usuarioid, 'nombre' => 'Lote cierre', 'superficie' => 1,
            'unidadsuperficieid' => LoteDefaults::unidadHectareaId(), 'cultivoid' => Cultivo::firstOrCreate(['nombre' => 'Papa'])->cultivoid,
            'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('en_crecimiento')]);
        $prioridad = Prioridad::firstOrCreate(['nombre' => 'Media'])->prioridadid;
        Actividad::create(['loteid' => $lote->loteid, 'usuarioid' => $this->operario->usuarioid, 'descripcion' => 'Siembra previa',
            'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => 'Siembra'])->tipoactividadid,
            'prioridadid' => $prioridad, 'fechainicio' => now()->subDays(2), 'fechafin' => now()->subDay(), 'orden_secuencia' => 1]);
        $this->actividad = Actividad::create(['loteid' => $lote->loteid, 'usuarioid' => $this->operario->usuarioid, 'descripcion' => 'Fertilización asignada',
            'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => 'Fertilización'])->tipoactividadid,
            'prioridadid' => $prioridad, 'fechainicio' => now(), 'orden_secuencia' => 2, 'observaciones' => 'Plan original',
            'detalle_json' => json_encode(['modo' => 'insumos', 'stock_aplicado' => false, 'insumos' => [$this->consumo()]])]);
        Sanctum::actingAs($this->operario);
    }

    private function usuario(string $rol, string $nombre, ?int $supervisor = null): Usuario
    {
        $u = Usuario::create(['nombre' => $nombre, 'apellido' => 'Cierre', 'email' => $nombre.'@edt33.test', 'nombreusuario' => $nombre,
            'passwordhash' => bcrypt('prueba123'), 'role' => $rol, 'activo' => true, 'supervisor_usuarioid' => $supervisor,
            'fecharegistro' => now(), 'fechamodificacion' => now()]);
        $u->syncRoles([$rol]);
        return $u;
    }

    private function consumo(): array
    {
        return ['insumoid' => $this->insumo->insumoid, 'almacenid' => $this->almacen->almacenid, 'cantidad' => '2.500'];
    }

    private function datos(): array
    {
        return ['resultado' => 'Aplicación uniforme realizada', 'evidencia_foto' => UploadedFile::fake()->createWithContent('foto.png', $this->imagen), 'consumos' => [$this->consumo()]];
    }

    private function cerrar(array $cambios = [])
    {
        return $this->post('/api/actividades/'.$this->actividad->actividadid.'/cerrar', array_replace($this->datos(), $cambios), ['Accept' => 'application/json']);
    }

    private function stock(): string
    {
        return InventarioDecimal::texto(InventarioDecimal::unidades($this->insumo->fresh()->getRawOriginal('stock')));
    }

    public function test_cierre_persiste_y_se_consulta_en_web_y_api_con_foto_autorizada(): void
    {
        $r = $this->cerrar()->assertOk()->assertJsonPath('data.resultado', 'Aplicación uniforme realizada')
            ->assertJsonPath('data.usuarioid_ejecutor', $this->operario->usuarioid)->assertJsonPath('data.completada', true)->assertJsonPath('data.consumos.0.cantidad', '2.500');
        $this->assertSame('7.500000', $this->stock());
        $this->assertDatabaseHas('loteinsumo', ['actividadid' => $this->actividad->actividadid, 'insumoid' => $this->insumo->insumoid, 'cantidadusada' => 2.5]);
        $this->assertDatabaseHas('almacen_movimiento', ['referencia' => 'ACT-'.$this->actividad->actividadid, 'almacenid' => $this->almacen->almacenid, 'cantidad' => 2.5]);
        $a = $this->actividad->fresh();
        $this->assertSame('Plan original', $a->observaciones);
        $this->assertNotNull($a->fechafin);
        Storage::disk('local')->assertExists($a->evidencia_foto_path);
        $this->getJson($r->json('data.evidencia_foto_url'))->assertOk();
        $this->getJson('/api/actividades/'.$a->actividadid)->assertOk()->assertJsonPath('data.resultado', 'Aplicación uniforme realizada');
        $this->actingAs($this->operario, 'web')->get(route('lotes.trazabilidad', $a->loteid))->assertOk()->assertSee('Aplicación uniforme realizada')->assertSee('2.500');
        Sanctum::actingAs($this->otro);
        $this->getJson('/api/actividades/'.$a->actividadid.'/evidencia')->assertNotFound();
    }

    public function test_reintento_no_duplica_y_cambio_confirmado_es_conflicto(): void
    {
        $this->cerrar()->assertOk();
        $fecha = $this->actividad->fresh()->fechafin->toISOString();
        $foto = $this->actividad->fresh()->evidencia_foto_path;
        $this->cerrar(['consumos' => [array_replace($this->consumo(), ['cantidad' => '2.5'])]])->assertOk();
        $this->cerrar(['resultado' => 'Diferente'])->assertConflict();
        $this->assertSame('7.500000', $this->stock());
        $this->assertSame($fecha, $this->actividad->fresh()->fechafin->toISOString());
        $this->assertSame($foto, $this->actividad->fresh()->evidencia_foto_path);
        $this->assertCount(1, Storage::disk('local')->allFiles());
        $this->assertSame(1, LoteInsumo::where('actividadid', $this->actividad->actividadid)->count());
        $this->assertSame(1, AlmacenMovimiento::where('referencia', 'ACT-'.$this->actividad->actividadid)->count());
    }

    public function test_stock_duplicados_y_precision_invalidos_no_dejan_escrituras(): void
    {
        foreach (['0', '-1', '0.0001', '11.000'] as $cantidad) {
            $this->cerrar(['consumos' => [array_replace($this->consumo(), ['cantidad' => $cantidad])]])->assertUnprocessable()->assertJsonValidationErrors('consumos.0.cantidad');
        }
        $this->cerrar(['consumos' => [$this->consumo(), $this->consumo()]])->assertUnprocessable()->assertJsonValidationErrors('consumos.0.insumoid');
        $this->assertSame('10.000000', $this->stock());
        $this->assertNull($this->actividad->fresh()->fechafin);
        $this->assertDatabaseCount('loteinsumo', 0);
        $this->assertDatabaseCount('almacen_movimiento', 0);
        $this->assertCount(0, Storage::disk('local')->allFiles());
    }

    public function test_autenticacion_asignacion_campos_protegidos_e_imagen_real(): void
    {
        foreach ([$this->jefe, $this->otro] as $u) {
            Sanctum::actingAs($u);
            $this->cerrar()->assertForbidden();
        }
        Sanctum::actingAs($this->operario);
        $this->cerrar(['resultado' => ''])->assertUnprocessable()->assertJsonValidationErrors('resultado');
        $this->cerrar(['fechafin' => '2026-11-15'])->assertUnprocessable()->assertJsonValidationErrors('fechafin');
        $this->cerrar(['evidencia_foto' => UploadedFile::fake()->createWithContent('engano.jpg', '<?php echo 1;')])->assertUnprocessable()->assertJsonValidationErrors('evidencia_foto');
        $this->app['auth']->forgetGuards();
        $this->cerrar()->assertUnauthorized();
    }

    public function test_fallo_despues_de_foto_revierte_stock_consumos_y_limpia_archivo(): void
    {
        $dispatcher = clone Actividad::getEventDispatcher();
        Actividad::updating(function ($a) { if ($a->isDirty('fechafin')) throw new \RuntimeException('Fallo de prueba'); });
        try { $this->cerrar()->assertStatus(500)->assertJsonPath('message', 'No se pudo cerrar la actividad. No se confirmaron cambios.'); }
        finally { Actividad::setEventDispatcher($dispatcher); }
        $this->assertNull($this->actividad->fresh()->fechafin);
        $this->assertSame('10.000000', $this->stock());
        $this->assertDatabaseCount('loteinsumo', 0);
        $this->assertDatabaseCount('almacen_movimiento', 0);
        $this->assertCount(0, Storage::disk('local')->allFiles());
    }

    public function test_web_usa_mismo_servicio_y_api_no_reabre_el_cierre(): void
    {
        $this->actingAs($this->operario, 'web')->post(route('actividades.marcar-realizada', $this->actividad), $this->datos())->assertRedirect()->assertSessionHasNoErrors();
        $this->assertSame('7.500000', $this->stock());
        Sanctum::actingAs($this->jefe);
        $this->patchJson('/api/actividades/'.$this->actividad->actividadid, ['fechafin' => null])->assertConflict();
        $this->assertNotNull($this->actividad->fresh()->fechafin);
    }

    public function test_modelos_obsoletos_no_pierden_incrementos_ni_generan_stock_negativo(): void
    {
        $copia = $this->insumo->fresh();
        $this->insumo->incrementarStock('2.000');
        $copia->decrementarStock('2.500');
        $this->assertSame('9.500000', $this->stock());
        try { $copia->decrementarStock('10.000'); $this->fail('No debe permitir stock negativo.'); }
        catch (\Illuminate\Validation\ValidationException $e) { $this->assertSame('9.500000', $this->stock()); }
    }

    public function test_jefe_puede_reasignar_responsable_pendiente_y_cerrar_si_se_la_asigna(): void
    {
        // En web el jefe puede reasignar a otro trabajador de su equipo y luego a sí mismo.
        $this->actingAs($this->jefe, 'web')
            ->patch(route('actividades.reasignar-responsable', $this->actividad), [
                'usuarioid' => $this->otro->usuarioid,
            ])
            ->assertRedirect()
            ->assertSessionHas('success');
        $this->assertSame((int) $this->otro->usuarioid, (int) $this->actividad->fresh()->usuarioid);

        // En API el jefe se la reasigna a sí mismo.
        Sanctum::actingAs($this->jefe);
        $this->patchJson('/api/actividades/'.$this->actividad->actividadid, [
            'usuarioid' => $this->jefe->usuarioid,
        ])->assertOk();
        $this->assertSame((int) $this->jefe->usuarioid, (int) $this->actividad->fresh()->usuarioid);

        // Al estar asignada al propio jefe, ahora sí puede cerrarla con evidencia.
        $this->cerrar()->assertOk();
        $this->assertNotNull($this->actividad->fresh()->fechafin);

        // Una vez cerrada, ya no se puede reasignar el responsable.
        $this->patchJson('/api/actividades/'.$this->actividad->actividadid, [
            'usuarioid' => $this->operario->usuarioid,
        ])->assertConflict();
    }

    public function test_api_insumos_excluye_legacy_sin_almacen_y_siembra_fija_semilla_del_lote(): void
    {
        $unidadId = $this->insumo->unidadmedidaid;
        $tipoSemilla = TipoInsumo::firstOrCreate(['nombre' => 'Material de Siembra'])->tipoinsumoid;

        $legacy = Insumo::create([
            'nombre' => 'Semilla Legacy Sin Almacen',
            'almacenid' => null,
            'unidadmedidaid' => $unidadId,
            'tipoinsumoid' => $tipoSemilla,
            'stock' => '50.000000',
        ]);
        $semillaPapa = Insumo::create([
            'nombre' => 'Semilla de Papa',
            'almacenid' => $this->almacen->almacenid,
            'unidadmedidaid' => $unidadId,
            'tipoinsumoid' => $tipoSemilla,
            'stock' => '100.000000',
        ]);
        $semillaTomate = Insumo::create([
            'nombre' => 'Semilla de Tomate',
            'almacenid' => $this->almacen->almacenid,
            'unidadmedidaid' => $unidadId,
            'tipoinsumoid' => $tipoSemilla,
            'stock' => '100.000000',
        ]);

        Sanctum::actingAs($this->jefe);
        $idsVisibles = collect($this->getJson('/api/insumos')->assertOk()->json())->pluck('insumoid')->all();
        $this->assertNotContains($legacy->insumoid, $idsVisibles);
        $this->assertContains($semillaPapa->insumoid, $idsVisibles);

        $loteSiembra = Lote::create([
            'usuarioid' => $this->jefe->usuarioid,
            'nombre' => 'Parcela Siembra Fija',
            'superficie' => 1,
            'unidadsuperficieid' => LoteDefaults::unidadHectareaId(),
            'cultivoid' => Cultivo::firstOrCreate(['nombre' => 'Papa'])->cultivoid,
            'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('planificado'),
            'insumosemillaid' => $semillaPapa->insumoid,
            'cantidad_semilla_planificada' => '12.500',
        ]);
        $siembra = Actividad::create([
            'loteid' => $loteSiembra->loteid,
            'usuarioid' => $this->jefe->usuarioid,
            'descripcion' => 'Siembra Papa',
            'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => 'Siembra'])->tipoactividadid,
            'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->prioridadid,
            'fechainicio' => now(),
            'orden_secuencia' => 1,
        ]);

        // El detalle API expone la semilla planificada del lote.
        $this->getJson('/api/actividades/'.$siembra->actividadid)
            ->assertOk()
            ->assertJsonPath('data.lote.insumosemillaid', $semillaPapa->insumoid)
            ->assertJsonPath('data.lote.insumo_semilla.nombre', 'Semilla de Papa');

        // Intentar cerrar con otra semilla (Tomate) se rechaza.
        $foto = UploadedFile::fake()->createWithContent('cierre.png', $this->imagen);
        $this->post('/api/actividades/'.$siembra->actividadid.'/cerrar', [
            'resultado' => 'Siembra realizada',
            'evidencia_foto' => $foto,
            'consumos' => [[
                'insumoid' => $semillaTomate->insumoid,
                'almacenid' => $this->almacen->almacenid,
                'cantidad' => '10',
            ]],
        ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('consumos.0.insumoid');

        // Cerrar con la semilla planificada del lote funciona.
        $foto2 = UploadedFile::fake()->createWithContent('cierre2.png', $this->imagen);
        $this->post('/api/actividades/'.$siembra->actividadid.'/cerrar', [
            'resultado' => 'Siembra realizada con semilla de papa',
            'evidencia_foto' => $foto2,
            'consumos' => [[
                'insumoid' => $semillaPapa->insumoid,
                'almacenid' => $this->almacen->almacenid,
                'cantidad' => '12.5',
            ]],
        ], ['Accept' => 'application/json'])->assertOk();
    }
}
