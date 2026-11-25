<?php

namespace Tests\Feature;

use App\Models\AlmacenMovimiento;
use App\Models\DestinoProduccion;
use App\Models\DetallePedido;
use App\Models\Insumo;
use App\Models\LoteProduccionMateriaPrima;
use App\Models\LoteProduccionPedido;
use App\Models\MateriaPrimaLote;
use App\Models\Pedido;
use App\Models\Produccion;
use App\Models\ProduccionAlmacenamiento;
use App\Services\EnvioRecepcionQrService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\Support\EnvioQrFixture;
use Tests\Support\TrazabilidadPublicaFixture;
use Tests\TestCase;

class RecorridoPublicoRutasTest extends TestCase
{
    use RefreshDatabase;

    private array $base;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        Storage::fake('local');
        $this->base = TrazabilidadPublicaFixture::crear();
    }

    private function origen(array $f, bool $industrial = false): array
    {
        $base = $this->base;
        $cosecha = Produccion::create(['loteid' => $base['lote']->getKey(), 'cantidad' => '20.123456',
            'cantidad_base' => '20.123456', 'unidadmedidaid' => $f['kg']->getKey(), 'fechacosecha' => '2026-11-20',
            'destinoproduccionid' => DestinoProduccion::firstOrCreate(['nombre' => 'Almacenamiento'])->getKey()]);
        $almacenamiento = ProduccionAlmacenamiento::create(['produccionid' => $cosecha->getKey(),
            'almacenid' => $f['almacen']->getKey(), 'cantidad' => '20.123456', 'unidadmedidaid' => $f['kg']->getKey(), 'fechaentrada' => now()]);
        $pedido = $f['tipo'] === 'agricola' ? $f['pedido'] : Pedido::create(['numero_solicitud' => 'PED-ORIGEN-61',
            'estado' => 'confirmado', 'latitud' => -17.123456, 'longitud' => -63.987654]);
        $detalle = $f['tipo'] === 'agricola' ? $f['detalle'] : DetallePedido::create(['pedidoid' => $pedido->getKey(),
            'cultivo_personalizado' => 'Zanahoria', 'cantidad' => '20.123456']);
        $detalle->update(['produccionalmacenamientoid' => $almacenamiento->getKey()]);
        if ($industrial) {
            $insumoEntrada = Insumo::create(['nombre' => 'Zanahoria materia prima', 'tipoinsumoid' => $f['insumo']->tipoinsumoid,
                'unidadmedidaid' => $f['kg']->getKey(), 'almacenid' => $f['insumo']->almacenid, 'stock' => '19']);
            $materia = MateriaPrimaLote::create(['detallepedidoid' => $detalle->getKey(), 'insumoid' => $insumoEntrada->getKey(),
                'almacenid' => $insumoEntrada->almacenid, 'cantidad' => '20.123456', 'cantidad_disponible' => '19',
                'fecha_recepcion' => now(), 'conformidad_recepcion' => true]);
            $proceso = LoteProduccionPedido::create(['pedidoid' => $pedido->getKey(), 'codigo_lote' => 'PLT-TRAZABILIDAD-61',
                'nombre' => 'Producto procesado', 'fecha_creacion' => now()]);
            LoteProduccionMateriaPrima::create(['loteproduccionpedidoid' => $proceso->getKey(),
                'materiaprimaloteid' => $materia->getKey(), 'insumoid' => $insumoEntrada->getKey(),
                'cantidad_planificada' => '1.123456', 'cantidad_usada' => '1.123456']);
            $f['partida']->update(['loteproduccionpedidoid' => $proceso->getKey()]);
        }

        return get_defined_vars();
    }

    private function etapa(array $json, string $tipo): array
    {
        return collect($json['etapas'])->firstWhere('tipo', $tipo)['eventos'];
    }

    public function test_recepcion_agricola_usa_linea_y_partida_exactas_y_no_expone_credenciales(): void
    {
        $f = EnvioQrFixture::crear('agricola');
        $o = $this->origen($f);
        $fecha = now()->setTime(12, 34, 56);
        $this->travelTo($fecha);
        $qr = app(EnvioRecepcionQrService::class)->confirmar($f['qr'], $f['receptor'],
            [['id' => $f['detalle']->getKey(), 'cantidad_recibida' => '10.123456']], EnvioQrFixture::firma());
        $respuesta = $this->getJson('/api/trazabilidad/'.$o['base']['lote']->codigo_trazabilidad)->assertOk();
        $evento = collect($this->etapa($respuesta->json(), 'planta'))->firstWhere('tipo', 'recepcion_registrada');
        $this->assertSame('10.123456', $evento['cantidad_recibida']);
        $this->assertSame($fecha->toIso8601String(), $evento['fecha']);
        $this->assertSame('recepcion', $evento['fecha_tipo']);
        $this->assertCount(1, $respuesta->json('rutas'));
        $this->assertSame($fecha->toIso8601String(), $respuesta->json('rutas.0.fecha_recepcion'));
        $respuesta->assertDontSee($qr->token)->assertDontSee($f['receptor']->email)
            ->assertDontSee($f['conductor']->email)->assertDontSee($qr->firma_path);

        $envio = $f['envio']->fresh();
        $snapshot = $envio->recepcion_planta_datos;
        $snapshot['lineas'][0]['materiaprimaloteid'] = 999999;
        $envio->update(['recepcion_planta_datos' => $snapshot]);
        $parcial = $this->getJson('/api/trazabilidad/'.$o['base']['lote']->codigo_trazabilidad)->assertOk();
        $eventos = collect($this->etapa($parcial->json(), 'planta'));
        $this->assertCount(0, $eventos->where('tipo', 'recepcion_registrada'));
        $this->assertNull($eventos->firstWhere('tipo', 'envio_registrado')['cantidad_recibida']);
        $this->travelBack();
    }

    public function test_traslado_real_conserva_cantidad_y_recepcion_sin_publicar_ruta_privada(): void
    {
        $f = EnvioQrFixture::crear('traslado');
        $o = $this->origen($f, true);
        $f['detalle']->update(['loteproduccionpedidoid' => $o['proceso']->getKey()]);
        $f['envio']->update(['fecha_salida' => now()->subHour(),
            'rutageojson' => ['coordinates' => [[-63.987654, -17.123456]]], 'nombre' => 'RUTA-PRIVADA-NO-PUBLICAR-61']);
        $qr = app(EnvioRecepcionQrService::class)->confirmar($f['qr'], $f['receptor'],
            [['id' => $f['detalle']->getKey(), 'cantidad_recibida' => '5.0000']], EnvioQrFixture::firma());
        $respuesta = $this->getJson('/api/trazabilidad/'.$o['base']['lote']->codigo_trazabilidad)->assertOk();
        $traslado = collect($this->etapa($respuesta->json(), 'mayorista'))->firstWhere('tipo', 'traslado_registrado');
        $this->assertSame('10.000000', $traslado['cantidad_kg']);
        $this->assertSame('5.000000', $traslado['cantidad_unidades']);
        $this->assertSame('5.000000', $traslado['cantidad_recibida']);
        $this->assertSame('bolsas', $traslado['unidad_recepcion']);
        $this->assertSame($qr->utilizado_en->toIso8601String(), $traslado['fecha_recepcion']);
        $ruta = collect($respuesta->json('rutas'))->firstWhere('tipo', 'traslado');
        $this->assertSame('planta', $ruta['origen']['tipo']);
        $this->assertSame('mayorista', $ruta['destino']['tipo']);
        $this->assertSame($qr->utilizado_en->toIso8601String(), $ruta['fecha_recepcion']);
        foreach ([$qr->token, $qr->firma_path, 'RUTA-PRIVADA-NO-PUBLICAR-61', '-63.987654', '-17.123456', $f['conductor']->email] as $privado) {
            $respuesta->assertDontSee($privado);
        }
    }

    public function test_pdv_mixto_enlaza_recepcion_real_y_no_mezcla_otro_output_o_destinatario(): void
    {
        $f = EnvioQrFixture::crear('distribucion', true);
        $o = $this->origen($f, true);
        $pedido = $f['envio']->pedidos()->whereHas('puntoVenta', fn ($q) => $q->where('usuarioid', $f['receptor']->getKey()))->firstOrFail();
        $detalle = $pedido->detalles()->firstOrFail();
        $otro = $f['envio']->pedidos()->whereKeyNot($pedido->getKey())->with('puntoVenta')->firstOrFail();
        $qr = app(EnvioRecepcionQrService::class)->confirmar($f['qr'], $f['receptor'],
            [['id' => $detalle->getKey(), 'cantidad_recibida' => '5.123456']], EnvioQrFixture::firma());
        $punto = $pedido->puntoVenta->fresh();
        $movimiento = AlmacenMovimiento::where('almacenid', $punto->almacenid)->where('referencia', $pedido->numero_solicitud)
            ->whereNotNull('inventario_presentacion_loteid')->firstOrFail();
        $producto = Insumo::findOrFail($movimiento->insumoid);
        $url = '/api/trazabilidad/'.strtoupper($producto->codigo_trazabilidad);
        // The actual source still owns its detail FK; the destination is proved by the
        // exact order number, concrete destination batch, historical quantities and used QR.
        $this->assertNull($movimiento->detallepedidodistribucionid);
        $this->assertTrue(AlmacenMovimiento::where('detallepedidodistribucionid', $detalle->getKey())->exists());
        $respuesta = $this->getJson($url)->assertOk();
        $eventos = collect($this->etapa($respuesta->json(), 'distribucion'));
        $this->assertCount(1, $eventos);
        $this->assertSame(strtoupper($pedido->numero_solicitud), $eventos->first()['codigo_pedido']);
        $this->assertSame('5.123456', $eventos->first()['cantidad']);
        $this->assertSame('10.246912', $eventos->first()['cantidad_kg']);
        $this->assertSame('bolsas', $eventos->first()['unidad']);
        $this->assertSame($pedido->fresh()->fecha_recepcion->toIso8601String(), $eventos->first()['fecha_recepcion']);
        $this->assertCount(1, $respuesta->json('rutas'));
        foreach ([$otro->numero_solicitud, strtoupper($otro->numero_solicitud), $otro->puntoVenta->nombre, $otro->puntoVenta->direccion,
            $f['otroReceptor']->email, $qr->token, $qr->firma_path] as $privado) {
            $respuesta->assertDontSee($privado);
        }

        $destino = \App\Models\InventarioPresentacionLote::findOrFail($movimiento->inventario_presentacion_loteid);
        $referencia = $destino->referencia_lote;
        $destino->update(['referencia_lote' => null]);
        $sinReferencia = $this->getJson($url)->assertOk();
        $this->assertSame([], $this->etapa($sinReferencia->json(), 'distribucion'));
        $this->assertSame([], $sinReferencia->json('rutas'));
        $destino->update(['referencia_lote' => $referencia]);

        // Another product/batch from the same process and warehouse, sharing the same
        // historical batch reference, makes the destination origin ambiguous.
        $otroProducto = $f['insumo']->replicate();
        $otroProducto->nombre = 'OTRO-OUTPUT-NO-ATRIBUIR-61';
        $otroProducto->save();
        $otraPresentacion = $f['presentacion']->replicate();
        $otraPresentacion->insumoid = $otroProducto->getKey();
        $otraPresentacion->save();
        $otraPartida = $f['partida']->replicate();
        $otraPartida->fill(['insumoid' => $otroProducto->getKey(), 'insumo_presentacionid' => $otraPresentacion->getKey()])->save();
        $parcial = $this->getJson($url)->assertOk();
        $this->assertSame([], $this->etapa($parcial->json(), 'distribucion'));
        $this->assertSame([], $parcial->json('rutas'));
        $parcial->assertDontSee('OTRO-OUTPUT-NO-ATRIBUIR-61');
    }
}
