<?php

namespace Tests\Feature;

use App\Models\AlmacenMovimiento;
use App\Models\FirmaRecepcionEnvio;
use App\Models\Insumo;
use App\Models\MateriaPrimaLote;
use App\Support\PedidoMovilAcceso;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Support\EnvioQrFixture;
use Tests\TestCase;

class RecepcionAgricolaDashboardTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        Storage::fake('local');
    }

    private function caso(): array
    {
        $f = EnvioQrFixture::crear();
        $f['pedido']->update(['numero_solicitud' => 'PED-20261126-0001']);
        $f['detalle']->update(['cultivo_personalizado' => 'Fresa', 'cantidad' => '20.000000']);

        return $f;
    }

    private function datos(array $f, string $cantidad = '18.500000'): array
    {
        return ['imagen_firma' => EnvioQrFixture::firma(),
            'lineas' => [['id' => $f['detalle']->getKey(), 'cantidad_recibida' => $cantidad]]];
    }

    public function test_jefe_destino_recibe_desde_dashboard_con_pesaje_firma_y_un_solo_ingreso(): void
    {
        $f = $this->caso();
        $url = route('recepcion.planta', $f['envio']->getKey(), absolute: false);
        // Reproduce el 403 original: el jefe receptor no creó el pedido ni gestiona su origen.
        $this->assertFalse(PedidoMovilAcceso::agricola($f['pedido']->newQuery()->whereKey($f['pedido']->getKey()), $f['receptor'])->exists());
        $dashboard = $this->actingAs($f['receptor'])->get(route('dashboard'))->assertOk()
            ->assertSee('Recibir envío')->assertSee($url, false);
        $this->assertSame($url, $dashboard->viewData('envios_pendientes_planta')[0]['url']);
        $this->get(route('logistica.asignaciones.show', $f['envio']))->assertForbidden();
        $this->get($url)->assertOk()->assertSee('PED-20261126-0001')->assertSee('Fresa')
            ->assertSee('20 kg')->assertSee('Firma del destinatario')
            ->assertSee(route('recepcion.planta.confirmar', $f['envio']->getKey(), absolute: false), false);
        $this->assertNull($f['qr']->fresh()->utilizado_en);

        $this->post($url, $this->datos($f))->assertSessionHasNoErrors()->assertRedirect($url);
        $this->get($url)->assertOk()->assertSee('Entrega finalizada')->assertSee('Ver comprobante');
        $envio = $f['envio']->fresh();
        $this->assertNotNull($envio->fecha_recepcion_planta);
        $this->assertSame($f['receptor']->getKey(), $envio->recepcion_usuarioid);
        $this->assertSame('recibido_planta', $envio->estado);
        $this->assertSame($f['receptor']->getKey(), FirmaRecepcionEnvio::sole()->firmante_usuarioid);
        $this->assertSame(1, AlmacenMovimiento::count());
        $this->assertSame(1, MateriaPrimaLote::count());
        $this->assertEquals(18.5, Insumo::where('almacenid', $f['almacen']->getKey())->sole()->stock);
        $this->assertEquals(18.5, AlmacenMovimiento::sole()->cantidad);
        $qr = $f['qr']->fresh();
        $this->assertNotNull($qr->utilizado_en);
        Storage::disk('local')->assertExists($qr->firma_path);
        $this->assertSame('18.500000', $qr->datos_recepcion['lineas'][0]['cantidad_recibida']);

        $archivos = Storage::disk('local')->allFiles();
        $this->post($url, $this->datos($f))->assertStatus(409);
        $this->post(route('recepcion.publica.firmar', $qr->token), $this->datos($f))->assertStatus(409);
        $this->assertSame(1, FirmaRecepcionEnvio::count());
        $this->assertSame(1, AlmacenMovimiento::count());
        $this->assertSame(1, MateriaPrimaLote::count());
        $this->assertSame($archivos, Storage::disk('local')->allFiles());
        $this->assertEquals(18.5, Insumo::where('almacenid', $f['almacen']->getKey())->sole()->stock);
        $this->get(route('recepcion.publica', $qr->token))->assertOk()->assertSee('Entrega finalizada');
        $this->assertSame([], $this->get(route('dashboard'))->assertOk()->viewData('envios_pendientes_planta'));
    }

    public function test_otro_jefe_de_planta_no_ve_el_aviso_ni_recibe_por_dashboard_o_qr(): void
    {
        $f = $this->caso();
        $otro = EnvioQrFixture::crear();
        $url = route('recepcion.planta', $f['envio']->getKey(), absolute: false);
        $dashboard = $this->actingAs($otro['receptor'])->get(route('dashboard'))->assertOk();
        $this->assertNotContains($url, array_column($dashboard->viewData('envios_pendientes_planta'), 'url'));
        $this->get($url)->assertNotFound();
        $this->post($url, $this->datos($f))->assertNotFound();
        $this->get(route('recepcion.publica', $f['qr']->token))->assertNotFound();
        $this->post(route('recepcion.publica.firmar', $f['qr']->token), $this->datos($f))->assertNotFound();
        $this->assertNull($f['qr']->fresh()->utilizado_en);
        $this->assertNull($f['envio']->fresh()->fecha_recepcion_planta);
        $this->assertSame(0, FirmaRecepcionEnvio::count());
        $this->assertSame(0, AlmacenMovimiento::count());
    }

    public function test_recepcion_rechaza_si_falta_llegada_incidentes_o_firma_del_chofer(): void
    {
        foreach (['llegada', 'incidentes', 'firma'] as $faltante) {
            $f = EnvioQrFixture::crear();
            if ($faltante === 'llegada') {
                $f['envio']->update(['llegada_confirmada_at' => null]);
            } elseif ($faltante === 'incidentes') {
                $f['envio']->checklistIncidente()->delete();
            } else {
                $f['envio']->firmaTransportista()->delete();
            }
            $url = route('recepcion.planta', $f['envio']->getKey(), absolute: false);
            $dashboard = $this->actingAs($f['receptor'])->get(route('dashboard'))->assertOk();
            $this->assertFalse($dashboard->viewData('envios_pendientes_planta')[0]['puede_recibir']);
            $this->get($url)->assertStatus(409);
            $this->postJson($url, $this->datos($f))->assertUnprocessable()->assertJsonValidationErrors('envio');
            $this->assertNull($f['qr']->fresh()->utilizado_en);
        }
        $this->assertSame(0, FirmaRecepcionEnvio::count());
        $this->assertSame(0, AlmacenMovimiento::count());
        $this->assertSame([], Storage::disk('local')->allFiles());
    }

    public function test_validacion_de_cantidad_y_firma_no_ingresa_stock_y_conserva_formulario(): void
    {
        $f = $this->caso();
        $url = route('recepcion.planta', $f['envio']->getKey(), absolute: false);
        $this->actingAs($f['receptor'])->from($url)->post($url, $this->datos($f, '21'))->assertRedirect($url)->assertSessionHasErrors('lineas.'.$f['detalle']->getKey().'.cantidad_recibida');
        $this->get($url)->assertOk()->assertSee('No puede recibir más de lo enviado.');
        $datos = $this->datos($f);
        unset($datos['imagen_firma']);
        $this->postJson($url, $datos)->assertUnprocessable()->assertJsonValidationErrors('imagen_firma');
        $this->assertSame(0, FirmaRecepcionEnvio::count());
        $this->assertSame(0, AlmacenMovimiento::count());
        $this->assertNull($f['qr']->fresh()->utilizado_en);
    }

    public function test_ruta_directa_conserva_permiso_de_confirmacion_y_no_permite_al_chofer_firmar_recepcion(): void
    {
        $f = $this->caso();
        $url = route('recepcion.planta', $f['envio']->getKey(), absolute: false);
        $this->get($url)->assertRedirect(route('login'));
        $this->actingAs($f['conductor'])->get($url)->assertForbidden();
        $this->post($url, $this->datos($f))->assertForbidden();
        $f['receptor']->roles()->first()->revokePermissionTo('recepcion_planta.confirm');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();
        $this->actingAs($f['receptor']->fresh())->get($url)->assertForbidden();
        $this->post($url, $this->datos($f))->assertForbidden();
        $this->assertFalse($this->get(route('dashboard'))->assertOk()->viewData('envios_pendientes_planta')[0]['puede_recibir']);
        $this->assertSame(0, AlmacenMovimiento::count());
        $this->assertNull($f['qr']->fresh()->utilizado_en);
    }
}
