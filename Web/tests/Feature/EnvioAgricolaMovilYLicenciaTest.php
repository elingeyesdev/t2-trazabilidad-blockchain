<?php

namespace Tests\Feature;

use App\Models\TipoVehiculo;
use App\Models\Vehiculo;
use App\Services\TransporteCapacidadService;
use App\Support\PedidoCatalogo;
use App\Support\TransportistaFlotaCatalogo;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\EscenarioComercialLogistica;
use Tests\Support\CertificadosFixture;
use Tests\TestCase;

class EnvioAgricolaMovilYLicenciaTest extends TestCase
{
    use EscenarioComercialLogistica, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
    }

    public function test_licencia_invalida_en_usuario_usa_respaldo_del_perfil_transportista(): void
    {
        $chofer = $this->conductor(TransportistaFlotaCatalogo::AGRICOLA);
        $chofer->forceFill(['tipo_licencia' => 'M', 'licencias_json' => null])->save();
        $chofer->perfilTransportista->forceFill(['tipo_licencia' => 'C', 'licencias_json' => null])->save();

        $capacidad = app(TransporteCapacidadService::class);
        $this->assertSame(['C'], $capacidad->licenciasTransportista($chofer->fresh('perfilTransportista')));

        $tipo = TipoVehiculo::create(['nombre' => 'Camión grande test', 'capacidad_kg' => 10000, 'capacidad_m3' => 40, 'licencia_requerida' => 'C']);
        $vehiculo = Vehiculo::create(['placa' => 'LIC-001', 'marca' => 'Volvo', 'modelo' => 'FH', 'tipovehiculoid' => $tipo->getKey(), 'activo' => true, 'ambito_flota' => 'agricola']);

        $capacidad->validarAsignacion($chofer->fresh('perfilTransportista'), $vehiculo);
        $this->assertTrue(true);
    }

    public function test_formulario_movil_agricola_acota_almacenes_calcula_costo_valida_capacidad_y_crea_envio_visible_en_web(): void
    {
        $f = CertificadosFixture::crear();
        $jefe = $f['agricola'];
        $otroJefe = $this->actor('jefe_agricultor');

        $miAlmacen = $this->almacen('agricola', $jefe, 'Almacen Propio Norte');
        $miAlmacen->update(['ubicacion' => 'Calle Norte · GPS -17.75304, -63.16598']);
        $almacenAjeno = $this->almacen('agricola', $otroJefe, 'Almacen Ajeno Sur');
        $planta = $this->almacen('planta', $f['planta'], 'Planta Industrial Central');
        $planta->update(['ubicacion' => 'Parque Industrial · GPS -17.80250, -63.14580']);

        $cosechaPropia = $f['cosechas'][0];
        $cosechaPropia->update(['almacenid' => $miAlmacen->getKey(), 'cantidad' => '500', 'fechasalida' => null]);

        if (isset($f['cosechas'][1])) {
            $f['cosechas'][1]->update(['almacenid' => $almacenAjeno->getKey(), 'cantidad' => '300', 'fechasalida' => null]);
        }

        $chofer = $this->conductor(TransportistaFlotaCatalogo::AGRICOLA);
        $chofer->forceFill(['tipo_licencia' => 'M', 'licencias_json' => null])->save();
        $chofer->perfilTransportista->forceFill(['tipo_licencia' => 'C', 'licencias_json' => null])->save();

        $tipo = TipoVehiculo::create(['nombre' => 'Camión mediano test', 'capacidad_kg' => 3500, 'capacidad_m3' => 15, 'licencia_requerida' => 'C']);
        $vehiculo = Vehiculo::create(['placa' => 'MOV-101', 'marca' => 'Ford', 'modelo' => 'Ranger', 'tipovehiculoid' => $tipo->getKey(), 'activo' => true, 'ambito_flota' => 'agricola']);

        // 1. Formulario móvil devuelve solo el almacén y productos propios del jefe agrícola.
        $formResp = $this->actingAs($jefe)->getJson('/api/pedidos-agricolas/formulario')->assertOk();
        $origenIds = collect($formResp->json('data.almacenes_origen'))->pluck('id')->all();
        $this->assertSame([$miAlmacen->getKey()], $origenIds);
        $this->assertNotContains($almacenAjeno->getKey(), $origenIds);
        $this->assertContains($planta->getKey(), collect($formResp->json('data.almacenes_destino'))->pluck('id')->all());
        $this->assertContains('cosecha:'.$cosechaPropia->getKey(), collect($formResp->json('data.productos'))->pluck('producto_ref')->all());
        $this->assertContains($chofer->getKey(), collect($formResp->json('data.transportistas'))->pluck('id')->all());
        $this->assertContains($vehiculo->getKey(), collect($formResp->json('data.vehiculos'))->pluck('id')->all());

        // 2. Selector web productos-pedido también acota al jefe agrícola.
        $webProdResp = $this->actingAs($jefe)->getJson('/catalogo-selector/productos-pedido')->assertOk();
        $webProdAlmacenes = collect($webProdResp->json('data'))->pluck('extra.almacenid')->unique()->values()->all();
        $this->assertSame([$miAlmacen->getKey()], $webProdAlmacenes);

        // 3. Cálculo de costo y validación de capacidad desde API móvil.
        $costoResp = $this->actingAs($jefe)->postJson('/api/pedidos-agricolas/calcular-costo', [
            'paradas' => [
                ['lat' => -17.75304, 'lng' => -63.16598],
                ['lat' => -17.80250, 'lng' => -63.14580],
            ],
        ])->assertOk();
        $costoBs = (int) $costoResp->json('data.costo_bs');
        $this->assertGreaterThan(0, $costoBs);

        $this->actingAs($jefe)->postJson('/api/pedidos-agricolas/validar-capacidad', [
            'vehiculo_id' => $vehiculo->getKey(),
            'peso_kg' => 250,
            'volumen_m3' => 1.25,
        ])->assertOk()->assertJsonPath('data.ok', true);

        $this->actingAs($jefe)->postJson('/api/pedidos-agricolas/validar-capacidad', [
            'vehiculo_id' => $vehiculo->getKey(),
            'peso_kg' => 5000,
        ])->assertOk()->assertJsonPath('data.ok', false);

        // 4. Crear envío desde API móvil con el chofer de licencia M/C y verificar que aparece en listado web.
        $createResp = $this->actingAs($jefe)->postJson('/api/pedidos-agricolas', [
            'origen_almacenid' => $miAlmacen->getKey(),
            'origen_latitud' => -17.75304,
            'origen_longitud' => -63.16598,
            'origen_direccion' => 'Almacen Propio Norte',
            'latitud' => -17.80250,
            'longitud' => -63.14580,
            'direccion_texto' => 'Planta Industrial Central',
            'fechaEntregaDeseada' => now()->addDay()->toDateString(),
            'hora_recogida' => '08:30',
            'transportista_usuarioid' => $chofer->getKey(),
            'vehiculoid' => $vehiculo->getKey(),
            'costo_bs' => $costoBs,
            'detalles' => [[
                'producto_ref' => 'cosecha:'.$cosechaPropia->getKey(),
                'cantidad' => '50',
                'observaciones' => PedidoCatalogo::construirMetaCargaObservaciones('kg', '50', 'Caja de cartón', 'Mediano'),
            ]],
        ])->assertCreated();

        $numeroSolicitud = $createResp->json('data.numero_solicitud');
        $createResp->assertJsonPath('data.envio.vehiculo_placa', 'MOV-101');
        $createResp->assertJsonPath('data.origen.direccion', 'Almacen Propio Norte');

        // 5. El envío recién creado debe aparecer en el listado unificado web del jefe agrícola.
        $this->actingAs($jefe)
            ->get('/logistica/asignaciones/listado')
            ->assertOk()
            ->assertSee($numeroSolicitud);
    }
}
