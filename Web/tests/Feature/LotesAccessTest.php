<?php

namespace Tests\Feature;

use App\Models\Usuario;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class LotesAccessTest extends TestCase
{
    use RefreshDatabase;

    private function createUser(string $roleName): Usuario
    {
        $this->seed(RolePermissionSeeder::class);
        $role = Role::findOrCreate($roleName, 'web');

        $user = Usuario::create([
            'nombre' => 'Test',
            'apellido' => ucfirst($roleName),
            'email' => $roleName . '.lotes@test.local',
            'nombreusuario' => $roleName . '_lotes',
            'passwordhash' => Hash::make('secret123'),
            'role' => $roleName,
            'fecharegistro' => now(),
            'fechamodificacion' => now(),
            'activo' => true,
        ]);

        $user->syncRoles([$role->name]);
        return $user;
    }

    public function test_admin_supervisa_lotes_pero_no_los_crea(): void
    {
        $admin = $this->createUser('admin');
        $this->actingAs($admin);

        $this->get(route('lotes.index'))->assertOk();
        $this->get(route('lotes.create'))->assertForbidden();
        $this->post(route('lotes.store'), [])->assertForbidden();
    }

    public function test_agricultor_ve_sus_lotes_y_actividades_sin_crear_lotes(): void
    {
        $agricultor = $this->createUser('agricultor');
        $this->actingAs($agricultor);

        $this->get(route('lotes.index'))->assertOk();
        $this->get(route('lotes.create'))->assertForbidden();
        $this->get(route('actividades.index'))->assertOk();
        $this->get(route('actividades.calendario'))->assertOk();
    }

    public function test_admin_y_agricultor_acceden_api_lotes(): void
    {
        $admin = $this->createUser('admin');
        Sanctum::actingAs($admin);
        $this->getJson('/api/lotes')->assertOk();

        $agricultor = $this->createUser('agricultor');
        Sanctum::actingAs($agricultor);
        $this->getJson('/api/lotes')->assertOk();
    }

    public function test_agricultor_accede_api_lotes(): void
    {
        $agricultor = $this->createUser('agricultor');
        Sanctum::actingAs($agricultor);
        $this->getJson('/api/lotes')->assertOk();
    }

    public function test_listado_tabler_conserva_filtros_paginacion_y_acciones_por_estado(): void
    {
        $jefe = $this->createUser('jefe_agricultor');
        $this->seed(\Database\Seeders\CatalogosOperacionAgricolaSeeder::class);
        $unidad = \App\Models\UnidadMedida::firstOrCreate(['abreviatura' => 'ha'], ['nombre' => 'Hectárea', 'categoria' => 'superficie']);
        $cultivo = \App\Models\Cultivo::firstOrCreate(['nombre' => 'Papa']);
        $planificado = \App\Support\EstadoLoteCatalogo::idPorSlug('planificado');
        for ($i = 1; $i <= 16; $i++) {
            $lote = \App\Models\Lote::create([
                'usuarioid' => $jefe->usuarioid, 'nombre' => 'Parcela Tabler '.$i,
                'ubicacion' => 'Zona de prueba', 'superficie' => 1,
                'unidadsuperficieid' => $unidad->unidadmedidaid, 'cultivoid' => $cultivo->cultivoid,
                'estadolotetipoid' => $planificado, 'fechacreacion' => now(), 'fechamodificacion' => now(),
            ]);
        }

        $this->actingAs($jefe)->get(route('lotes.index', ['q' => 'Parcela Tabler']))
            ->assertOk()
            ->assertSee('Nuevo lote')
            ->assertSee(route('lotes.edit', $lote))
            ->assertSee(route('lotes.destroy', $lote))
            ->assertSee('name="_method" value="DELETE"', false)
            ->assertSee('name="_token"', false)
            ->assertSee('q=Parcela%20Tabler', false)
            ->assertSee('page=2', false)
            ->assertDontSee('bootstrap@4.6.2', false);

        $this->get(route('lotes.show', $lote))->assertOk()->assertSee('Datos del lote')->assertSee('Resumen de actividad')->assertDontSee('bootstrap@4.6.2', false);
        $this->get(route('lotes.ubicacion', $lote))->assertOk()->assertSee('Ubicación sin coordenadas')->assertSee('Agregar coordenadas');
        $tipo = \App\Models\TipoActividad::firstOrCreate(['nombre' => 'Preparación del terreno']);
        $prioridad = \App\Models\Prioridad::firstOrCreate(['nombre' => 'Media']);
        \App\Models\Actividad::create([
            'loteid' => $lote->loteid, 'usuarioid' => $jefe->usuarioid, 'descripcion' => 'Preparación de prueba',
            'tipoactividadid' => $tipo->tipoactividadid, 'prioridadid' => $prioridad->prioridadid,
            'fechainicio' => now()->subDay(), 'fechafin' => now(),
        ]);
        $this->get(route('lotes.trazabilidad', $lote))->assertOk()
            ->assertSee('Historial de eventos')->assertDontSee('bootstrap@4.6.2', false);
        $this->view('lotes.tabler.modal-asignar-siembra', [
            'lote' => $lote, 'puede_designar_responsable_siembra' => true,
            'responsable_siembra_label' => $jefe->nombre,
        ])->assertSee('data-bs-dismiss="modal"', false)->assertSee(route('lotes.siembra.asignar', $lote));

        $lote->update(['estadolotetipoid' => \App\Support\EstadoLoteCatalogo::idPorSlug('cosechado')]);
        $this->get(route('lotes.index', ['q' => $lote->nombre]))->assertOk()
            ->assertSee(route('lotes.show', $lote))
            ->assertSee(route('lotes.trazabilidad', $lote))
            ->assertDontSee(route('lotes.edit', $lote));

        $admin = $this->createUser('admin');
        $this->actingAs($admin)->get(route('lotes.index'))->assertOk()->assertDontSee('Nuevo lote');
        $this->get(route('lotes.index', ['q' => 'sin coincidencias']))->assertOk()->assertSee('No hay lotes que coincidan');
    }
}

