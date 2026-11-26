<?php

namespace Tests\Feature;

use App\Models\IncidenteEnvio;
use App\Models\Prioridad;
use App\Models\TipoActividad;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Support\CertificadosFixture;
use Tests\Support\EnvioQrFixture;
use Tests\Support\TrazabilidadPublicaFixture;
use Tests\TestCase;

class ApiPermisosOperativos63Test extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        Storage::fake('local');
    }

    private function autenticar($usuario): void
    {
        app('auth')->forgetGuards();
        $this->withHeaders(['Authorization' => 'Bearer '.$usuario->createToken('edt63')->plainTextToken]);
    }

    public function test_matriz_ocho_roles_lecturas_y_denegaciones_con_guard_real(): void
    {
        $tipo = TipoActividad::firstOrCreate(['nombre' => 'Riego']);
        $prioridad = Prioridad::firstOrCreate(['nombre' => 'Media']);
        foreach (['admin', 'jefe_agricultor', 'agricultor', 'jefe_planta', 'planta', 'transportista', 'mayorista', 'minorista'] as $rol) {
            $usuario = CertificadosFixture::usuario($rol, 'matriz63'.$rol);
            $this->autenticar($usuario);
            $asigna = in_array($rol, ['admin', 'jefe_agricultor'], true);
            $cosecha = in_array($rol, ['admin', 'jefe_agricultor', 'agricultor'], true);
            $this->getJson('/api/catalogos-operativos/tipoactividades')->assertStatus($asigna ? 200 : 403);
            $this->getJson('/api/catalogos-operativos/prioridades')->assertStatus($asigna ? 200 : 403);
            $this->getJson('/api/catalogos-operativos/unidadesmedida')->assertStatus($cosecha ? 200 : 403);
            $this->getJson('/api/actividades/responsables')->assertStatus($rol === 'jefe_agricultor' ? 200 : 403);
            $this->getJson('/api/usuarios')->assertStatus($rol === 'admin' ? 200 : 403);
            $this->getJson('/api/punto-venta/inventario')->assertStatus(in_array($rol, ['admin', 'minorista'], true) ? 200 : 403);
            $this->postJson('/api/tipoactividades', ['nombre' => 'Prueba '.$rol])->assertStatus($rol === 'admin' ? 201 : 403);
            if ($rol !== 'admin') {
                $this->patchJson('/api/prioridades/'.$prioridad->getKey(), ['nombre' => 'Cambiar'])->assertForbidden();
            }
        }
    }

    public function test_selector_de_equipo_habilita_asignacion_real_y_excluye_ajenos_inactivos_y_pendientes(): void
    {
        $f = TrazabilidadPublicaFixture::crear();
        $jefe = $f['usuario'];
        $jefe->update(['role' => 'jefe_agricultor']);
        $jefe->syncRoles(['jefe_agricultor']);
        $empleado = CertificadosFixture::usuario('agricultor', 'empleado63');
        $empleado->update(['supervisor_usuarioid' => $jefe->getKey()]);
        $ajeno = CertificadosFixture::usuario('agricultor', 'ajeno63');
        $inactivo = CertificadosFixture::usuario('agricultor', 'inactivo63');
        $inactivo->update(['supervisor_usuarioid' => $jefe->getKey(), 'activo' => false]);
        $pendiente = CertificadosFixture::usuario('agricultor', 'pendiente63');
        $pendiente->update(['supervisor_usuarioid' => $jefe->getKey(), 'estado_cuenta' => 'pendiente']);
        $tipo = TipoActividad::firstOrCreate(['nombre' => 'Preparación del terreno']);
        $prioridad = Prioridad::firstOrCreate(['nombre' => 'Media']);
        $this->autenticar($jefe);
        $this->getJson('/api/usuarios')->assertForbidden();
        $this->getJson('/api/tipoactividades')->assertForbidden();
        $this->getJson('/api/catalogos-operativos/tipoactividades')->assertOk()->assertJsonFragment(['tipoactividadid' => $tipo->getKey()]);
        $res = $this->getJson('/api/actividades/responsables')->assertOk()->assertJsonCount(2)
            ->assertJsonFragment(['usuarioid' => $empleado->getKey()])->assertDontSee($jefe->email)->assertDontSee('passwordhash');
        $ids = array_column($res->json(), 'usuarioid');
        $this->assertNotContains($ajeno->getKey(), $ids);
        $this->assertNotContains($inactivo->getKey(), $ids);
        $this->assertNotContains($pendiente->getKey(), $ids);
        $datos = ['loteid' => $f['lote']->getKey(), 'usuarioid' => $empleado->getKey(), 'tipoactividadid' => $tipo->getKey(),
            'prioridadid' => $prioridad->getKey(), 'descripcion' => 'Riego del equipo', 'fechainicio' => now()->toDateTimeString(), 'fecha_planificada' => now()->toDateString()];
        $this->postJson('/api/actividades', $datos)->assertCreated();
        $this->assertDatabaseHas('actividad', ['loteid' => $f['lote']->getKey(), 'usuarioid' => $empleado->getKey()]);
        $this->postJson('/api/actividades', [...$datos, 'usuarioid' => $ajeno->getKey()])->assertUnprocessable()->assertJsonValidationErrors('usuarioid');
        $this->postJson('/api/actividades', [...$datos, 'usuarioid' => $pendiente->getKey()])->assertUnprocessable()->assertJsonValidationErrors('usuarioid');
        $this->autenticar($empleado);
        $this->getJson('/api/actividades')->assertOk()->assertJsonPath('meta.total', 1);
        $this->postJson('/api/actividades', $datos)->assertForbidden();
    }

    public function test_incidentes_selector_reporte_asignacion_y_resolucion_por_los_tres_ambitos(): void
    {
        foreach (['agricola' => 'envio_agricola', 'traslado' => 'traslado', 'distribucion' => 'distribucion'] as $trayecto => $tipo) {
            $f = EnvioQrFixture::crear($trayecto);
            $params = http_build_query(['afectado_tipo' => $tipo, 'afectado_id' => $f['envio']->getKey()]);
            $this->autenticar($f['conductor']);
            $this->getJson('/api/incidentes/responsables?'.$params)->assertOk()
                ->assertJsonFragment(['usuarioid' => $f['remitente']->getKey()])->assertDontSee($f['remitente']->email);
            $datos = ['afectado_tipo' => $tipo, 'afectado_id' => $f['envio']->getKey(), 'tipo' => 'Retraso',
                'descripcion' => 'Demora en el viaje asignado', 'responsable_usuarioid' => $f['remitente']->getKey()];
            $res = $this->postJson('/api/incidentes', $datos)->assertCreated()->assertJsonPath('estado', 'abierto');
            $id = $res->json('incidenteenvioid');
            $this->getJson('/api/incidentes/'.$id)->assertOk();
            $this->patchJson('/api/incidentes/'.$id.'/resolver', ['nota_resolucion' => 'No autorizado'])->assertForbidden();
            $this->patchJson('/api/incidentes/'.$id.'/asignar', ['responsable_usuarioid' => $f['remitente']->getKey()])->assertForbidden();
            // Historical unassigned report: only an eligible manager can fill the missing assignment.
            IncidenteEnvio::whereKey($id)->update(['responsable_usuarioid' => null]);
            $this->autenticar($f['remitente']);
            $this->patchJson('/api/incidentes/'.$id.'/asignar', ['responsable_usuarioid' => $f['remitente']->getKey()])->assertOk()
                ->assertJsonPath('responsable_usuarioid', $f['remitente']->getKey());
            $this->patchJson('/api/incidentes/'.$id.'/resolver', ['nota_resolucion' => 'Se coordinó la entrega.'])->assertOk()->assertJsonPath('estado', 'resuelto');
            $this->assertDatabaseHas('incidente_envio', ['incidenteenvioid' => $id, 'resueltopor_usuarioid' => $f['remitente']->getKey()]);
            $ajeno = CertificadosFixture::usuario('transportista', 'ajeno'.$trayecto.'63');
            $this->autenticar($ajeno);
            $this->getJson('/api/incidentes/responsables?'.$params)->assertNotFound();
            $this->getJson('/api/incidentes/'.$id)->assertNotFound();
        }
    }

    public function test_sin_sesion_no_hay_selectores_ni_inventario_privado(): void
    {
        foreach (['catalogos-operativos/tipoactividades', 'catalogos-operativos/unidadesmedida', 'actividades/responsables',
            'incidentes/responsables?afectado_tipo=envio_agricola&afectado_id=1', 'punto-venta/inventario'] as $uri) {
            $this->getJson('/api/'.$uri)->assertUnauthorized();
        }
    }
}
