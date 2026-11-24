<?php

namespace Tests\Feature;

use App\Models\Actividad;
use App\Models\CatalogoTamanoConteo;
use App\Models\Cultivo;
use App\Models\DestinoProduccion;
use App\Models\HistorialEstadoLote;
use App\Models\Insumo;
use App\Models\Lote;
use App\Models\Prioridad;
use App\Models\Produccion;
use App\Models\TipoActividad;
use App\Models\TipoEmpaque;
use App\Models\TipoInsumo;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Support\EstadoLoteCatalogo;
use App\Support\LoteDefaults;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CosechaRegistroTest extends TestCase
{
    use RefreshDatabase;

    private Usuario $jefe;

    private Usuario $ajeno;

    private Usuario $operario;

    private UnidadMedida $kg;

    private Insumo $semilla;

    private CatalogoTamanoConteo $calibre;

    private Lote $lote;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        Storage::fake('public');
        $this->jefe = $this->usuario('jefe_agricultor', 'principal');
        $this->ajeno = $this->usuario('jefe_agricultor', 'ajeno');
        $this->operario = $this->usuario('agricultor', 'operario', $this->jefe->usuarioid);
        $this->kg = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
        $this->semilla = Insumo::create(['nombre' => 'Papa exactitud', 'unidadmedidaid' => $this->kg->unidadmedidaid,
            'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Material de Siembra'])->tipoinsumoid, 'stock' => '100']);
        $empaque = TipoEmpaque::firstOrCreate(['nombre' => 'Caja de cartón'], ['activo' => true]);
        $this->calibre = CatalogoTamanoConteo::create(['insumoid' => $this->semilla->insumoid,
            'nombre' => 'Calibre exacto', 'peso_promedio_kg' => '0.1750', 'conteo_por_empaque' => 50,
            'tipoempaqueid' => $empaque->tipoempaqueid, 'activo' => true]);
        DestinoProduccion::firstOrCreate(['nombre' => 'Almacenamiento']);
        $this->lote = $this->nuevoLote();
    }

    private function usuario(string $rol, string $nombre, ?int $supervisor = null): Usuario
    {
        $u = Usuario::create(['nombre' => $nombre, 'apellido' => 'Cosecha', 'email' => $nombre.'@cosecha.test',
            'nombreusuario' => 'cosecha_'.$nombre, 'passwordhash' => bcrypt('prueba123'), 'role' => $rol,
            'supervisor_usuarioid' => $supervisor, 'activo' => true, 'estado_cuenta' => 'aprobado',
            'fecharegistro' => now(), 'fechamodificacion' => now(), 'bienvenida_vista' => true]);
        $u->syncRoles([$rol]);

        return $u;
    }

    private function nuevoLote(?Usuario $responsable = null): Lote
    {
        return Lote::create(['usuarioid' => ($responsable ?? $this->jefe)->usuarioid,
            'nombre' => 'Lote cosecha '.Lote::count(), 'superficie' => 1, 'unidadsuperficieid' => LoteDefaults::unidadHectareaId(),
            'cultivoid' => Cultivo::firstOrCreate(['nombre' => 'Papa'])->cultivoid,
            'insumosemillaid' => $this->semilla->insumoid, 'catalogotamanoconteoid' => $this->calibre->catalogotamanoconteoid,
            'estadolotetipoid' => EstadoLoteCatalogo::idPorSlug('listo_para_cosecha')]);
    }

    private function como(Usuario $usuario): void
    {
        $this->actingAs($usuario, 'web');
        Sanctum::actingAs($usuario);
    }

    private function datos(?Lote $lote = null, array $cambios = []): array
    {
        return array_replace(['loteid' => ($lote ?? $this->lote)->loteid, 'cantidad' => '5250.125000',
            'unidadmedidaid' => $this->kg->unidadmedidaid, 'catalogotamanoconteoid' => $this->calibre->catalogotamanoconteoid,
            'fechacosecha' => '2026-11-17', 'evidencia_foto' => UploadedFile::fake()->image('cosecha.png', 4, 4)], $cambios);
    }

    private function registrar(array $cambios = [], ?Lote $lote = null)
    {
        return $this->post('/api/producciones', $this->datos($lote, $cambios), ['Accept' => 'application/json']);
    }

    public function test_web_y_api_guardan_la_misma_cosecha_y_consultas_cruzadas(): void
    {
        $this->como($this->jefe);
        $otro = $this->nuevoLote();
        $web = $this->post(route('producciones.store'), $this->datos())->assertSessionHasNoErrors()->assertRedirect();
        $a = Produccion::firstOrFail();
        $api = $this->registrar(lote: $otro)->assertCreated()
            ->assertJsonPath('cantidad', '5250.125000')->assertJsonPath('cantidad_base', '5250.125000')
            ->assertJsonPath('cantidad_unidades', 30001)->assertJsonPath('cantidad_empaques', 601)
            ->assertJsonPath('fechacosecha', '2026-11-17')->assertJsonPath('presentacion.peso_promedio_kg', '0.1750');
        $b = Produccion::findOrFail($api->json('produccionid'));
        $this->assertSame($a->cantidad, $b->cantidad);
        $this->assertSame($a->presentacion_cosecha, $b->presentacion_cosecha);
        $this->getJson('/api/producciones/'.$a->produccionid)->assertOk()->assertJsonPath('cantidad_base', '5250.125000');
        $this->get(route('producciones.show', $b))->assertOk()->assertSee('5250.125')->assertSee('Calibre exacto')->assertSee('0.1750 kg/unidad');
        $this->assertSame($this->lote->loteid, $a->loteid);
        $this->assertSame($this->calibre->catalogotamanoconteoid, $a->catalogotamanoconteoid);
        $this->assertSame(100.0, $this->semilla->fresh()->stock);
        $this->assertDatabaseCount('produccionalmacenamiento', 0);
        $this->assertSame(2, HistorialEstadoLote::where('estadolotetipoid', EstadoLoteCatalogo::idPorSlug('cosechado'))->count());
        $this->get(route('producciones.index'))->assertOk()->assertSee('5250.125');
    }

    public function test_reenviar_con_la_misma_clave_no_duplica_la_cosecha(): void
    {
        $this->como($this->jefe);
        $cabeceras = ['Accept' => 'application/json', 'Idempotency-Key' => 'cliente-reintento-1'];

        $primera = $this->post('/api/producciones', $this->datos(), $cabeceras)->assertCreated();
        $repetida = $this->post('/api/producciones', $this->datos(), $cabeceras)
            ->assertCreated()->assertHeader('Idempotent-Replayed', 'true');

        $this->assertSame(1, Produccion::count());
        $this->assertSame($primera->json('produccionid'), $repetida->json('produccionid'));
    }

    public function test_conversiones_factores_decimales_redondeo_y_vista_previa(): void
    {
        $this->como($this->jefe);
        $lb = UnidadMedida::create(['nombre' => 'Libra exacta', 'abreviatura' => 'lb', 'categoria' => 'peso']);
        $this->calibre->update(['peso_promedio_kg' => '0.1250', 'conteo_por_empaque' => 7]);
        $cantidadCalibres = CatalogoTamanoConteo::count();
        $this->get(route('producciones.create', ['loteid' => $this->lote->loteid]))->assertOk();
        $this->assertSame($cantidadCalibres, CatalogoTamanoConteo::count());
        $this->assertSame('0.1250', $this->calibre->fresh()->peso_promedio_kg);
        $previa = $this->getJson(route('producciones.vista-previa', [
            'loteid' => $this->lote->loteid, 'cantidad' => '1.234567', 'unidadmedidaid' => $lb->unidadmedidaid,
            'catalogotamanoconteoid' => $this->calibre->catalogotamanoconteoid,
        ]))->assertOk()->assertJsonPath('kg', '0.559990')->assertJsonPath('unidades', 4)->assertJsonPath('empaques', 1);
        $this->registrar(['cantidad' => '1.234567', 'unidadmedidaid' => $lb->unidadmedidaid])->assertCreated()
            ->assertJsonPath('cantidad_base', '0.559990')->assertJsonPath('presentacion.kg', $previa->json('kg'));
        // 0.0625 / 0.125 = 0.5 => one unit (HALF_UP), then one package (CEILING).
        $this->registrar(['cantidad' => '0.062500'], $this->nuevoLote())->assertCreated()
            ->assertJsonPath('cantidad_unidades', 1)->assertJsonPath('cantidad_empaques', 1);
        $g = UnidadMedida::create(['nombre' => 'Gramo exacto', 'abreviatura' => 'g', 'categoria' => 'peso']);
        $this->registrar(['cantidad' => '0.000500', 'unidadmedidaid' => $g->unidadmedidaid], $this->nuevoLote())->assertCreated()
            ->assertJsonPath('cantidad_base', '0.000001');
    }

    public function test_cantidades_invalidas_precision_limites_y_campos_derivados(): void
    {
        $this->como($this->jefe);
        foreach (['0', '-1', 'texto', '1.0000001', '1,25', '1,000.25', '1e3', '1000000000000', true, []] as $cantidad) {
            $this->registrar(['cantidad' => $cantidad])->assertUnprocessable()->assertJsonValidationErrors('cantidad');
        }
        $tonelada = UnidadMedida::create(['nombre' => 'Tonelada exacta', 'abreviatura' => 't', 'categoria' => 'peso']);
        $this->registrar(['cantidad' => '1000000000', 'unidadmedidaid' => $tonelada->unidadmedidaid])->assertUnprocessable()->assertJsonValidationErrors('cantidad');
        $this->registrar(['cantidad' => '400000000'])->assertUnprocessable()->assertJsonValidationErrors('cantidad');
        foreach (['cantidad_base', 'factor', 'factor_conversion', 'equivalencia', 'cantidad_unidades', 'cantidad_empaques', 'presentacion_cosecha', 'usuarioid', 'peso_promedio_kg'] as $campo) {
            $this->registrar([$campo => '1'])->assertUnprocessable()->assertJsonValidationErrors($campo);
        }
        $this->assertDatabaseCount('produccion', 0);
        $this->assertCount(0, Storage::disk('public')->allFiles());
    }

    public function test_limite_decimal_se_conserva_exacto_incluso_en_sqlite(): void
    {
        $this->como($this->jefe);
        $this->calibre->update(['peso_promedio_kg' => '999999.9999']);
        $r = $this->registrar(['cantidad' => '999999999999.999999'])->assertCreated()
            ->assertJsonPath('cantidad', '999999999999.999999')->assertJsonPath('cantidad_base', '999999999999.999999')
            ->assertJsonPath('cantidad_unidades', 1000000)->assertJsonPath('cantidad_empaques', 20000);
        $this->getJson('/api/producciones/'.$r->json('produccionid'))->assertOk()->assertJsonPath('cantidad', '999999999999.999999');
    }

    public function test_presentaciones_y_unidades_invalidas_no_generan_defaults(): void
    {
        $this->como($this->jefe);
        $this->registrar(['catalogotamanoconteoid' => 999999])->assertUnprocessable()->assertJsonValidationErrors('catalogotamanoconteoid');
        $this->calibre->update(['activo' => false]);
        $this->registrar()->assertUnprocessable()->assertJsonValidationErrors('catalogotamanoconteoid');
        $this->calibre->update(['activo' => true, 'peso_promedio_kg' => '0']);
        $this->registrar()->assertUnprocessable()->assertJsonValidationErrors('catalogotamanoconteoid');
        $this->calibre->update(['peso_promedio_kg' => '-0.1250']);
        $this->registrar()->assertUnprocessable()->assertJsonValidationErrors('catalogotamanoconteoid');
        $this->calibre->update(['peso_promedio_kg' => '0.1750', 'conteo_por_empaque' => 0]);
        $this->registrar()->assertUnprocessable()->assertJsonValidationErrors('catalogotamanoconteoid');
        $this->calibre->update(['conteo_por_empaque' => 50]);
        $this->calibre->tipoEmpaque->update(['activo' => false]);
        $this->registrar()->assertUnprocessable()->assertJsonValidationErrors('catalogotamanoconteoid');
        $this->calibre->tipoEmpaque->update(['activo' => true]);
        $semillaOtra = Insumo::create(['nombre' => 'Tomate incompatible', 'stock' => 0, 'unidadmedidaid' => $this->kg->unidadmedidaid, 'tipoinsumoid' => $this->semilla->tipoinsumoid]);
        $otro = $this->calibre->replicate();
        $otro->insumoid = $semillaOtra->insumoid;
        $otro->save();
        $this->registrar(['catalogotamanoconteoid' => $otro->catalogotamanoconteoid])->assertUnprocessable()->assertJsonValidationErrors('catalogotamanoconteoid');
        $litro = UnidadMedida::create(['nombre' => 'Litro inválido', 'abreviatura' => 'L', 'categoria' => 'volumen']);
        $this->registrar(['unidadmedidaid' => $litro->unidadmedidaid])->assertUnprocessable()->assertJsonValidationErrors('unidadmedidaid');
        $desconocida = UnidadMedida::create(['nombre' => 'Peso sin factor', 'abreviatura' => 'xyz', 'categoria' => 'peso']);
        $this->registrar(['unidadmedidaid' => $desconocida->unidadmedidaid])->assertUnprocessable()->assertJsonValidationErrors('unidadmedidaid');
        $this->assertDatabaseCount('catalogo_tamano_conteo', 2);
        $this->assertDatabaseCount('produccion', 0);
    }

    public function test_fecha_foto_obligatorias_y_errores_web_conservan_entrada(): void
    {
        $this->como($this->jefe);
        $this->registrar(['fechacosecha' => '2026-02-30'])->assertUnprocessable()->assertJsonValidationErrors('fechacosecha');
        $this->registrar(['evidencia_foto' => null])->assertUnprocessable()->assertJsonValidationErrors('evidencia_foto');
        $this->from(route('producciones.create', ['loteid' => $this->lote->loteid]))
            ->post(route('producciones.store'), $this->datos(cambios: ['cantidad' => '1,25']))
            ->assertRedirect()->assertSessionHasErrors('cantidad')->assertSessionHasInput('cantidad', '1,25');
        $this->get(route('producciones.create', ['loteid' => $this->lote->loteid]))->assertOk()
            ->assertSee('catalogotamanoconteoid')->assertSee('fechacosecha')->assertSee('1,25');
        // There is no pre-existing prohibition on future harvest dates.
        $this->registrar(['fechacosecha' => '2099-12-31'])->assertCreated()->assertJsonPath('fechacosecha', '2099-12-31');
    }

    public function test_ownership_consultas_catalogo_ruta_anidada_y_asignacion_operario(): void
    {
        $this->como($this->jefe);
        $id = $this->registrar()->assertCreated()->json('produccionid');
        $otroLote = $this->nuevoLote();
        $this->getJson('/api/lotes/'.$otroLote->loteid.'/producciones/'.$id)->assertNotFound();
        $this->como($this->ajeno);
        $this->getJson('/api/producciones/'.$id)->assertNotFound();
        $this->getJson('/api/producciones')->assertOk()->assertExactJson([]);
        $this->getJson('/api/producciones?loteid='.$this->lote->loteid)->assertNotFound();
        $this->getJson('/api/lotes/'.$this->lote->loteid.'/presentaciones-cosecha')->assertNotFound();
        $this->get(route('producciones.show', $id))->assertNotFound();
        $this->get(route('producciones.create', ['loteid' => $this->lote->loteid]))->assertNotFound();
        $this->get(route('producciones.index'))->assertOk()->assertDontSee('5250.125');
        $this->registrar(lote: $otroLote)->assertNotFound();
        $this->como($this->operario);
        $this->registrar(lote: $otroLote)->assertNotFound();
        $asignacion = Actividad::create(['loteid' => $otroLote->loteid, 'usuarioid' => $this->operario->usuarioid,
            'descripcion' => 'Tarea asignada', 'tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => 'Riego'])->tipoactividadid,
            'prioridadid' => Prioridad::firstOrCreate(['nombre' => 'Media'])->prioridadid, 'fechainicio' => now()]);
        $this->registrar(lote: $otroLote)->assertForbidden();
        $asignacion->update(['tipoactividadid' => TipoActividad::firstOrCreate(['nombre' => 'Cosecha'])->tipoactividadid]);
        $r = $this->registrar(lote: $otroLote)->assertCreated();
        $this->getJson('/api/lotes/'.$otroLote->loteid.'/producciones/'.$r->json('produccionid'))->assertOk();
    }

    public function test_autenticacion_y_permiso_sin_bypass_admin(): void
    {
        $this->get('/api/producciones')->assertUnauthorized()->assertJsonStructure(['message']);
        $this->registrar()->assertUnauthorized();
        $sinPermiso = $this->usuario('transportista', 'sinpermiso');
        $this->como($sinPermiso);
        $this->getJson('/api/producciones')->assertForbidden();
        $this->registrar()->assertForbidden();
        $this->como($this->usuario('admin', 'admin'));
        $this->registrar()->assertForbidden();
        $this->assertDatabaseCount('produccion', 0);
    }

    public function test_snapshot_no_cambia_por_edicion_catalogo_lote_ni_unidad(): void
    {
        $this->como($this->jefe);
        $r = $this->registrar()->assertCreated();
        $id = $r->json('produccionid');
        $snapshot = $r->json('presentacion');
        $this->calibre->update(['peso_promedio_kg' => '9.9999', 'conteo_por_empaque' => 2, 'nombre' => 'Editado', 'activo' => false]);
        $this->lote->update(['catalogotamanoconteoid' => null]);
        $this->kg->update(['abreviatura' => 't', 'nombre' => 'Unidad editada']);
        $this->getJson('/api/producciones/'.$id)->assertOk()->assertJsonPath('presentacion', $snapshot)->assertJsonPath('unidad', 'kg');
        $this->get(route('producciones.show', $id))->assertOk()->assertSee('Calibre exacto')->assertSee('0.1750 kg/unidad')->assertSee('5250.125');
        $this->putJson('/api/producciones/'.$id, ['cantidad' => '1'])->assertStatus(405);
        $this->deleteJson('/api/producciones/'.$id)->assertStatus(405);
        $this->assertSame('5250.125000', Produccion::findOrFail($id)->cantidad);
    }

    public function test_fallo_de_historial_revierte_cosecha_estado_y_archivo(): void
    {
        $this->como($this->jefe);
        HistorialEstadoLote::creating(function () {
            throw new \RuntimeException('Fallo de persistencia simulado');
        });
        try {
            $this->registrar()->assertStatus(500);
        } finally {
            HistorialEstadoLote::flushEventListeners();
        }
        $this->assertDatabaseCount('produccion', 0);
        $this->assertSame(EstadoLoteCatalogo::idPorSlug('listo_para_cosecha'), $this->lote->fresh()->estadolotetipoid);
        $this->assertCount(0, Storage::disk('public')->allFiles());
    }

    public function test_legacy_no_inventa_factor_y_listado_no_oculta_cosechas_previas(): void
    {
        $this->como($this->jefe);
        $datos = ['loteid' => $this->lote->loteid, 'cantidad' => '10.123456', 'cantidad_base' => null,
            'unidadmedidaid' => $this->kg->unidadmedidaid, 'fechacosecha' => '2026-10-01',
            'destinoproduccionid' => DestinoProduccion::first()->destinoproduccionid];
        $a = Produccion::create($datos);
        $b = Produccion::create(array_replace($datos, ['cantidad_base' => '9.500000', 'cantidad_unidades' => 77, 'cantidad_empaques' => 3]));
        $this->getJson('/api/producciones/'.$a->produccionid)->assertOk()->assertJsonPath('cantidad_base', null)
            ->assertJsonPath('presentacion.unidades', null)->assertJsonPath('presentacion.peso_promedio_kg', null);
        $this->calibre->update(['peso_promedio_kg' => '3.0000']);
        $this->getJson('/api/producciones/'.$b->produccionid)->assertOk()->assertJsonPath('cantidad_unidades', 77)->assertJsonPath('cantidad_base', '9.500000');
        $this->getJson('/api/producciones')->assertOk()->assertJsonCount(2);
        $this->get(route('producciones.index'))->assertOk()->assertViewHas('producciones', fn ($p) => $p->total() === 2);
        $this->get(route('producciones.show', $a))->assertOk()->assertSee('El factor original no está disponible');
        $this->assertNull($a->fresh()->presentacion_cosecha);
    }

    public function test_alias_cantidadkg_y_presentacion_planificada_son_compatibles(): void
    {
        $this->como($this->jefe);
        $data = $this->datos();
        unset($data['cantidad'], $data['catalogotamanoconteoid'], $data['unidadmedidaid'], $data['fechacosecha']);
        $data['cantidadkg'] = '8.750000';
        $this->post('/api/producciones', $data, ['Accept' => 'application/json'])->assertCreated()
            ->assertJsonPath('cantidad', '8.750000')->assertJsonPath('cantidad_unidades', 50)->assertJsonPath('cantidad_empaques', 1)
            ->assertJsonPath('fechacosecha', now()->toDateString());
    }
}
