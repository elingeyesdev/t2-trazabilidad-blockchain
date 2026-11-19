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

class ApiConsultaEvidenciaActividadTest extends TestCase
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

    public function test_detalle_comparte_foto_ejecutor_cantidades_historicas_y_no_modifica_stock(): void
    {
        $this->cerrar()->assertOk();
        $a = $this->actividad->fresh();
        $this->insumo->unidadMedida->update(['abreviatura' => 'unidad cambiada']);
        $antes = [$this->stock(), LoteInsumo::count(), AlmacenMovimiento::count(), $a->getAttributes()];
        for ($i = 0; $i < 2; $i++) {
            $r = $this->getJson('/api/actividades/'.$a->actividadid)->assertOk()
                ->assertJsonPath('data.resultado', 'Aplicación uniforme realizada')
                ->assertJsonPath('data.responsable_cierre.usuarioid', $this->operario->usuarioid)
                ->assertJsonPath('data.responsable.usuarioid', $this->operario->usuarioid)
                ->assertJsonPath('data.fechafin', $a->fechafin->toJSON())
                ->assertJsonPath('data.evidencia_foto_path', null)
                ->assertJsonPath('data.evidencia_estado', 'disponible')
                ->assertJsonPath('data.consumos.0.cantidad', '2.500')
                ->assertJsonPath('data.consumos.0.unidad', 'kg')
                ->assertJsonPath('data.consumos.0.unidad_historica', true)
                ->assertJsonPath('data.consumos.0.almacenid', $this->almacen->almacenid);
            $this->assertStringNotContainsString('actividades_privadas/', $r->getContent());
            $foto = $this->getJson($r->json('data.evidencia_foto_url'))->assertOk();
            $this->assertSame($this->imagen, $foto->streamedContent());
        }
        $this->actingAs($this->operario, 'web')->get(route('actividades.show', $a))->assertOk()
            ->assertSee('Aplicación uniforme realizada')->assertSee('2.500')->assertSee('kg')
            ->assertSee('Responsable del cierre')->assertSee($a->fechafin->format('d/m/Y H:i'))
            ->assertSee(route('actividades.evidencia', $a), false)->assertDontSee('unidad cambiada');
        $this->assertSame($antes, [$this->stock(), LoteInsumo::count(), AlmacenMovimiento::count(), $a->fresh()->getAttributes()]);
    }

    public function test_dos_actividades_del_mismo_lote_no_comparten_fotos_ni_consumos(): void
    {
        $this->cerrar()->assertOk();
        $otra = $this->actividad->fresh()->replicate();
        $otra->descripcion = 'Trabajo segundo';
        $otra->save();
        $path = 'actividades_privadas/'.$otra->actividadid.'/segunda.png';
        Storage::disk('local')->put($path, 'bytes de otra evidencia');
        $otra->update(['evidencia_foto_path' => $path, 'detalle_json' => json_encode([
            'stock_aplicado' => true, 'cierre' => ['resultado' => 'Resultado exclusivo segundo'],
            'insumos' => [['insumoid' => $this->insumo->insumoid, 'nombre' => 'Insumo exclusivo segundo', 'cantidad' => '0.125', 'unidad' => 'kg', 'almacenid' => $this->almacen->almacenid]],
        ])]);
        $primera = $this->getJson('/api/actividades/'.$this->actividad->actividadid)->assertOk()->assertJsonCount(1, 'data.consumos')
            ->assertJsonPath('data.consumos.0.cantidad', '2.500')->assertDontSee('Resultado exclusivo segundo')->assertDontSee('0.125');
        $segunda = $this->getJson('/api/actividades/'.$otra->actividadid)->assertOk()->assertJsonCount(1, 'data.consumos')
            ->assertJsonPath('data.consumos.0.cantidad', '0.125')->assertDontSee('2.500')->assertDontSee('Aplicación uniforme realizada');
        $this->assertNotSame($primera->json('data.evidencia_foto_url'), $segunda->json('data.evidencia_foto_url'));
        $this->assertSame('bytes de otra evidencia', $this->getJson($segunda->json('data.evidencia_foto_url'))->assertOk()->streamedContent());
        $this->actingAs($this->operario, 'web')->get(route('actividades.show', $otra))->assertOk()
            ->assertSee('Resultado exclusivo segundo')->assertSee('0.125')->assertDontSee('2.500');
    }

    public function test_ausencias_y_pendiente_no_presentan_planificacion_como_cierre(): void
    {
        $a = $this->actividad;
        foreach ([false, true] as $cerrada) {
            $a->update(['fechafin' => $cerrada ? now() : null]);
            $this->getJson('/api/actividades/'.$a->actividadid)->assertOk()
                ->assertJsonPath('data.evidencia_estado', 'sin_fotografia')->assertJsonPath('data.evidencia_foto_url', null)
                ->assertJsonPath('data.tiene_evidencia', false)->assertJsonPath('data.consumos', [])
                ->assertJsonPath('data.resultado', null)->assertJsonPath('data.responsable_cierre', null);
            $this->actingAs($this->operario, 'web')->get(route('actividades.show', $a))->assertOk()
                ->assertSee('Esta actividad no tiene fotografía registrada')->assertSee('Esta actividad no registra consumo de insumos');
        }
        $this->cerrar()->assertConflict(); // A legacy completed task cannot be overwritten.
    }

    public function test_foto_registrada_inexistente_y_ruta_de_otra_actividad_son_controladas(): void
    {
        $this->cerrar()->assertOk();
        $a = $this->actividad->fresh();
        Storage::disk('local')->delete($a->evidencia_foto_path);
        $this->getJson('/api/actividades/'.$a->actividadid)->assertOk()
            ->assertJsonPath('data.tiene_evidencia', true)->assertJsonPath('data.evidencia_estado', 'no_disponible')
            ->assertJsonPath('data.evidencia_foto_url', null)->assertJsonCount(1, 'data.consumos');
        $this->actingAs($this->operario, 'web')->get(route('actividades.show', $a))->assertOk()
            ->assertSee('archivo no está disponible')->assertDontSee('Esta actividad no tiene fotografía registrada');
        $this->getJson('/api/actividades/'.$a->actividadid.'/evidencia')->assertNotFound();
        $a->update(['evidencia_foto_path' => null]);
        $this->getJson('/api/actividades/'.$a->actividadid)->assertOk()
            ->assertJsonPath('data.evidencia_estado', 'sin_fotografia')->assertJsonCount(1, 'data.consumos');
        Storage::disk('local')->put('actividades_privadas/999/ajena.png', 'no filtrar');
        $a->update(['evidencia_foto_path' => 'actividades_privadas/999/ajena.png']);
        $this->getJson('/api/actividades/'.$a->actividadid.'/evidencia')->assertNotFound();
    }

    public function test_ambitos_anidamiento_inexistentes_y_descarga_directa_autorizada(): void
    {
        $this->cerrar()->assertOk();
        $a = $this->actividad->fresh();
        $loteAjeno = $a->lote->replicate();
        $loteAjeno->usuarioid = $this->otro->usuarioid;
        $loteAjeno->save();
        $actividadAjena = $a->replicate();
        $actividadAjena->loteid = $loteAjeno->loteid;
        $actividadAjena->usuarioid = $this->otro->usuarioid;
        $actividadAjena->usuarioid_ejecutor = $this->otro->usuarioid;
        $actividadAjena->save();
        $this->getJson('/api/actividades/'.$actividadAjena->actividadid)->assertNotFound();
        $this->getJson('/api/actividades/'.$actividadAjena->actividadid.'/evidencia')->assertNotFound();
        $this->getJson('/api/lotes/'.$loteAjeno->loteid.'/actividades/'.$a->actividadid)->assertNotFound();
        $this->getJson('/api/actividades/999999')->assertNotFound();
        $this->getJson('/api/actividades/999999/evidencia')->assertNotFound();
        Sanctum::actingAs($this->otro);
        $this->getJson('/api/actividades/'.$a->actividadid)->assertNotFound();
        $this->getJson('/api/actividades/'.$a->actividadid.'/evidencia')->assertNotFound();
        $this->actingAs($this->otro, 'web')->get(route('actividades.show', $a))->assertForbidden();
        $this->get(route('actividades.evidencia', $a))->assertNotFound();
        auth()->forgetGuards();
        $this->getJson('/api/actividades/'.$a->actividadid)->assertUnauthorized();
        $this->getJson('/api/actividades/'.$a->actividadid.'/evidencia')->assertUnauthorized();
    }

    public function test_consumo_antiguo_solo_por_actividad_sin_inventar_almacen_historico(): void
    {
        $this->cerrar()->assertOk();
        $a = $this->actividad->fresh();
        $a->update(['detalle_json' => null]);
        $registro = LoteInsumo::where('actividadid', $a->actividadid)->firstOrFail();
        $sinActividad = $registro->replicate();
        $sinActividad->actividadid = null;
        $sinActividad->cantidadusada = '8.750';
        $sinActividad->save();
        $this->getJson('/api/actividades/'.$a->actividadid)->assertOk()->assertJsonCount(1, 'data.consumos')
            ->assertJsonPath('data.consumos.0.insumoid', $this->insumo->insumoid)
            ->assertJsonPath('data.consumos.0.cantidad', '2.500000')
            ->assertJsonPath('data.consumos.0.unidad', 'kg')->assertJsonPath('data.consumos.0.unidad_historica', false)
            ->assertJsonPath('data.consumos.0.almacenid', null)->assertDontSee('8.750');
        $this->actingAs($this->operario, 'web')->get(route('actividades.show', $a))->assertOk()
            ->assertSee('2.500000')->assertSee('unidad histórica no registrada')->assertDontSee('8.750');
    }

    public function test_fotografia_antigua_usa_ruta_autenticada_y_puede_no_tener_consumos(): void
    {
        $a = $this->actividad;
        $a->update(['fechafin' => now(), 'evidencia_foto_path' => 'actividades_evidencia/antigua.png', 'detalle_json' => null]);
        Storage::disk('public')->put('actividades_evidencia/antigua.png', $this->imagen);
        $r = $this->getJson('/api/actividades/'.$a->actividadid)->assertOk()->assertJsonPath('data.evidencia_estado', 'disponible')
            ->assertJsonPath('data.consumos', [])->assertJsonPath('data.evidencia_foto_url', route('api.actividades.evidencia', $a));
        $this->assertStringNotContainsString('/storage/actividades_evidencia/', $r->getContent());
        $this->getJson($r->json('data.evidencia_foto_url'))->assertOk();
        $this->actingAs($this->operario, 'web')->get(route('actividades.show', $a))->assertOk()->assertSee('Esta actividad no registra consumo de insumos');
    }
}
