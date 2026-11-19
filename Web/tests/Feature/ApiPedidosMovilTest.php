<?php

namespace Tests\Feature;

use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\DetallePedido;
use App\Models\DetallePedidoDistribucion;
use App\Models\InsumoPresentacion;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\TipoVehiculo;
use App\Models\Vehiculo;
use App\Services\InventarioPresentacionService;
use App\Support\PedidoCatalogo;
use App\Support\TransportistaFlotaCatalogo;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\EscenarioComercialLogistica;
use Tests\Support\CertificadosFixture;
use Tests\TestCase;

class ApiPedidosMovilTest extends TestCase
{
    use EscenarioComercialLogistica, RefreshDatabase;

    private array $f;

    private $mayorista;

    private $minorista;

    private $producto;

    private $presentacion;

    private $partida;

    private array $agricola;

    private array $distribucion;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed([RolePermissionSeeder::class, CatalogosOperacionAgricolaSeeder::class]);
        $this->f = CertificadosFixture::crear();
        $agr = $this->almacen('agricola', $this->f['agricola'], 'Origen agrícola');
        $cosecha = $this->f['cosechas'][0];
        $cosecha->update(['almacenid' => $agr->getKey(), 'cantidad' => '100.123456', 'fechasalida' => null]);
        $chofer = $this->conductor(TransportistaFlotaCatalogo::AGRICOLA);
        $tipo = TipoVehiculo::create(['nombre' => 'Camión API51', 'capacidad_kg' => 10000, 'capacidad_m3' => 100, 'licencia_requerida' => 'C']);
        $vehiculo = Vehiculo::create(['placa' => 'API-51', 'marca' => 'Test', 'modelo' => 'Test', 'tipovehiculoid' => $tipo->getKey(), 'activo' => true, 'ambito_flota' => 'agricola']);
        $this->agricola = ['origen_almacenid' => $agr->getKey(), 'origen_latitud' => -17.7, 'origen_longitud' => -63.1,
            'latitud' => -17.8, 'longitud' => -63.2, 'direccion_texto' => 'Destino planta', 'fechaEntregaDeseada' => now()->addDay()->toDateString(),
            'transportista_usuarioid' => $chofer->getKey(), 'vehiculoid' => $vehiculo->getKey(), 'costo_bs' => 100,
            'detalles' => [['producto_ref' => 'cosecha:'.$cosecha->getKey(), 'cantidad' => '5.123456',
                'observaciones' => PedidoCatalogo::construirMetaCargaObservaciones('empaques', '1', 'Saco', 'Grande')]]];
        $this->mayorista = $this->actor('mayorista');
        $almacen = $this->almacenMayorista($this->mayorista, 'Mayorista API51');
        $this->producto = $this->productoTerminado($almacen, 'Conserva API51', 50);
        $this->presentacion = InsumoPresentacion::create(['insumoid' => $this->producto->getKey(), 'nombre' => 'Bolsa 500 g', 'tipo_envase' => 'bolsa', 'peso_neto_kg' => '0.5', 'activo' => true]);
        $this->partida = app(InventarioPresentacionService::class)->ingresar($almacen->getKey(), $this->producto->getKey(), $this->presentacion->getKey(), null, 'PARTIDA-51', 100, 50);
        $this->minorista = $this->actor('minorista');
        $pdv = $this->puntoVenta($this->minorista, 'Destino PDV51');
        $this->distribucion = ['puntoventaid' => $pdv->getKey(), 'almacen_mayorista_origenid' => $almacen->getKey(),
            'fecha_entrega_deseada' => now()->addDay()->toDateString(),
            'detalles' => [['insumoid' => $this->producto->getKey(), 'insumo_presentacionid' => $this->presentacion->getKey(),
                'inventario_presentacion_loteid' => $this->partida->getKey(), 'cantidad' => '2.123456']]];
    }

    private function entrada(string $tipo): array
    {
        return $tipo === 'agricolas' ? $this->agricola : $this->distribucion;
    }

    private function usuario(string $tipo)
    {
        return $tipo === 'agricolas' ? $this->f['agricola'] : $this->minorista;
    }

    private function crear(string $tipo, ?array $datos = null)
    {
        return $this->actingAs($this->usuario($tipo))->postJson('/api/pedidos-'.$tipo, $datos ?? $this->entrada($tipo));
    }

    public function test_creacion_detalle_listado_y_consulta_cruzada_web_para_ambos_tipos(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $response = $this->crear($tipo)->assertCreated()->assertJsonPath('data.estado', $tipo === 'agricolas' ? 'sin asignacion' : 'pendiente')
                ->assertJsonCount(1, 'data.detalles')->assertJsonPath('data.detalles.0.cantidad', $this->entrada($tipo)['detalles'][0]['cantidad']);
            $id = $response->json('data.id');
            $this->getJson('/api/pedidos-'.$tipo.'/'.$id)->assertOk()->assertJsonPath('data.id', $id);
            $this->getJson('/api/pedidos-'.$tipo.'?per_page=1')->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('meta.per_page', 1);
            $this->get($tipo === 'agricolas' ? route('pedidos.show', $id) : route('punto-venta.pedidos.show', $id))->assertOk()
                ->assertSee($response->json('data.numero_solicitud'));
            if ($tipo === 'distribucion') {
                $response->assertJsonPath('data.detalles.0.cantidad_kg', '1.061728')->assertJsonPath('data.detalles.0.unidad', 'bolsas')->assertJsonPath('data.destino.puntoventaid', $this->distribucion['puntoventaid']);
            }
        }
    }

    public function test_creacion_web_se_consulta_desde_api_y_no_reserva_anticipadamente(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $antes = $tipo === 'agricolas' ? $this->f['cosechas'][0]->fresh()->getRawOriginal('cantidad') : $this->partida->fresh()->getRawOriginal('cantidad_unidades');
            $this->actingAs($this->usuario($tipo))->post($tipo === 'agricolas' ? route('pedidos.store') : route('punto-venta.pedidos.store'), $this->entrada($tipo))->assertSessionHasNoErrors()->assertRedirect();
            $modelo = $tipo === 'agricolas' ? Pedido::orderByDesc('pedidoid')->first() : PedidoDistribucion::orderByDesc('pedidodistribucionid')->first();
            $this->getJson('/api/pedidos-'.$tipo.'/'.$modelo->getKey())->assertOk()->assertJsonPath('data.detalles.0.cantidad', $this->entrada($tipo)['detalles'][0]['cantidad']);
            $despues = $tipo === 'agricolas' ? $this->f['cosechas'][0]->fresh()->getRawOriginal('cantidad') : $this->partida->fresh()->getRawOriginal('cantidad_unidades');
            $this->assertSame($antes, $despues);
        }
    }

    public function test_cantidades_invalidas_y_precision_excesiva_de_ambos_tipos(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            foreach (['0', '-1', '1.1234567', '1e2', '9999999999999'] as $cantidad) {
                $datos = $this->entrada($tipo);
                $datos['detalles'][0]['cantidad'] = $cantidad;
                $this->crear($tipo, $datos)->assertUnprocessable()->assertJsonValidationErrors('detalles.0.cantidad');
            }
        }
    }

    public function test_existencias_exactas_insuficientes_y_lineas_acumuladas(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $datos = $this->entrada($tipo);
            $datos['detalles'][0]['cantidad'] = $tipo === 'agricolas' ? '100.123456' : '100';
            $this->crear($tipo, $datos)->assertCreated();
            $datos['detalles'][] = $datos['detalles'][0];
            $this->crear($tipo, $datos)->assertUnprocessable()->assertJsonValidationErrors('detalles.1.cantidad');
            $datos['detalles'] = [$datos['detalles'][0]];
            $datos['detalles'][0]['cantidad'] = '101';
            $this->crear($tipo, $datos)->assertUnprocessable()->assertJsonValidationErrors('detalles.0.cantidad');
        }
    }

    public function test_presentaciones_y_destinos_invalidos_o_ajenos(): void
    {
        $datos = $this->agricola;
        $datos['detalles'][0]['catalogotamanoconteoid'] = 99999;
        $this->crear('agricolas', $datos)->assertUnprocessable()->assertJsonValidationErrors('detalles.0.catalogotamanoconteoid');
        $datos = $this->agricola;
        $datos['latitud'] = 91;
        $this->crear('agricolas', $datos)->assertUnprocessable()->assertJsonValidationErrors('latitud');
        $datos = $this->agricola;
        $datos['origen_almacenid'] = $this->f['almacen']->getKey();
        $this->crear('agricolas', $datos)->assertUnprocessable()->assertJsonValidationErrors('origen_almacenid');
        $otro = InsumoPresentacion::create(['insumoid' => $this->f['lote']->materiasPrimas()->first()->insumoid, 'nombre' => 'Ajena', 'peso_neto_kg' => 1, 'activo' => true]);
        $datos = $this->distribucion;
        $datos['detalles'][0]['insumo_presentacionid'] = $otro->getKey();
        $this->crear('distribucion', $datos)->assertUnprocessable()->assertJsonValidationErrors('detalles.0.insumo_presentacionid');
        $datos = $this->distribucion;
        $datos['puntoventaid'] = $this->puntoVenta($this->actor('minorista'), 'Ajeno')->getKey();
        $this->crear('distribucion', $datos)->assertUnprocessable();
    }

    public function test_campos_protegidos_no_modifican_autoria_o_estado_inicial(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            foreach (['estado' => 'recibido', 'creado_por_usuarioid' => 999, 'aceptado_por_usuarioid' => 999] as $campo => $valor) {
                $this->crear($tipo, $this->entrada($tipo) + [$campo => $valor])->assertUnprocessable()->assertJsonValidationErrors($campo);
            }
            $datos = $this->entrada($tipo);
            $datos['detalles'][0]['cantidad_kg'] = '0.01';
            $this->crear($tipo, $datos)->assertUnprocessable()->assertJsonValidationErrors('detalles.0.cantidad_kg');
        }
    }

    public function test_reintento_explicito_y_conflicto_no_crean_otro_pedido(): void
    {
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $datos = $this->entrada($tipo) + ['solicitud_id' => (string) Str::uuid()];
            $id = $this->crear($tipo, $datos)->assertCreated()->json('data.id');
            $this->crear($tipo, $datos)->assertCreated()->assertJsonPath('data.id', $id);
            $datos['detalles'][0]['cantidad'] = '1';
            $this->crear($tipo, $datos)->assertConflict();
            $otro = $this->crear($tipo)->assertCreated()->json('data.id');
            $this->assertNotSame($id, $otro);
        }
    }

    public function test_agricola_acepta_una_vez_descuenta_y_revalida_saldo_actual(): void
    {
        $a = $this->crear('agricolas')->assertCreated()->json('data.id');
        $this->postJson('/api/pedidos-agricolas/'.$a.'/transiciones', ['accion' => 'aceptar'])->assertOk()->assertJsonPath('data.estado', 'confirmado');
        $this->assertEquals('95.000000', $this->f['cosechas'][0]->fresh()->getRawOriginal('cantidad'));
        $this->postJson('/api/pedidos-agricolas/'.$a.'/transiciones', ['accion' => 'aceptar'])->assertOk();
        $this->assertEquals('95.000000', $this->f['cosechas'][0]->fresh()->getRawOriginal('cantidad'));
        $this->postJson('/api/pedidos-agricolas/'.$a.'/transiciones', ['accion' => 'rechazar'])->assertConflict();
        $b = $this->crear('agricolas')->assertCreated()->json('data.id');
        $this->f['cosechas'][0]->update(['cantidad' => 1]);
        $this->postJson('/api/pedidos-agricolas/'.$b.'/transiciones', ['accion' => 'aceptar'])->assertUnprocessable();
        $this->assertSame('sin asignacion', Pedido::findOrFail($b)->estado);
    }

    public function test_distribucion_reserva_reintento_reapertura_y_libera_sin_movimientos(): void
    {
        $id = $this->crear('distribucion')->assertCreated()->json('data.id');
        $movimientos = AlmacenMovimiento::count();
        $this->actingAs($this->mayorista)->postJson('/api/pedidos-distribucion/'.$id.'/transiciones', ['accion' => 'aceptar'])->assertOk()->assertJsonPath('data.estado', 'confirmado');
        $this->postJson('/api/pedidos-distribucion/'.$id.'/transiciones', ['accion' => 'aceptar'])->assertOk();
        $this->assertEquals('100.000000', $this->partida->fresh()->cantidad_unidades);
        $datos = $this->distribucion;
        $datos['detalles'][0]['cantidad'] = '99';
        $this->crear('distribucion', $datos)->assertUnprocessable();
        $this->actingAs($this->mayorista)->postJson('/api/pedidos-distribucion/'.$id.'/transiciones', ['accion' => 'reabrir-revision'])->assertOk()->assertJsonPath('data.estado', 'pendiente');
        $this->crear('distribucion', $datos)->assertCreated();
        $this->assertSame($movimientos, AlmacenMovimiento::count());
    }

    public function test_stock_vencido_y_partida_de_otro_producto_no_se_consumen(): void
    {
        $this->partida->update(['fecha_vencimiento' => now()->subDay()->toDateString()]);
        $this->crear('distribucion')->assertUnprocessable();
        $this->partida->update(['fecha_vencimiento' => now()->toDateString()]);
        $this->crear('distribucion')->assertCreated();
        $datos = $this->distribucion;
        $datos['detalles'][0]['inventario_presentacion_loteid'] = 99999;
        $this->crear('distribucion', $datos)->assertUnprocessable();
    }

    public function test_sin_autenticacion_sin_permiso_y_pedidos_ajenos_no_se_exponen(): void
    {
        $this->get('/api/pedidos-agricolas')->assertUnauthorized();
        $this->get('/api/pedidos-distribucion')->assertUnauthorized();
        foreach (['agricolas', 'distribucion'] as $tipo) {
            $id = $this->crear($tipo)->assertCreated()->json('data.id');
            $ajeno = $this->actor($tipo === 'agricolas' ? 'jefe_agricultor' : 'minorista');
            $this->actingAs($ajeno)->getJson('/api/pedidos-'.$tipo.'/'.$id)->assertNotFound();
            $this->getJson('/api/pedidos-'.$tipo)->assertOk()->assertJsonCount(0, 'data');
            $this->actingAs($this->actor('planta'))->postJson('/api/pedidos-'.$tipo, [])->assertForbidden();
        }
    }

    public function test_transiciones_no_permiten_modificar_lineas_y_usuario_equivocado_no_acepta(): void
    {
        $id = $this->crear('distribucion')->assertCreated()->json('data.id');
        $this->postJson('/api/pedidos-distribucion/'.$id.'/transiciones', ['accion' => 'aceptar'])->assertForbidden();
        $this->actingAs($this->mayorista)->postJson('/api/pedidos-distribucion/'.$id.'/transiciones', ['accion' => 'aceptar', 'detalles' => []])->assertUnprocessable();
        $this->postJson('/api/pedidos-distribucion/'.$id.'/transiciones', ['accion' => 'recibido'])->assertUnprocessable();
        $this->assertSame('pendiente', PedidoDistribucion::findOrFail($id)->estado);
    }

    public function test_fallo_al_guardar_lineas_revierte_cabecera_y_dependencias(): void
    {
        $antes = PedidoDistribucion::count();
        $almacenes = Almacen::count();
        DetallePedidoDistribucion::creating(fn () => throw new \RuntimeException('Fallo línea API51'));
        $this->withoutExceptionHandling();
        try {
            $this->crear('distribucion');
            $this->fail('Debía fallar');
        } catch (\RuntimeException $e) {
            $this->assertSame('Fallo línea API51', $e->getMessage());
        } finally {
            DetallePedidoDistribucion::flushEventListeners();
        }
        $this->assertSame($antes, PedidoDistribucion::count());
        $this->assertSame($almacenes, Almacen::count());
    }

    public function test_api_legada_conserva_lista_plana_y_claves_pero_protege_estado(): void
    {
        $id = $this->crear('agricolas')->assertCreated()->json('data.id');
        $this->getJson('/api/pedidos/'.$id)->assertOk()->assertJsonPath('pedidoid', $id)->assertJsonMissingPath('data');
        $this->getJson('/api/pedidos?per_page=1')->assertOk()->assertJsonCount(1)->assertHeader('X-Current-Page', '1');
        $this->patchJson('/api/pedidos/'.$id, ['estado' => 'confirmado'])->assertUnprocessable();
    }

    public function test_varias_presentaciones_conservan_conversion_y_todas_las_lineas_son_visibles_en_web(): void
    {
        $otra = InsumoPresentacion::create(['insumoid' => $this->producto->getKey(), 'nombre' => 'Lata 1 kg', 'tipo_envase' => 'lata', 'peso_neto_kg' => 1, 'activo' => true]);
        $partida = app(InventarioPresentacionService::class)->ingresar($this->producto->almacenid, $this->producto->getKey(), $otra->getKey(), null, 'LATA51', 10, 10);
        $datos = $this->distribucion;
        $datos['detalles'][] = ['insumoid' => $this->producto->getKey(), 'insumo_presentacionid' => $otra->getKey(), 'inventario_presentacion_loteid' => $partida->getKey(), 'cantidad' => '3.123456'];
        $r = $this->crear('distribucion', $datos)->assertCreated()->assertJsonCount(2, 'data.detalles')
            ->assertJsonPath('data.detalles.0.cantidad_kg', '1.061728')->assertJsonPath('data.detalles.1.cantidad_kg', '3.123456');
        $this->get(route('punto-venta.pedidos.show', $r->json('data.id')))->assertOk()->assertSee('Lata 1 kg')->assertSee('3.123456');
    }

    public function test_edicion_web_y_despacho_conservan_equivalencia_sin_recalcular_catalogo_ni_duplicar_salida(): void
    {
        $id = $this->crear('distribucion')->assertCreated()->json('data.id');
        $this->put(route('punto-venta.pedidos.update', $id), ['insumoid' => $this->producto->getKey(), 'cantidad' => '3.123456'])->assertRedirect()->assertSessionMissing('error');
        $this->getJson('/api/pedidos-distribucion/'.$id)->assertOk()->assertJsonPath('data.detalles.0.cantidad_kg', '1.561728');
        $this->presentacion->update(['peso_neto_kg' => 2]);
        $this->actingAs($this->mayorista)->postJson('/api/pedidos-distribucion/'.$id.'/transiciones', ['accion' => 'aceptar'])->assertOk();
        $ruta = \App\Models\RutaDistribucion::create(['codigo' => 'SALIDA-51', 'transportista_usuarioid' => $this->conductor()->getKey(), 'fecha_programada' => now(), 'estado' => 'pendiente', 'tipo_ruta' => 'distribucion']);
        PedidoDistribucion::findOrFail($id)->update(['rutadistribucionid' => $ruta->getKey()]);
        $service = app(\App\Services\PedidoDistribucionSalidaMayoristaService::class);
        $service->descontarPedidosDeRuta($ruta, $this->mayorista);
        $service->descontarPedidosDeRuta($ruta->fresh(), $this->mayorista);
        $movimientos = AlmacenMovimiento::where('referencia', PedidoDistribucion::findOrFail($id)->numero_solicitud)->get();
        $this->assertCount(1, $movimientos);
        $this->assertSame('1.561728', $movimientos[0]->cantidad);
        $this->assertSame('96.876544', $this->partida->fresh()->cantidad_unidades);
    }

    public function test_vencimiento_entre_solicitud_y_aceptacion_no_confirma_ni_reserva(): void
    {
        $id = $this->crear('distribucion')->assertCreated()->json('data.id');
        $this->partida->update(['fecha_vencimiento' => now()->subDay()->toDateString()]);
        $this->actingAs($this->mayorista)->postJson('/api/pedidos-distribucion/'.$id.'/transiciones', ['accion' => 'aceptar'])->assertUnprocessable();
        $this->assertSame('pendiente', PedidoDistribucion::findOrFail($id)->estado);
        $this->assertSame('100.000000', $this->partida->fresh()->cantidad_unidades);
    }

    public function test_fallo_en_linea_agricola_y_transicion_revierte_todos_los_cambios(): void
    {
        $antes = Pedido::count();
        DetallePedido::creating(fn () => throw new \RuntimeException('Fallo agrícola API51'));
        $this->withoutExceptionHandling();
        try {
            $this->crear('agricolas');
            $this->fail('Debía fallar');
        } catch (\RuntimeException $e) {
            $this->assertSame('Fallo agrícola API51', $e->getMessage());
        } finally {
            DetallePedido::flushEventListeners();
        }
        $this->assertSame($antes, Pedido::count());
        $id = $this->crear('agricolas')->assertCreated()->json('data.id');
        $saldo = $this->f['cosechas'][0]->fresh()->getRawOriginal('cantidad');
        Pedido::updating(function ($p) {
            if ($p->estado === 'confirmado') {
                throw new \RuntimeException('Fallo después del descuento API51');
            }
        });
        try {
            $this->postJson('/api/pedidos-agricolas/'.$id.'/transiciones', ['accion' => 'aceptar']);
            $this->fail('Debía revertirse la transición');
        } catch (\RuntimeException $e) {
            $this->assertSame('Fallo después del descuento API51', $e->getMessage());
        } finally {
            Pedido::flushEventListeners();
        }
        $this->assertSame('sin asignacion', Pedido::findOrFail($id)->estado);
        $this->assertSame($saldo, $this->f['cosechas'][0]->fresh()->getRawOriginal('cantidad'));
    }

    public function test_material_siembra_excluye_partidas_vencidas_y_bloqueadas_y_registra_salida_unica(): void
    {
        $tipo = \App\Models\TipoInsumo::firstOrCreate(['nombre' => 'Material de Siembra']);
        $insumo = \App\Models\Insumo::create(['nombre' => 'Semilla de tomate', 'almacenid' => $this->agricola['origen_almacenid'],
            'tipoinsumoid' => $tipo->getKey(), 'unidadmedidaid' => $this->f['kg']->getKey(), 'stock' => 10]);
        $partida = \App\Models\MateriaPrimaLote::create(['insumoid' => $insumo->getKey(), 'almacenid' => $insumo->almacenid,
            'fecha_recepcion' => now()->toDateString(), 'cantidad' => 10, 'cantidad_disponible' => 10, 'conformidad_recepcion' => false, 'fecha_vencimiento' => now()->addDay()->toDateString()]);
        $datos = $this->agricola;
        $datos['detalles'][0]['producto_ref'] = 'insumo:'.$insumo->getKey();
        $datos['detalles'][0]['materiaprimaloteid'] = $partida->getKey();
        $datos['detalles'][0]['cantidad'] = '1.123456';
        $this->crear('agricolas', $datos)->assertUnprocessable()->assertJsonValidationErrors('detalles.0.materiaprimaloteid');
        $partida->update(['conformidad_recepcion' => true, 'fecha_vencimiento' => now()->subDay()->toDateString()]);
        $this->crear('agricolas', $datos)->assertUnprocessable();
        $partida->update(['fecha_vencimiento' => now()->toDateString()]);
        $id = $this->crear('agricolas', $datos)->assertCreated()->json('data.id');
        $this->postJson('/api/pedidos-agricolas/'.$id.'/transiciones', ['accion' => 'aceptar'])->assertOk();
        $this->postJson('/api/pedidos-agricolas/'.$id.'/transiciones', ['accion' => 'aceptar'])->assertOk();
        $this->assertSame('8.876544', (string) $insumo->fresh()->getRawOriginal('stock'));
        $this->assertCount(1, AlmacenMovimiento::where('referencia', Pedido::findOrFail($id)->numero_solicitud)->get());
    }
}
