<?php

namespace Tests\Feature;

use App\Models\AlmacenMovimiento;
use App\Models\IncidenteEnvio;
use App\Services\IncidenteSeguimientoService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\Support\CertificadosFixture;
use Tests\Support\EnvioQrFixture;
use Tests\TestCase;

class IncidenteSeguimientoTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        Storage::fake('local');
        $this->f = EnvioQrFixture::crear('agricola');
    }

    private function entrada(array $extra = []): array
    {
        return [...['afectado_tipo' => 'envio_agricola', 'afectado_id' => $this->f['envio']->getKey(),
            'tipo' => 'Retraso', 'descripcion' => '  Demora registrada en el trayecto.  ',
            'responsable_usuarioid' => $this->f['remitente']->getKey()], ...$extra];
    }

    private function crear(): IncidenteEnvio
    {
        return app(IncidenteSeguimientoService::class)->registrar($this->f['conductor'], $this->entrada());
    }

    public function test_registro_detalle_y_autoria_son_concretos_y_no_exponen_modelos_de_usuario(): void
    {
        $this->actingAs($this->f['conductor'])->postJson('/api/incidentes', $this->entrada())->assertCreated()
            ->assertJsonPath('descripcion', 'Demora registrada en el trayecto.')
            ->assertJsonPath('afectado.tipo', 'envio_agricola')->assertJsonPath('afectado.id', $this->f['envio']->getKey())
            ->assertJsonPath('estado', 'abierto')->assertJsonPath('responsable.usuarioid', $this->f['remitente']->getKey())
            ->assertJsonPath('reportadopor_usuarioid', $this->f['conductor']->getKey())->assertJsonPath('nota_resolucion', null)
            ->assertDontSee('passwordhash')->assertDontSee('@edt44.test');
        $i = IncidenteEnvio::firstOrFail();
        $this->getJson('/api/incidentes/'.$i->getKey())->assertOk()->assertJsonPath('incidenteenvioid', $i->getKey());
        $this->assertSame($this->f['pedido']->getKey(), $i->pedidoid);
        $this->assertSame($this->f['envio']->getKey(), $i->envioasignacionmultipleid);
    }

    public function test_descripciones_referencias_y_metadatos_no_se_pueden_imponer(): void
    {
        $this->actingAs($this->f['conductor']);
        foreach (['', '   ', str_repeat('x', 3001), null] as $descripcion) {
            $this->postJson('/api/incidentes', $this->entrada(['descripcion' => $descripcion]))->assertUnprocessable()->assertJsonValidationErrors('descripcion');
        }
        $this->postJson('/api/incidentes', $this->entrada(['afectado_tipo' => 'App\\Models\\Usuario']))->assertUnprocessable();
        $this->postJson('/api/incidentes', $this->entrada(['afectado_id' => 999999]))->assertNotFound();
        $this->postJson('/api/incidentes', $this->entrada(['pedidoid' => 999999]))->assertUnprocessable();
        $this->postJson('/api/incidentes', $this->entrada(['externo_envio_id' => 'OTRO-CODIGO']))->assertUnprocessable();
        $this->postJson('/api/incidentes', $this->entrada(['estado' => 'resuelto', 'reportadopor_usuarioid' => 1]))->assertUnprocessable();
        $this->assertSame(0, IncidenteEnvio::count());
    }

    public function test_responsable_ajeno_o_sin_permiso_no_es_elegible(): void
    {
        $ajeno = CertificadosFixture::usuario('jefe_agricultor', 'ajeno53');
        $ajeno->givePermissionTo(['incidentes.view', 'incidentes.resolve']);
        $this->actingAs($this->f['conductor']);
        foreach ([null, $ajeno->getKey(), $this->f['conductor']->getKey()] as $responsable) {
            $this->postJson('/api/incidentes', $this->entrada(['responsable_usuarioid' => $responsable]))->assertUnprocessable()->assertJsonValidationErrors('responsable_usuarioid');
        }
        $this->assertSame(0, IncidenteEnvio::count());
    }

    public function test_pendientes_resueltos_paginacion_y_ambitos_se_conservan(): void
    {
        $i = $this->crear();
        foreach (['pendiente', 'resuelto'] as $estado) {
            $copia = $i->replicate();
            $copia->estado = $estado;
            $copia->save();
        }
        $this->actingAs($this->f['conductor'])->getJson('/api/incidentes?estado=pendiente&per_page=1')->assertOk()
            ->assertJsonPath('total', 1)->assertJsonCount(1, 'data')->assertJsonPath('data.0.estado', 'pendiente');
        $this->getJson('/api/incidentes?estado=resuelto')->assertOk()->assertJsonPath('total', 1);
        $this->getJson('/api/incidentes?per_page=1&page=2')->assertOk()->assertJsonPath('total', 3)->assertJsonCount(1, 'data');
        $this->getJson('/api/incidentes?estado=cancelado')->assertUnprocessable();
        $ajeno = CertificadosFixture::usuario('transportista', 'otroChofer53');
        $this->actingAs($ajeno)->getJson('/api/incidentes')->assertOk()->assertJsonPath('total', 0);
        $this->getJson('/api/incidentes/'.$i->getKey())->assertNotFound();
    }

    public function test_resolucion_reintento_equivalente_y_conflicto_preservan_cierre_y_descripcion(): void
    {
        $i = $this->crear();
        $url = '/api/incidentes/'.$i->getKey().'/resolver';
        $this->actingAs($this->f['remitente'])->patchJson($url, ['nota_resolucion' => '  Se coordinó la entrega.  '])->assertOk()
            ->assertJsonPath('estado', 'resuelto')->assertJsonPath('nota_resolucion', 'Se coordinó la entrega.')
            ->assertJsonPath('resueltopor_usuarioid', $this->f['remitente']->getKey());
        $cerrado = $i->fresh()->getAttributes();
        $this->patchJson($url, ['nota_resolucion' => 'Se coordinó la entrega.'])->assertOk();
        $this->patchJson($url, ['nota_resolucion' => 'Cambiar solución anterior'])->assertConflict();
        $this->assertSame($cerrado, $i->fresh()->getAttributes());
        $this->assertSame('Demora registrada en el trayecto.', $i->fresh()->descripcion);
        $this->assertSame($this->f['conductor']->getKey(), $i->fresh()->reportadopor_usuarioid);
    }

    public function test_resolver_exige_explicacion_permiso_y_responsable(): void
    {
        $i = $this->crear();
        $url = '/api/incidentes/'.$i->getKey().'/resolver';
        $this->actingAs($this->f['remitente']);
        foreach ([null, '', '  ', str_repeat('x', 2001)] as $nota) {
            $this->patchJson($url, ['nota_resolucion' => $nota])->assertUnprocessable();
        }
        $this->actingAs($this->f['conductor'])->patchJson($url, ['nota_resolucion' => 'No autorizado'])->assertForbidden();
        $this->assertSame('abierto', $i->fresh()->estado);
        $this->assertNull($i->fresh()->fecha_resolucion);
    }

    public function test_ruta_anidada_no_admite_incidente_de_otra_operacion(): void
    {
        $i = $this->crear();
        $this->actingAs($this->f['conductor'])->getJson('/api/incidentes/afectados/envio_agricola/'.$this->f['envio']->getKey().'/'.$i->getKey())
            ->assertOk()->assertJsonPath('incidenteenvioid', $i->getKey());
        $this->getJson('/api/incidentes/afectados/pedido_agricola/'.$this->f['pedido']->getKey().'/'.$i->getKey())->assertNotFound();
    }

    public function test_fallo_de_persistencia_revierte_estado_y_campos_de_resolucion(): void
    {
        $i = $this->crear();
        DB::unprepared("CREATE TRIGGER fallo_incidente53 BEFORE UPDATE ON incidente_envio WHEN NEW.estado = 'resuelto' BEGIN SELECT RAISE(ABORT, 'fallo simulado'); END");
        try {
            app(IncidenteSeguimientoService::class)->resolver($this->f['remitente'], $i->getKey(), 'Solución válida');
            $this->fail('La persistencia debía fallar.');
        } catch (\Illuminate\Database\QueryException $e) {
            $this->assertStringContainsString('fallo simulado', $e->getMessage());
        } finally {
            DB::unprepared('DROP TRIGGER fallo_incidente53');
        }
        $this->assertSame('abierto', $i->fresh()->estado);
        $this->assertNull($i->fresh()->nota_resolucion);
        $this->assertNull($i->fresh()->fecha_resolucion);
    }

    public function test_consulta_y_resolucion_no_cambian_stock_pedido_qr_o_recepcion(): void
    {
        $i = $this->crear();
        $antes = [$this->f['pedido']->fresh()->getAttributes(), $this->f['envio']->fresh()->getAttributes(),
            $this->f['qr']->fresh()->getAttributes(), AlmacenMovimiento::count()];
        $this->actingAs($this->f['remitente'])->getJson('/api/incidentes/'.$i->getKey())->assertOk();
        $this->patchJson('/api/incidentes/'.$i->getKey().'/resolver', ['nota_resolucion' => 'Atendido sin alterar operaciones.'])->assertOk();
        $this->assertSame($antes, [$this->f['pedido']->fresh()->getAttributes(), $this->f['envio']->fresh()->getAttributes(),
            $this->f['qr']->fresh()->getAttributes(), AlmacenMovimiento::count()]);
    }

    public function test_web_y_api_coinciden_escapan_texto_y_no_admiten_cierre_por_update_generico(): void
    {
        $i = app(IncidenteSeguimientoService::class)->registrar($this->f['conductor'], $this->entrada(['descripcion' => '<script>alert("problema")</script>']));
        $web = $this->actingAs($this->f['remitente'])->get(route('logistica.incidentes.show', $i))->assertOk()
            ->assertSee('<script>alert("problema")</script>')->assertDontSee('<script>alert("problema")</script>', false)
            ->assertSee('Pendiente de resolución')->assertSee($this->f['remitente']->nombre);
        if (getenv('ISSUE53_CAPTURAR')) {
            file_put_contents(storage_path('app/private/issue53-detalle.html'), $web->getContent());
        }
        $this->put(route('logistica.incidentes.update', $i), ['tipo' => 'Retraso', 'descripcion' => $i->descripcion,
            'estado' => 'resuelto', 'nota_resolucion' => 'Eludir transición'])->assertSessionHasErrors(['estado', 'nota_resolucion']);
        $this->assertSame('abierto', $i->fresh()->estado);
        $this->from(route('logistica.incidentes.show', $i))->patch(route('logistica.incidentes.resolve', $i), ['nota_resolucion' => '   '])
            ->assertSessionHasErrors('nota_resolucion');
        $this->patch(route('logistica.incidentes.resolve', $i), ['nota_resolucion' => 'Entrega reprogramada con el destinatario.'])->assertRedirect();
        $this->get(route('logistica.incidentes.show', $i))->assertOk()->assertSee('Entrega reprogramada con el destinatario.');
        $this->getJson('/api/incidentes/'.$i->getKey())->assertOk()->assertJsonPath('nota_resolucion', 'Entrega reprogramada con el destinatario.');
        $this->putJson('/api/incidentes/'.$i->getKey(), ['estado' => 'resuelto'])->assertStatus(405);
    }

    public function test_ruta_mixta_no_comparte_incidencias_entre_destinatarios(): void
    {
        $f = EnvioQrFixture::crear('distribucion', true);
        $f['remitente']->givePermissionTo(['incidentes.view', 'incidentes.update', 'incidentes.resolve']);
        $a = $f['envio']->pedidos()->orderBy('pedidodistribucionid')->firstOrFail();
        $b = $f['envio']->pedidos()->orderByDesc('pedidodistribucionid')->firstOrFail();
        $service = app(IncidenteSeguimientoService::class);
        $base = ['tipo' => 'Entrega', 'responsable_usuarioid' => $f['remitente']->getKey()];
        $propia = $service->registrar($f['conductor'], [...$base, 'afectado_tipo' => 'pedido_distribucion', 'afectado_id' => $a->getKey(), 'descripcion' => 'Problema exclusivo A']);
        $ajena = $service->registrar($f['conductor'], [...$base, 'afectado_tipo' => 'pedido_distribucion', 'afectado_id' => $b->getKey(), 'descripcion' => 'Problema exclusivo B']);
        $ruta = $service->registrar($f['conductor'], [...$base, 'afectado_tipo' => 'distribucion', 'afectado_id' => $f['envio']->getKey(), 'descripcion' => 'Problema de todo el viaje']);
        $f['receptor']->givePermissionTo(['incidentes.view', 'pedidos_distribucion.view']);
        $this->actingAs($f['receptor'])->getJson('/api/incidentes')->assertOk()->assertJsonPath('total', 1)
            ->assertJsonPath('data.0.incidenteenvioid', $propia->getKey())->assertDontSee('Problema exclusivo B')->assertDontSee('Problema de todo el viaje');
        $this->getJson('/api/incidentes/'.$ajena->getKey())->assertNotFound();
        $this->getJson('/api/incidentes/'.$ruta->getKey())->assertNotFound();
    }

    public function test_autenticacion_y_permiso_de_incidentes_se_comprueban_por_separado(): void
    {
        $i = $this->crear();
        $this->getJson('/api/incidentes')->assertUnauthorized();
        $this->getJson('/api/incidentes/'.$i->getKey())->assertUnauthorized();
        $sinPermiso = CertificadosFixture::usuario('planta', 'sinIncidencias53');
        $this->actingAs($sinPermiso)->getJson('/api/incidentes')->assertForbidden();
        $this->f['remitente']->roles->first()->revokePermissionTo('incidentes.resolve');
        $this->f['remitente']->unsetRelation('roles');
        $this->actingAs($this->f['remitente'])->patchJson('/api/incidentes/'.$i->getKey().'/resolver', ['nota_resolucion' => 'Sin permiso'])->assertForbidden();
        $this->assertSame('abierto', $i->fresh()->estado);
    }

    public function test_roles_reales_atienden_solo_su_tipo_y_operacion_sin_permisos_directos(): void
    {
        $service = app(IncidenteSeguimientoService::class);
        foreach (['agricola' => 'envio_agricola', 'traslado' => 'traslado', 'distribucion' => 'distribucion'] as $viaje => $tipo) {
            $f = $viaje === 'agricola' ? $this->f : EnvioQrFixture::crear($viaje);
            $datos = ['tipo' => 'Retraso', 'descripcion' => 'Atención por ámbito real', 'afectado_tipo' => $tipo,
                'afectado_id' => $f['envio']->getKey(), 'responsable_usuarioid' => $f['remitente']->getKey()];
            $this->assertSame([], $f['remitente']->getDirectPermissions()->pluck('name')->all());
            $this->assertSame([$f['remitente']->getKey()], array_column($service->responsables($tipo, $f['envio']), 'usuarioid'));
            $i = $service->registrar($f['conductor'], $datos);
            $this->actingAs($f['remitente'])->getJson('/api/incidentes/'.$i->getKey())->assertOk()->assertJsonPath('puede_resolver', true);
            $this->get(route('logistica.incidentes.show', $i))->assertOk()->assertSee('Confirmar resolución');
            $this->actingAs($f['receptor'])->getJson('/api/incidentes/'.$i->getKey())->assertStatus($viaje === 'distribucion' ? 403 : 404);
            $this->actingAs($f['conductor'])->patchJson('/api/incidentes/'.$i->getKey().'/resolver', ['nota_resolucion' => 'No permitido'])->assertForbidden();
            // Even a direct resolution permission cannot turn a driver into a domain chief.
            $f['conductor']->givePermissionTo('incidentes.resolve');
            $this->patchJson('/api/incidentes/'.$i->getKey().'/resolver', ['nota_resolucion' => 'Permiso sin rol de atención'])->assertForbidden();
            $this->actingAs($f['remitente'])->patchJson('/api/incidentes/'.$i->getKey().'/resolver', ['nota_resolucion' => 'Atendido por responsable de origen.'])->assertOk();
        }
    }

    public function test_solo_el_rol_de_atencion_puede_asignar_un_reporte_pendiente(): void
    {
        $i = $this->crear();
        $i->update(['responsable_usuarioid' => null]);
        $datos = ['tipo' => $i->tipo, 'descripcion' => $i->descripcion, 'responsable_usuarioid' => $this->f['remitente']->getKey()];
        $this->actingAs($this->f['conductor'])->put(route('logistica.incidentes.update', $i), $datos)->assertForbidden();
        $this->assertNull($i->fresh()->responsable_usuarioid);
        $this->actingAs($this->f['remitente'])->put(route('logistica.incidentes.update', $i), $datos)->assertRedirect();
        $this->assertSame($this->f['remitente']->getKey(), $i->fresh()->responsable_usuarioid);
        $ajeno = CertificadosFixture::usuario('jefe_agricultor', 'sinOperacion53');
        $this->actingAs($ajeno)->getJson('/api/incidentes/'.$i->getKey())->assertNotFound();
    }

    public function test_migracion_aditiva_preserva_admin_y_transportista_y_no_crea_roles(): void
    {
        $roles = \Spatie\Permission\Models\Role::orderBy('id')->pluck('name', 'id')->all();
        $permisos = fn ($nombre) => \Spatie\Permission\Models\Role::findByName($nombre)->permissions()->orderBy('name')->pluck('name')->all();
        $admin = $permisos('admin');
        $conductor = $permisos('transportista');
        $migration = require database_path('migrations/2026_11_20_180000_habilitar_atencion_incidencias_por_ambito.php');
        $migration->up();
        $migration->up();
        $this->assertSame($roles, \Spatie\Permission\Models\Role::orderBy('id')->pluck('name', 'id')->all());
        $this->assertSame($admin, $permisos('admin'));
        $this->assertSame($conductor, $permisos('transportista'));
        foreach (['jefe_agricultor', 'jefe_planta', 'mayorista', 'jefe_mayorista'] as $rol) {
            $this->assertTrue(\Spatie\Permission\Models\Role::findByName($rol)->hasAllPermissions(['incidentes.view', 'incidentes.update', 'incidentes.resolve']));
        }
    }

    public function test_codigo_historico_ambiguo_no_concede_acceso_a_incidente_de_otro_autor(): void
    {
        $otro = CertificadosFixture::usuario('transportista', 'autorLegado53');
        $i = IncidenteEnvio::create(['externo_envio_id' => $this->f['envio']->externo_envio_id,
            'reportadopor_usuarioid' => $otro->getKey(), 'tipo' => 'Otro viaje', 'descripcion' => 'Antecedente ajeno sin FK tipificada', 'estado' => 'abierto']);
        $this->actingAs($this->f['conductor'])->getJson('/api/incidentes')->assertOk()->assertJsonPath('total', 0);
        $this->getJson('/api/incidentes/'.$i->getKey())->assertNotFound();
        $this->actingAs($otro)->getJson('/api/incidentes/'.$i->getKey())->assertOk()
            ->assertJsonPath('afectado', null)->assertJsonPath('externo_envio_id', null)->assertJsonPath('responsable', null);
    }
}
