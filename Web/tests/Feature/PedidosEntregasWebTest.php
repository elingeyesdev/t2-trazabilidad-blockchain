<?php

namespace Tests\Feature;

use App\Models\AlmacenMovimiento;
use App\Models\PedidoDistribucion;
use App\Models\RecepcionQrEnvio;
use App\Services\EnvioMovilConsultaService;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Support\CertificadosFixture;
use Tests\Support\EnvioQrFixture;
use Tests\Support\PedidoDecisionFixture;
use Tests\TestCase;

class PedidosEntregasWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        Storage::fake('local');
    }

    private function seguimiento(array $f): string
    {
        return route('envios.operacion', ['tipo' => $f['tipo'], 'envio' => $f['envio']->getKey()]);
    }

    public function test_bandejas_comparten_tabla_y_conservan_precision_filtros_y_acciones(): void
    {
        $f = PedidoDecisionFixture::crear();
        $p = PedidoDecisionFixture::pedido($f, 'distribucion', '1.123456');
        foreach ([$f['minorista'], $f['mayorista']] as $actor) {
            $res = $this->actingAs($actor)->get(route('punto-venta.pedidos.index'))->assertOk()->assertSee('op-tabla-movil')
                ->assertSee('1.123456')->assertSee('bolsas')->assertSee($p->numero_solicitud);
            if (getenv('EDT54_CAPTURE')) {
                file_put_contents(storage_path('app/private/edt54-bandeja.html'), $res->getContent());
            }
            $res->assertSee($actor->is($f['mayorista']) ? 'Revisar pedido' : 'Ver pedido');
            $this->get(route('punto-venta.pedidos.index', ['q' => 'NO-EXISTE-54']))->assertOk()->assertDontSee($p->numero_solicitud);
            $this->get(route('punto-venta.pedidos.index', ['q' => $p->numero_solicitud, 'hasta' => now()->toDateString()]))->assertOk()->assertSee($p->numero_solicitud);
            $this->get(route('punto-venta.pedidos.index', ['estado_grupo' => 'recibido']))->assertOk()->assertDontSee($p->numero_solicitud);
        }
        $ajeno = CertificadosFixture::usuario('minorista', 'ajeno54');
        $this->actingAs($ajeno)->get(route('punto-venta.pedidos.index', ['q' => $p->numero_solicitud]))->assertOk()->assertViewHas('pedidos', fn ($items) => $items->isEmpty());
    }

    public function test_busqueda_de_envios_y_fecha_son_funcionales_y_no_muestran_otros_choferes(): void
    {
        $f = EnvioQrFixture::crear('agricola');
        $otro = EnvioQrFixture::crear('agricola');
        $url = route('logistica.asignaciones.listado');
        $lista = $this->actingAs($f['conductor'])->get($url)->assertOk()->assertSee('op-tabla-movil')->assertSee($f['envio']->externo_envio_id)->assertSee('10.123456')->assertDontSee($otro['envio']->externo_envio_id);
        if (getenv('EDT54_CAPTURE')) {
            file_put_contents(storage_path('app/private/edt54-envios.html'), $lista->getContent());
        }
        $this->get($url.'?q=NO-EXISTE-54')->assertOk()->assertDontSee($f['envio']->externo_envio_id);
        $this->get($url.'?q='.$f['envio']->externo_envio_id.'&hasta='.now()->toDateString())->assertOk()->assertSee($f['envio']->externo_envio_id);
        $this->get($url.'?desde='.now()->addDay()->toDateString())->assertOk()->assertDontSee($f['envio']->externo_envio_id);
    }

    public function test_pedido_permite_consultar_entrega_mixta_sin_exponer_pedidos_ajenos(): void
    {
        $f = EnvioQrFixture::crear('distribucion', true);
        $propio = PedidoDistribucion::whereHas('puntoVenta', fn ($p) => $p->where('usuarioid', $f['receptor']->getKey()))->firstOrFail();
        $ajeno = PedidoDistribucion::where('pedidodistribucionid', '!=', $propio->getKey())->firstOrFail();
        $this->actingAs($f['receptor'])->get(route('punto-venta.pedidos.show', $propio))->assertOk()->assertSee($this->seguimiento($f), false);
        $antes = RecepcionQrEnvio::count();
        $movimientos = AlmacenMovimiento::count();
        $res = $this->get($this->seguimiento($f))->assertOk()->assertSee($propio->numero_solicitud)->assertDontSee($ajeno->numero_solicitud)->assertSee('5.123456')->assertSee('bolsas');
        $this->assertSame($antes, RecepcionQrEnvio::count());
        $this->assertSame($movimientos, AlmacenMovimiento::count());
        $this->assertNull($f['qr']->fresh()->utilizado_en);
        if (getenv('EDT54_CAPTURE')) {
            file_put_contents(storage_path('app/private/edt54-seguimiento.html'), $res->getContent());
        }
    }

    public function test_tres_tipos_muestran_comprobante_confirmado_y_protegen_su_acceso(): void
    {
        foreach (['agricola', 'distribucion', 'traslado'] as $tipo) {
            $f = EnvioQrFixture::crear($tipo);
            $this->actingAs($f['receptor'])->get($this->seguimiento($f))->assertOk()->assertDontSee('Abrir comprobante');
            $this->postJson('/api/envios/'.$tipo.'/'.$f['envio']->getKey().'/recepcion', [
                'codigo' => $f['qr']->token, 'imagen_firma' => EnvioQrFixture::firma(),
                'lineas' => array_map(fn ($l) => ['id' => $l['id'], 'cantidad_recibida' => $l['cantidad_enviada']], app(EnvioMovilConsultaService::class)->lineas($f['envio'], $f['receptor'])),
            ])->assertCreated();
            $comprobante = route('recepcion.comprobante', $f['qr']->getKey());
            $this->get($this->seguimiento($f))->assertOk()->assertSee('Recepción confirmada')->assertSee($comprobante, false);
            $this->get($comprobante)->assertOk()->assertHeader('Content-Type', 'application/pdf');
            $extra = CertificadosFixture::usuario($f['receptor']->getRoleNames()->first(), 'otro54'.$tipo);
            $this->actingAs($extra)->get($comprobante)->assertNotFound();
        }
    }

    public function test_sin_permiso_o_fuera_de_ambito_no_puede_consultar_y_no_ve_comprobante_de_otro_destinatario(): void
    {
        $f = EnvioQrFixture::crear('distribucion', true);
        $this->getJson($this->seguimiento($f))->assertUnauthorized();
        $ajeno = CertificadosFixture::usuario('minorista', 'privado54');
        $this->actingAs($ajeno)->get($this->seguimiento($f))->assertNotFound();
        $this->actingAs($f['receptor']);
        $otro = collect($f['qrs'])->first(fn ($q) => $q->getKey() !== $f['qr']->getKey());
        $otro->forceFill(['utilizado_en' => now(), 'firma_path' => 'otra.png', 'datos_recepcion' => ['ejemplo' => true]])->save();
        $this->get($this->seguimiento($f))->assertOk()->assertDontSee(route('recepcion.comprobante', $otro->getKey()), false);
        $f['receptor']->roles->first()->revokePermissionTo('pedidos_distribucion.view');
        $this->actingAs($f['receptor']->fresh())->get($this->seguimiento($f))->assertForbidden();
    }

    public function test_los_estados_y_acciones_cambian_tras_rechazo_y_no_se_pierde_el_motivo(): void
    {
        $f = PedidoDecisionFixture::crear();
        $p = PedidoDecisionFixture::pedido($f, 'distribucion');
        $this->actingAs($f['mayorista'])->post(route('punto-venta.pedidos.rechazar', $p), ['motivo_rechazo' => 'Fecha no disponible'])->assertRedirect();
        $this->get(route('punto-venta.pedidos.index'))->assertOk()->assertSee('Rechazado')->assertDontSee('Revisar pedido');
        $this->get(route('punto-venta.pedidos.show', $p))->assertOk()->assertSee('Fecha no disponible')->assertDontSee('Motivo del rechazo (obligatorio)');
    }

    public function test_fechas_invalidas_conservan_filtros_y_rechazan_rango_invertido(): void
    {
        $f = PedidoDecisionFixture::crear();
        $this->actingAs($f['minorista'])->from('/origen')->get(route('punto-venta.pedidos.index', ['desde' => '2026-11-20', 'hasta' => '2026-11-19', 'q' => 'Prueba']))->assertRedirect('/origen')->assertSessionHasErrors('hasta');
    }

    public function test_formularios_conservan_campos_validaciones_y_permiso_de_creacion(): void
    {
        $f = PedidoDecisionFixture::crear();
        $res = $this->actingAs($f['agricola'])->get(route('pedidos.create'))->assertOk()->assertSee('ag-pedidos-entregas')->assertSee('name="_token"', false);
        if (getenv('EDT54_CAPTURE')) {
            file_put_contents(storage_path('app/private/edt54-formulario.html'), $res->getContent());
        }
        $this->actingAs($f['minorista'])->get(route('punto-venta.pedidos.create', ['ctx' => 'pdv']))->assertOk()->assertSee('ag-pedidos-entregas')->assertSee('name="_token"', false);
        $this->actingAs($f['admin'])->get(route('pedidos.create'))->assertForbidden();
    }

    public function test_fecha_de_registro_localiza_rutas_que_aun_no_tienen_fecha_de_salida(): void
    {
        $f = EnvioQrFixture::crear('distribucion');
        $url = route('logistica.asignaciones.listado');
        $this->assertNull($f['envio']->fecha_salida);
        $this->actingAs($f['conductor'])->get($url.'?hasta='.now()->toDateString())->assertOk()->assertSee($f['envio']->codigo);
        $this->get($url.'?desde='.now()->addDay()->toDateString())->assertOk()->assertDontSee($f['envio']->codigo);
    }
}
