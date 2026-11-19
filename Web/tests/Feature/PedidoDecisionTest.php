<?php

namespace Tests\Feature;

use App\Models\AlmacenMovimiento;
use App\Models\PedidoDecision;
use App\Services\PedidoDistribucionReservaService;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Support\CertificadosFixture;
use Tests\Support\PedidoDecisionFixture as Fixture;
use Tests\TestCase;

class PedidoDecisionTest extends TestCase
{
    use RefreshDatabase;

    private array $f;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $this->f = Fixture::crear();
    }

    private function actor(string $tipo)
    {
        return $this->f[$tipo === 'agricolas' ? 'agricola' : 'mayorista'];
    }

    private function api(string $tipo, $pedido): string
    {
        return '/api/pedidos-'.$tipo.'/'.$pedido->getKey();
    }

    private function web(string $tipo, $pedido, string $accion): string
    {
        return $tipo === 'agricolas'
            ? route('logistica.asignaciones.'.$accion.'-pedido', $pedido->envioAsignacion)
            : route('punto-venta.pedidos.'.$accion, $pedido);
    }

    public function test_aceptacion_exacta_y_reintento_no_duplican_efectos(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo, '10.000000');
            $this->actingAs($this->actor($tipo));
            $movimientos = AlmacenMovimiento::count();
            foreach ([1, 2] as $vez) {
                $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'aceptar'])->assertOk()
                    ->assertJsonPath('data.estado', 'confirmado')->assertJsonPath('data.decision.accion', 'aceptar')
                    ->assertJsonPath('data.decision.usuarioid', $this->actor($tipo)->getKey())->assertJsonPath('data.acciones_disponibles', []);
            }
            $this->assertSame(1, $p->decisiones()->count());
            $this->assertSame($movimientos, AlmacenMovimiento::count());
            $this->assertEquals($tipo === 'agricolas' ? 0 : 10, $tipo === 'agricolas' ? $this->f['cosechas'][0]->fresh()->cantidad : $this->f['producto']->fresh()->stock);
            $this->get($tipo === 'agricolas' ? route('pedidos.show', $p) : route('punto-venta.pedidos.show', $p))->assertOk()->assertSee('Última decisión del pedido: Aceptado');
        }
    }

    public function test_rechazo_guarda_motivo_actor_fecha_y_conserva_stock_y_otras_reservas(): void
    {
        $reservado = Fixture::pedido($this->f, 'distribucion', '3.000000');
        $this->actingAs($this->actor('distribucion'))->postJson($this->api('distribucion', $reservado).'/transiciones', ['accion' => 'aceptar'])->assertOk();
        $movimientos = AlmacenMovimiento::count();
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            $this->actingAs($this->actor($tipo));
            foreach ([1, 2] as $vez) {
                $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'rechazar', 'motivo_rechazo' => '  No es posible atender la fecha.  '])
                    ->assertOk()->assertJsonPath('data.motivo_rechazo', 'No es posible atender la fecha.')->assertJsonPath('data.estado', 'rechazado')
                    ->assertJsonPath('data.decision.usuarioid', $this->actor($tipo)->getKey())->assertJsonPath('data.acciones_disponibles', []);
            }
            $this->assertNotNull($p->fresh()->ultimaDecision->fecha);
            $this->assertSame(1, $p->decisiones()->count());
            $this->get($tipo === 'agricolas' ? route('pedidos.show', $p) : route('punto-venta.pedidos.show', $p))->assertOk()->assertSee('No es posible atender la fecha.');
        }
        $this->assertEquals(10, $this->f['cosechas'][0]->fresh()->cantidad);
        $this->assertEquals(10, $this->f['producto']->fresh()->stock);
        $this->assertEquals(10, $this->f['partida']->fresh()->cantidad_unidades);
        $this->assertSame($movimientos, AlmacenMovimiento::count());
        $this->assertEquals(3, app(PedidoDistribucionReservaService::class)->reservado($this->f['origen']->getKey(), $this->f['producto']->getKey(), $this->f['presentacion']->getKey()));
    }

    public function test_motivos_invalidos_y_metadatos_impuestos_no_se_guardan(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            $this->actingAs($this->actor($tipo));
            foreach ([null, '', '   ', str_repeat('a', 501), ['objeto']] as $motivo) {
                $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'rechazar', 'motivo_rechazo' => $motivo])
                    ->assertUnprocessable()->assertJsonValidationErrors('motivo_rechazo');
            }
            foreach (['usuarioid' => 1, 'fecha' => '2000-01-01', 'estado' => 'rechazado', 'decision' => [], 'reservado' => 0] as $campo => $valor) {
                $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'rechazar', 'motivo_rechazo' => 'Prueba', $campo => $valor])->assertUnprocessable()->assertJsonValidationErrors($campo);
            }
            $this->assertSame(0, $p->decisiones()->count());
        }
    }

    public function test_conflictos_no_sobrescriben_la_decision(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            $this->actingAs($this->actor($tipo));
            $url = $this->api($tipo, $p).'/transiciones';
            $this->postJson($url, ['accion' => 'rechazar', 'motivo_rechazo' => 'Motivo original'])->assertOk();
            $this->postJson($url, ['accion' => 'rechazar', 'motivo_rechazo' => 'Otro motivo'])->assertConflict();
            $this->postJson($url, ['accion' => 'aceptar'])->assertConflict();
            $this->assertSame('Motivo original', $p->fresh()->ultimaDecision->motivo);
            $this->assertSame(1, $p->decisiones()->count());
            $aceptado = Fixture::pedido($this->f, $tipo, '1.000000');
            $this->postJson($this->api($tipo, $aceptado).'/transiciones', ['accion' => 'aceptar'])->assertOk();
            $this->postJson($this->api($tipo, $aceptado).'/transiciones', ['accion' => 'rechazar', 'motivo_rechazo' => 'Tardío'])->assertConflict();
            $this->assertSame('confirmado', $aceptado->fresh()->estado);
        }
    }

    public function test_web_rechaza_y_api_consulta_y_validacion_conserva_texto(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            $this->actingAs($this->actor($tipo));
            $texto = str_repeat('x', 501);
            $this->from('/origen')->post($this->web($tipo, $p, 'rechazar'), ['motivo_rechazo' => $texto])->assertRedirect('/origen')
                ->assertSessionHasErrors('motivo_rechazo')->assertSessionHasInput('motivo_rechazo', $texto);
            $this->post($this->web($tipo, $p, 'rechazar'), ['motivo_rechazo' => 'Motivo desde web'])->assertRedirect();
            $this->getJson($this->api($tipo, $p))->assertOk()->assertJsonPath('data.motivo_rechazo', 'Motivo desde web');
            $this->post($this->web($tipo, $p, 'rechazar'), ['motivo_rechazo' => 'Cambio no permitido'])->assertRedirect()->assertSessionHas('error');
        }
    }

    public function test_web_acepta_y_api_consulta_sin_otra_reserva(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            $this->actingAs($this->actor($tipo))->post($this->web($tipo, $p, 'aceptar'))->assertRedirect();
            $this->getJson($this->api($tipo, $p))->assertOk()->assertJsonPath('data.estado', 'confirmado')->assertJsonPath('data.decision.accion', 'aceptar');
            $this->assertSame(1, $p->decisiones()->count());
        }
    }

    public function test_autenticacion_ambito_y_rol_son_efectivos_y_acciones_no_se_muestran(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            auth()->forgetGuards();
            $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'aceptar'])->assertUnauthorized();
            $ajeno = CertificadosFixture::usuario($tipo === 'agricolas' ? 'jefe_agricultor' : 'mayorista', 'ajeno'.$tipo);
            $this->actingAs($ajeno)->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'aceptar'])->assertNotFound();
            $this->getJson($this->api($tipo, $p))->assertNotFound();
            $this->actingAs($this->f['admin'])->getJson($this->api($tipo, $p))->assertOk()->assertJsonPath('data.acciones_disponibles', []);
            $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'aceptar'])->assertForbidden();
            $this->actingAs($this->actor($tipo))->getJson($this->api($tipo, $p))->assertOk()->assertJsonPath('data.acciones_disponibles', ['aceptar', 'rechazar']);
            $this->putJson($this->api($tipo, $p), ['estado' => 'confirmado'])->assertStatus(405);
            if ($tipo === 'agricolas') {
                $this->putJson('/api/pedidos/'.$p->getKey(), ['estado' => 'confirmado'])->assertUnprocessable();
            }
        }
    }

    public function test_stock_insuficiente_o_vencido_no_deja_decision_parcial(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo, '11.000000');
            $this->actingAs($this->actor($tipo))->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'aceptar'])->assertUnprocessable();
            $this->assertSame(0, $p->decisiones()->count());
            $this->assertSame($tipo === 'agricolas' ? 'sin asignacion' : 'pendiente', $p->fresh()->estado);
        }
        $p = Fixture::pedido($this->f, 'distribucion');
        $this->f['partida']->update(['fecha_vencimiento' => now()->subDay()->toDateString()]);
        $this->postJson($this->api('distribucion', $p).'/transiciones', ['accion' => 'aceptar'])->assertUnprocessable();
        $this->assertSame(0, $p->decisiones()->count());
    }

    public function test_lineas_repetidas_acumulan_consumo_y_aceptan_solo_cuando_alcanza(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            $p->detalles->first()->replicate()->save();
            $this->actingAs($this->actor($tipo))->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'aceptar'])->assertUnprocessable();
            $this->assertSame(0, $p->decisiones()->count());
            foreach ($p->detalles()->get() as $linea) {
                $linea->update(['cantidad' => 5, 'datos_solicitud' => $tipo === 'agricolas' ? null : ['unidad' => 'bolsas', 'cantidad_kg' => '5.000000']]);
            }
            $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'aceptar'])->assertOk();
            $this->assertSame(1, $p->decisiones()->count());
        }
        $this->assertEquals(0, $this->f['cosechas'][0]->fresh()->cantidad);
        $this->assertEquals(10, $this->f['producto']->fresh()->stock);
    }

    public function test_permiso_revocado_impide_decidir_y_oculta_acciones(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            $actor = $this->actor($tipo);
            $permiso = $tipo === 'agricolas' ? 'pedidos.update' : 'pedidos_distribucion.update';
            $actor->roles->first()->revokePermissionTo($permiso);
            $this->actingAs($actor->fresh())->getJson($this->api($tipo, $p))->assertOk()->assertJsonPath('data.acciones_disponibles', []);
            $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => 'rechazar', 'motivo_rechazo' => 'Sin permiso'])->assertForbidden();
            $this->assertSame(0, $p->decisiones()->count());
        }
    }

    public function test_ser_creador_o_tener_origen_cabecera_no_autoriza_existencias_ajenas(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            if ($tipo === 'agricolas') {
                $this->f['cosechas'][0]->almacen->update(['responsable_usuarioid' => $this->f['planta']->getKey()]);
            } else {
                $this->f['producto']->update(['almacenid' => $this->f['almacen']->getKey()]);
            }
            $this->actingAs($this->actor($tipo))->getJson($this->api($tipo, $p))->assertOk()->assertJsonPath('data.acciones_disponibles', []);
            foreach (['aceptar', 'rechazar'] as $accion) {
                $this->postJson($this->api($tipo, $p).'/transiciones', ['accion' => $accion, 'motivo_rechazo' => 'Origen ajeno'])->assertForbidden();
            }
            $this->assertSame(0, $p->decisiones()->count());
        }
    }

    public function test_reserva_legada_acumula_lineas_y_respeta_la_reserva_en_presentacion(): void
    {
        $p = Fixture::pedido($this->f, 'distribucion');
        $linea = $p->detalles->first();
        $linea->update(['insumo_presentacionid' => null, 'inventario_presentacion_loteid' => null, 'datos_solicitud' => null]);
        $linea->replicate()->save();
        $this->actingAs($this->actor('distribucion'));
        try {
            \Illuminate\Support\Facades\DB::transaction(fn () => app(PedidoDistribucionReservaService::class)->reservar($p->fresh()));
            $this->fail('No debe reservar doce unidades con saldo diez.');
        } catch (\InvalidArgumentException $e) {
            $this->assertStringContainsString('acumuladas', $e->getMessage());
        }
        $otro = Fixture::pedido($this->f, 'distribucion');
        $this->postJson($this->api('distribucion', $otro).'/transiciones', ['accion' => 'aceptar'])->assertOk();
        $p->detalles()->whereKey($linea->getKey())->delete();
        try {
            \Illuminate\Support\Facades\DB::transaction(fn () => app(PedidoDistribucionReservaService::class)->reservar($p->fresh()));
            $this->fail('La reserva legada debe respetar las seis unidades ya reservadas.');
        } catch (\InvalidArgumentException $e) {
            $this->assertStringContainsString('acumuladas', $e->getMessage());
        }
        $this->assertEquals(10, $this->f['producto']->fresh()->stock);
    }

    public function test_fallo_al_registrar_decision_revierte_stock_estado_y_logistica(): void
    {
        $this->withoutExceptionHandling();
        PedidoDecision::creating(fn () => throw new \RuntimeException('Fallo de escritura de decisión'));
        try {
            foreach (['agricolas', 'distribucion'] as $tipo) {
                foreach (['aceptar', 'rechazar'] as $accion) {
                    $p = Fixture::pedido($this->f, $tipo);
                    try {
                        $this->actingAs($this->actor($tipo))->postJson($this->api($tipo, $p).'/transiciones', ['accion' => $accion, 'motivo_rechazo' => 'Prueba rollback']);
                        $this->fail('Se esperaba el fallo inyectado.');
                    } catch (\RuntimeException $e) {
                        $this->assertSame('Fallo de escritura de decisión', $e->getMessage());
                    }
                    $this->assertSame($tipo === 'agricolas' ? 'sin asignacion' : 'pendiente', $p->fresh()->estado);
                    if ($tipo === 'agricolas') {
                        $this->assertSame('pendiente', $p->fresh()->envioAsignacion->estado);
                    }
                }
            }
        } finally {
            PedidoDecision::flushEventListeners();
        }
        $this->assertEquals(10, $this->f['cosechas'][0]->fresh()->cantidad);
        $this->assertEquals(10, $this->f['producto']->fresh()->stock);
        $this->assertSame(0, PedidoDecision::count());
    }

    public function test_no_se_rechazan_despachos_ni_recepciones_aunque_cabecera_parezca_pendiente(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $p = Fixture::pedido($this->f, $tipo);
            if ($tipo === 'agricolas') {
                $p->envioAsignacion->update(['estado' => 'en_ruta', 'simulacion_inicio_at' => now()]);
            } else {
                $p->update(['fecha_recepcion' => now()]);
            }
            foreach (['aceptar', 'rechazar'] as $accion) {
                $this->actingAs($this->actor($tipo))->postJson($this->api($tipo, $p).'/transiciones', ['accion' => $accion, 'motivo_rechazo' => 'No debe aplicarse'])->assertConflict();
            }
            $this->assertSame(0, $p->decisiones()->count());
            $this->getJson($this->api($tipo, $p))->assertOk()->assertJsonPath('data.acciones_disponibles', []);
        }
    }
}
