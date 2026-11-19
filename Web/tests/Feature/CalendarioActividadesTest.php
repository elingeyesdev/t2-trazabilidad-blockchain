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

class CalendarioActividadesTest extends TestCase
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

    private function periodo(string $inicio, string $fin)
    {
        return $this->getJson(route('actividades.calendario', ['start' => $inicio, 'end' => $fin]));
    }

    private function preparar(): void
    {
        $this->actingAs($this->operario, 'web');
        $this->actividad->update(['fecha_planificada' => '2030-03-01', 'fechainicio' => '2030-02-20 09:30:00',
            'fechafin' => '2030-03-05 18:00:00', 'usuarioid_ejecutor' => $this->otro->usuarioid]);
    }

    private function consumo(): array
    {
        return ['insumoid' => $this->insumo->insumoid, 'almacenid' => $this->almacen->almacenid, 'cantidad' => '2.500'];
    }

    public function test_fecha_planificada_no_se_mueve_al_cierre_y_abre_detalle_existente(): void
    {
        $this->preparar();
        $this->periodo('2030-03-01', '2030-03-02')->assertOk()->assertJsonCount(1, 'eventos')
            ->assertJsonPath('eventos.0.id', (string) $this->actividad->actividadid)
            ->assertJsonPath('eventos.0.start', '2030-03-01')->assertJsonPath('eventos.0.allDay', true)
            ->assertJsonPath('eventos.0.title', 'Fertilización asignada')
            ->assertJsonPath('eventos.0.extendedProps.responsable', 'operario Cierre')
            ->assertJsonPath('eventos.0.extendedProps.estado', 'Completada')
            ->assertJsonPath('eventos.0.url', route('actividades.show', $this->actividad));
        $this->periodo('2030-03-05', '2030-03-06')->assertOk()->assertJsonPath('eventos', []);
        $this->periodo('2030-02-20', '2030-02-21')->assertOk()->assertJsonPath('eventos', []);
        $this->get(route('actividades.show', $this->actividad))->assertOk()->assertSee('Responsable del cierre');
    }

    public function test_limites_exclusivos_fallback_de_inicio_y_navegacion_conservan_dias(): void
    {
        $this->preparar();
        $sinPlan = $this->actividad->replicate();
        $sinPlan->fill(['fecha_planificada' => null, 'fechainicio' => '2030-02-28 23:59:59', 'fechafin' => null, 'descripcion' => 'Inicio sin planificación']);
        $sinPlan->save();
        $this->periodo('2030-02-01', '2030-03-01')->assertOk()->assertJsonCount(1, 'eventos')
            ->assertJsonPath('eventos.0.id', (string) $sinPlan->actividadid)
            ->assertJsonPath('eventos.0.start', '2030-02-28')->assertJsonPath('eventos.0.extendedProps.estado', 'Pendiente');
        $this->periodo('2030-03-01', '2030-04-01')->assertOk()->assertJsonCount(1, 'eventos')
            ->assertJsonPath('eventos.0.id', (string) $this->actividad->actividadid);
        $this->periodo('2030-02-28', '2030-03-02')->assertOk()->assertJsonCount(2, 'eventos');
        $this->periodo('2030-02-01', '2030-03-01')->assertOk()->assertJsonPath('eventos.0.start', '2030-02-28');
    }

    public function test_ambitos_estados_y_responsable_sin_asignar_sin_filtraciones(): void
    {
        $this->preparar();
        $ajena = $this->actividad->replicate();
        $ajena->fill(['usuarioid' => $this->otro->usuarioid, 'usuarioid_ejecutor' => null, 'descripcion' => 'Trabajo privado otro']);
        $ajena->save();
        $this->periodo('2030-03-01', '2030-04-01')->assertOk()->assertJsonCount(1, 'eventos')->assertDontSee('Trabajo privado otro');
        $this->actingAs($this->jefe, 'web');
        $this->periodo('2030-03-01', '2030-04-01')->assertOk()->assertJsonCount(2, 'eventos');
        $ajena->update(['fechafin' => null]);
        $this->periodo('2030-03-01', '2030-04-01')->assertOk()->assertJsonPath('eventos.1.extendedProps.responsable', 'otro Cierre')
            ->assertJsonPath('eventos.1.extendedProps.estado', 'Pendiente');
        $jefeAjeno = $this->usuario('jefe_agricultor', 'jefeajeno');
        $this->actingAs($jefeAjeno, 'web');
        $this->periodo('2030-03-01', '2030-04-01')->assertOk()->assertJsonPath('eventos', [])->assertJsonPath('sin_fecha', 0);
        $this->get(route('actividades.show', $this->actividad))->assertForbidden();
    }

    public function test_valida_rango_autenticacion_y_pagina_sin_cargar_todos_los_eventos(): void
    {
        $this->preparar();
        $this->get(route('actividades.calendario'))->assertOk()->assertSee('Calendario de actividades')
            ->assertSee('agSidebar')->assertDontSee('Fertilización asignada')->assertDontSee('newActivityModal');
        foreach ([['2030-02-30', '2030-03-02'], ['2030-03-02', '2030-03-01'], ['2030-03-01', '2030-03-01'], ['2030-01-01', '2030-04-01']] as [$inicio, $fin]) {
            $this->periodo($inicio, $fin)->assertUnprocessable();
        }
        $this->getJson(route('actividades.calendario', ['start' => '2030-03-01']))->assertUnprocessable();
        $this->periodo('2030-04-01', '2030-05-01')->assertOk()->assertJsonPath('eventos', []);
        auth()->forgetGuards();
        $this->getJson(route('actividades.calendario', ['start' => '2030-03-01', 'end' => '2030-04-01']))->assertUnauthorized();
    }
}
