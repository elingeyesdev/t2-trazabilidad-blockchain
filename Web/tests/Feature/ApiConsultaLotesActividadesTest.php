<?php

namespace Tests\Feature;

use App\Models\Actividad;
use App\Models\Cultivo;
use App\Models\EstadoLoteTipo;
use App\Models\HistorialEstadoLote;
use App\Models\Lote;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ApiConsultaLotesActividadesTest extends TestCase
{
    use RefreshDatabase;

    private function crearUsuario(string $rol, string $sufijo, ?int $supervisorId = null): Usuario
    {
        $this->seed(RolePermissionSeeder::class);
        $this->seed(CatalogosOperacionAgricolaSeeder::class);
        $role = Role::findOrCreate($rol, 'web');

        $user = Usuario::create([
            'nombre' => 'Usuario '.$sufijo,
            'apellido' => 'Prueba',
            'email' => "{$rol}.{$sufijo}@consulta-api.test",
            'nombreusuario' => "{$rol}_{$sufijo}",
            'passwordhash' => Hash::make('secret123'),
            'role' => $rol,
            'supervisor_usuarioid' => $supervisorId,
            'fecharegistro' => now(),
            'fechamodificacion' => now(),
            'activo' => true,
        ]);
        $user->syncRoles([$role->name]);

        return $user;
    }

    private function crearLote(Usuario $responsable, string $nombre = 'Lote Consulta'): Lote
    {
        $unidad = UnidadMedida::query()->firstOrCreate(
            ['abreviatura' => 'ha'],
            ['nombre' => 'Hectárea', 'categoria' => 'superficie']
        );
        $cultivo = Cultivo::query()->firstOrCreate(
            ['nombre' => 'Papa'],
            ['detalle' => 'Cultivo de prueba']
        );
        $estado = EstadoLoteTipo::query()->firstOrCreate(['nombre' => 'En crecimiento']);

        return Lote::create([
            'usuarioid' => $responsable->usuarioid,
            'nombre' => $nombre,
            'ubicacion' => 'Parcela de prueba',
            'superficie' => 2.5,
            'unidadsuperficieid' => $unidad->unidadmedidaid,
            'cultivoid' => $cultivo->cultivoid,
            'estadolotetipoid' => $estado->estadolotetipoid,
            'fechasiembra' => '2026-08-01',
            'fechacreacion' => '2026-07-30 10:00:00',
            'fechamodificacion' => '2026-08-01 10:00:00',
        ]);
    }

    private function crearActividad(Lote $lote, Usuario $responsable, string $descripcion, ?string $fechaFin = null): Actividad
    {
        $tipo = TipoActividad::query()->firstOrCreate(['nombre' => 'Riego'], ['descripcion' => 'Riego de prueba']);
        $prioridad = Prioridad::query()->firstOrCreate(['nombre' => 'Media']);

        return Actividad::create([
            'loteid' => $lote->loteid,
            'usuarioid' => $responsable->usuarioid,
            'descripcion' => $descripcion,
            'fechainicio' => '2026-08-03 08:15:00',
            'fecha_planificada' => '2026-08-04',
            'fechafin' => $fechaFin,
            'tipoactividadid' => $tipo->tipoactividadid,
            'prioridadid' => $prioridad->prioridadid,
        ]);
    }

    private function crearHistorial(Lote $lote, Usuario $usuario): HistorialEstadoLote
    {
        return HistorialEstadoLote::create([
            'loteid' => $lote->loteid,
            'estadolotetipoid' => $lote->estadolotetipoid,
            'fecha_cambio' => '2026-08-02 12:00:00',
            'observaciones' => 'Inspección de prueba',
            'usuarioid' => $usuario->usuarioid,
        ]);
    }

    public function test_consultas_requieren_autenticacion(): void
    {
        $this->getJson('/api/lotes')->assertUnauthorized();
        $this->getJson('/api/actividades')->assertUnauthorized();
        $this->getJson('/api/historial-estados-lote')->assertUnauthorized();
    }

    public function test_usuario_autenticado_sin_permiso_de_lectura_recibe_403(): void
    {
        $usuario = $this->crearUsuario('sin_permisos', 'lectura');
        Sanctum::actingAs($usuario);

        $this->getJson('/api/lotes')->assertForbidden();
        $this->getJson('/api/actividades')->assertForbidden();
        $this->getJson('/api/historial-estados-lote')->assertForbidden();
    }

    public function test_listados_y_detalles_se_acotan_a_las_asignaciones_del_usuario(): void
    {
        $jefe = $this->crearUsuario('jefe_agricultor', 'equipo');
        $operarioA = $this->crearUsuario('agricultor', 'A', $jefe->usuarioid);
        $operarioB = $this->crearUsuario('agricultor', 'B', $jefe->usuarioid);
        $lote = $this->crearLote($jefe);
        $actividadA = $this->crearActividad($lote, $operarioA, 'Tarea visible');
        $actividadB = $this->crearActividad($lote, $operarioB, 'Tarea ajena');
        $historial = $this->crearHistorial($lote, $jefe);

        Sanctum::actingAs($operarioA);

        $this->getJson('/api/lotes')->assertOk()
            ->assertJsonPath('data.0.loteid', $lote->loteid);
        $this->getJson('/api/lotes/'.$lote->loteid)->assertOk()
            ->assertJsonPath('data.actividades.0.actividadid', $actividadA->actividadid)
            ->assertJsonMissing(['descripcion' => 'Tarea ajena']);
        $this->getJson('/api/actividades')->assertOk()
            ->assertJsonPath('data.0.actividadid', $actividadA->actividadid)
            ->assertJsonMissing(['actividadid' => $actividadB->actividadid]);
        $this->getJson('/api/actividades/'.$actividadB->actividadid)->assertNotFound();
        $this->getJson('/api/historial-estados-lote/'.$historial->historial_estado_id)->assertOk();
    }

    public function test_consulta_anidada_no_devuelve_actividad_de_otro_lote(): void
    {
        $jefe = $this->crearUsuario('jefe_agricultor', 'anidado');
        $operario = $this->crearUsuario('agricultor', 'Anidado', $jefe->usuarioid);
        $loteA = $this->crearLote($jefe, 'Lote A');
        $loteB = $this->crearLote($jefe, 'Lote B');
        $actividadB = $this->crearActividad($loteB, $operario, 'Actividad del lote B');

        Sanctum::actingAs($jefe);

        $this->getJson('/api/lotes/'.$loteA->loteid.'/actividades/'.$actividadB->actividadid)->assertNotFound();
        $this->getJson('/api/lotes/'.$loteA->loteid.'/actividades')->assertOk()
            ->assertJsonPath('data', []);
        $this->getJson('/api/lotes/'.$loteA->loteid.'/actividades?loteid='.$loteB->loteid)->assertUnprocessable();
        $this->getJson('/api/lotes/999999/actividades')->assertNotFound();
        $this->getJson('/api/actividades/999999')->assertNotFound();
    }

    public function test_tareas_pendientes_filtros_y_paginacion_usan_la_regla_de_la_web(): void
    {
        $jefe = $this->crearUsuario('jefe_agricultor', 'paginacion');
        $lote = $this->crearLote($jefe);
        $pendiente = $this->crearActividad($lote, $jefe, 'Tarea pendiente');
        $completada = $this->crearActividad($lote, $jefe, 'Tarea completada', '2026-08-03 09:00:00');
        $this->crearActividad($lote, $jefe, 'Tercera tarea');

        Sanctum::actingAs($jefe);

        $this->getJson('/api/actividades?estado=pendiente&per_page=1&page=2')
            ->assertOk()
            ->assertJsonPath('meta.per_page', 1)
            ->assertJsonPath('meta.current_page', 2)
            ->assertJsonPath('meta.total', 2)
            ->assertJsonPath('data.0.pendiente', true);
        $this->getJson('/api/actividades?estado=completada')
            ->assertOk()
            ->assertJsonPath('data.0.actividadid', $completada->actividadid)
            ->assertJsonPath('data.0.completada', true);
        $this->getJson('/api/actividades?loteid='.$lote->loteid.'&tipoactividadid='.$pendiente->tipoactividadid)
            ->assertOk()
            ->assertJsonPath('meta.total', 3);
        $this->getJson('/api/lotes?per_page=1&sort=nombre&direction=asc')
            ->assertOk()
            ->assertJsonPath('meta.per_page', 1);
        $this->getJson('/api/actividades?estado=otro')->assertUnprocessable();
        $this->getJson('/api/actividades?per_page=101')->assertUnprocessable();
        $this->getJson('/api/actividades?sort=passwordhash')->assertUnprocessable();
        $this->getJson('/api/lotes?direction=sideways')->assertUnprocessable();
    }

    public function test_lote_sin_actividades_o_historial_devuelve_colecciones_vacias(): void
    {
        $jefe = $this->crearUsuario('jefe_agricultor', 'vacio');
        $lote = $this->crearLote($jefe, 'Lote sin eventos');
        $lote->update(['fechasiembra' => null]);

        Sanctum::actingAs($jefe);

        $this->getJson('/api/lotes/'.$lote->loteid)->assertOk()
            ->assertJsonPath('data.actividades', [])
            ->assertJsonPath('data.actividades_pendientes', 0)
            ->assertJsonPath('data.producciones', [])
            ->assertJsonPath('data.historial', [])
            ->assertJsonPath('data.insumo_semilla', null)
            ->assertJsonPath('data.cultivo.nombre', 'Papa')
            ->assertJsonPath('data.estado_tipo.nombre', 'En crecimiento');
    }

    public function test_historial_general_solo_incluye_lotes_visibles(): void
    {
        $jefeA = $this->crearUsuario('jefe_agricultor', 'histA');
        $jefeB = $this->crearUsuario('jefe_agricultor', 'histB');
        $loteA = $this->crearLote($jefeA, 'Lote historia A');
        $loteB = $this->crearLote($jefeB, 'Lote historia B');
        $historialA = $this->crearHistorial($loteA, $jefeA);
        $historialB = $this->crearHistorial($loteB, $jefeB);

        Sanctum::actingAs($jefeA);

        $this->getJson('/api/historial-estados-lote')->assertOk()
            ->assertJsonPath('meta.total', 1)
            ->assertJsonPath('data.0.historial_estado_id', $historialA->historial_estado_id)
            ->assertJsonMissing(['historial_estado_id' => $historialB->historial_estado_id]);
        $this->getJson('/api/historial-estados-lote?fecha_hasta=2026-08-02')
            ->assertOk()
            ->assertJsonPath('meta.total', 1);
        $this->getJson('/api/historial-estados-lote?fecha_desde=2026-08-03&fecha_hasta=2026-08-02')
            ->assertUnprocessable();
        $this->getJson('/api/historial-estados-lote/'.$historialB->historial_estado_id)->assertNotFound();
        $this->getJson('/api/lotes/'.$loteB->loteid)->assertNotFound();
    }

    public function test_campos_api_coinciden_con_el_detalle_web_y_no_exponen_columnas_internas(): void
    {
        $jefe = $this->crearUsuario('jefe_agricultor', 'coherencia');
        $lote = $this->crearLote($jefe, 'Lote coherencia');
        $actividad = $this->crearActividad($lote, $jefe, 'Riego de coherencia');
        $actividad->update(['evidencia_foto_path' => 'actividades/evidencia-prueba.jpg']);
        $actividad->refresh();
        $this->crearHistorial($lote, $jefe);

        $web = $this->actingAs($jefe)->get(route('lotes.trazabilidad', $lote))->assertOk();
        Sanctum::actingAs($jefe);
        $api = $this->getJson('/api/lotes/'.$lote->loteid)->assertOk()
            ->assertJsonPath('data.loteid', $lote->loteid)
            ->assertJsonPath('data.nombre', 'Lote coherencia')
            ->assertJsonPath('data.cultivo_etiqueta', 'Papa')
            ->assertJsonPath('data.estado_tipo.nombre', 'En crecimiento')
            ->assertJsonPath('data.usuario.nombre', 'Usuario coherencia')
            ->assertJsonPath('data.actividades.0.actividadid', $actividad->actividadid)
            ->assertJsonPath('data.actividades.0.fecha_planificada', '2026-08-04')
            ->assertJsonPath('data.actividades.0.pendiente', true)
            ->assertJsonPath('data.actividades.0.evidencia_foto_path', 'actividades/evidencia-prueba.jpg')
            ->assertJsonPath('data.actividades.0.tiene_evidencia', true)
            ->assertJsonMissingPath('data.usuario.passwordhash')
            ->assertJsonMissingPath('data.actividades.0.detalle_json');

        $this->assertStringContainsString('Lote coherencia', $web->getContent());
        $this->assertStringContainsString('Papa', $web->getContent());
        $this->assertSame('2026-08-04', $api->json('data.actividades.0.fecha_planificada'));
        $this->assertStringEndsWith('/storage/actividades/evidencia-prueba.jpg', $api->json('data.actividades.0.evidencia_foto_url'));
        $this->assertNotEmpty($api->json('data.historial'));
    }
}
