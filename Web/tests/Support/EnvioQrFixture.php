<?php

namespace Tests\Support;

use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\ChecklistIncidenteEnvio;
use App\Models\DetallePedido;
use App\Models\DetallePedidoDistribucion;
use App\Models\DetalleTrasladoPlantaMayorista;
use App\Models\EnvioAsignacionMultiple;
use App\Models\FirmaTransportistaEnvio;
use App\Models\Insumo;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\PuntoVenta;
use App\Models\RutaDistribucion;
use App\Models\TipoInsumo;
use App\Models\TipoMovimientoAlmacen;
use App\Models\UnidadMedida;
use App\Services\EnvioRecepcionQrService;

class EnvioQrFixture
{
    public static function firma(bool $vacia = false): string
    {
        $img = imagecreatetruecolor(160, 80);
        imagefill($img, 0, 0, imagecolorallocate($img, 255, 255, 255));
        if (! $vacia) {
            imageline($img, 10, 65, 150, 10, imagecolorallocate($img, 20, 30, 40));
        }
        ob_start();
        imagepng($img);
        $bytes = ob_get_clean();
        imagedestroy($img);

        return 'data:image/png;base64,'.base64_encode($bytes);
    }

    public static function crear(string $tipo = 'agricola', bool $mixta = false): array
    {
        $sufijo = bin2hex(random_bytes(4));
        $receptor = CertificadosFixture::usuario($tipo === 'agricola' ? 'jefe_planta' : ($tipo === 'traslado' ? 'mayorista' : 'minorista'), 'r'.$sufijo);
        $remitente = CertificadosFixture::usuario($tipo === 'agricola' ? 'jefe_agricultor' : ($tipo === 'traslado' ? 'jefe_planta' : 'mayorista'), 'e'.$sufijo);
        $conductor = CertificadosFixture::usuario('transportista', 't'.$sufijo);
        $kg = UnidadMedida::firstOrCreate(['abreviatura' => 'kg'], ['nombre' => 'Kilogramo', 'categoria' => 'peso']);
        $kg->update(['categoria' => 'peso']);
        $almacen = Almacen::create(['nombre' => 'Destino '.$sufijo, 'ambito' => $tipo === 'agricola' ? 'planta' : 'mayorista', 'ubicacion' => 'Prueba',
            'capacidad' => 10000, 'unidadmedidaid' => $kg->getKey(), 'activo' => true, 'responsable_usuarioid' => $tipo === 'distribucion' ? $remitente->getKey() : $receptor->getKey()]);
        $salida = TipoMovimientoAlmacen::firstOrCreate(['nombre' => 'Salida QR', 'naturaleza' => 'salida'], ['activo' => true]);
        TipoMovimientoAlmacen::firstOrCreate(['nombre' => 'Ingreso QR', 'naturaleza' => 'ingreso'], ['activo' => true]);
        if ($tipo === 'agricola') {
            $pedido = Pedido::create(['numero_solicitud' => 'AGR-'.$sufijo, 'estado' => 'confirmado', 'creado_por_usuarioid' => $remitente->getKey(),
                'latitud' => -17.78, 'longitud' => -63.18, 'nombre_planta' => $almacen->nombre, 'direccion_texto' => $almacen->nombre.' · GPS', 'fechapedido' => now()]);
            $detalle = DetallePedido::create(['pedidoid' => $pedido->getKey(), 'cultivo_personalizado' => 'Tomate QR', 'cantidad' => '10.123456']);
            $envio = EnvioAsignacionMultiple::create(['pedidoid' => $pedido->getKey(), 'externo_envio_id' => 'ENV-'.$sufijo,
                'transportista_usuarioid' => $conductor->getKey(), 'estado' => 'en_transporte_planta', 'fecha_asignacion' => now(), 'llegada_confirmada_at' => now()]);
        } else {
            $envio = RutaDistribucion::create(['codigo' => 'RUTA-'.$sufijo, 'nombre' => 'Ruta QR', 'tipo_ruta' => $tipo === 'traslado' ? 'planta_mayorista' : 'mayorista_pdv',
                'almacen_mayorista_origenid' => $tipo === 'distribucion' ? $almacen->getKey() : null,
                'almacen_mayorista_destinoid' => $tipo === 'traslado' ? $almacen->getKey() : null,
                'transportista_usuarioid' => $conductor->getKey(), 'estado' => 'en_ruta', 'llegada_confirmada_at' => now()]);
            $origen = $tipo === 'traslado' ? Almacen::create(['nombre' => 'Origen '.$sufijo, 'ambito' => 'planta', 'ubicacion' => 'Prueba', 'capacidad' => 10000,
                'unidadmedidaid' => $kg->getKey(), 'activo' => true, 'responsable_usuarioid' => $remitente->getKey()]) : $almacen;
            $insumo = Insumo::create(['nombre' => 'Producto QR', 'almacenid' => $origen->getKey(), 'stock' => 100, 'unidadmedidaid' => $kg->getKey(),
                'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Producto terminado'])->getKey()]);
            $presentacion = InsumoPresentacion::create(['insumoid' => $insumo->getKey(), 'nombre' => 'Bolsa 2 kg', 'peso_neto_kg' => 2, 'tipo_envase' => 'bolsa', 'activo' => true]);
            $partida = InventarioPresentacionLote::create(['insumoid' => $insumo->getKey(), 'almacenid' => $origen->getKey(), 'insumo_presentacionid' => $presentacion->getKey(),
                'cantidad_unidades' => 50, 'cantidad_kg' => 100, 'referencia_lote' => 'LOTE-'.$sufijo]);
            if ($tipo === 'traslado') {
                $envio->update(['almacen_planta_origenid' => $origen->getKey()]);
                $detalle = DetalleTrasladoPlantaMayorista::create(['rutadistribucionid' => $envio->getKey(), 'insumoid' => $insumo->getKey(),
                    'producto_nombre' => $insumo->nombre, 'cantidad' => 10, 'cantidad_unidades' => 5, 'insumo_presentacionid' => $presentacion->getKey(),
                    'inventario_presentacion_loteid' => $partida->getKey(), 'presentacion_nombre' => $presentacion->nombre]);
            } else {
                $receptores = [$receptor];
                if ($mixta) {
                    $otroReceptor = CertificadosFixture::usuario('minorista', 'otro'.$sufijo);
                    $receptores[] = $otroReceptor;
                }
                foreach ($receptores as $i => $dueno) {
                    $pdv = PuntoVenta::create(['usuarioid' => $dueno->getKey(), 'nombre' => 'Tienda '.$i.$sufijo, 'direccion' => 'Dirección '.$i, 'activo' => true]);
                    $pedido = PedidoDistribucion::create(['numero_solicitud' => 'PDV-'.$i.$sufijo, 'puntoventaid' => $pdv->getKey(), 'estado' => 'en_transito',
                        'almacen_mayorista_origenid' => $almacen->getKey(), 'rutadistribucionid' => $envio->getKey(), 'fechapedido' => now()]);
                    $detalle = DetallePedidoDistribucion::create(['pedidodistribucionid' => $pedido->getKey(), 'insumoid' => $insumo->getKey(), 'producto_nombre' => $insumo->nombre,
                        'almacen_mayorista_origenid' => $almacen->getKey(), 'insumo_presentacionid' => $presentacion->getKey(), 'inventario_presentacion_loteid' => $partida->getKey(),
                        'cantidad' => '5.123456', 'datos_solicitud' => ['unidad' => 'bolsas', 'presentacion' => 'Bolsa 2 kg', 'peso_neto_kg' => '2', 'cantidad_kg' => '10.246912']]);
                    AlmacenMovimiento::create(['almacenid' => $almacen->getKey(), 'insumoid' => $insumo->getKey(), 'usuarioid' => $remitente->getKey(),
                        'tipo_movimiento_almacenid' => $salida->getKey(), 'fecha' => now()->toDateString(), 'cantidad' => '10.246912',
                        'referencia' => $pedido->numero_solicitud, 'detallepedidodistribucionid' => $detalle->getKey(),
                        'observaciones' => 'Distribución PDV — salida mayorista · [inventario_presentacion_descontado]']);
                }
            }
        }
        $fk = $tipo === 'agricola' ? 'envioasignacionmultipleid' : 'rutadistribucionid';
        ChecklistIncidenteEnvio::create([$fk => $envio->getKey(), 'fecha' => now()]);
        FirmaTransportistaEnvio::create([$fk => $envio->getKey(), 'imagenfirma' => self::firma(), 'firmante_usuarioid' => $conductor->getKey(), 'nombrefirmante' => $conductor->nombre, 'fechafirma' => now()]);
        $qrs = app(EnvioRecepcionQrService::class)->emitir($envio);
        $qr = collect($qrs)->first(fn ($q) => ! $q->destinatario_usuarioid || (int) $q->destinatario_usuarioid === (int) $receptor->getKey());

        return get_defined_vars();
    }
}
