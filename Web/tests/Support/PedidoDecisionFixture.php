<?php

namespace Tests\Support;

use App\Models\Almacen;
use App\Models\DetallePedido;
use App\Models\DetallePedidoDistribucion;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Insumo;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\PuntoVenta;
use App\Models\TipoInsumo;
use Illuminate\Support\Str;

class PedidoDecisionFixture
{
    public static function crear(): array
    {
        $f = CertificadosFixture::crear();
        $f['admin'] = CertificadosFixture::usuario('admin', 'admin53');
        $almacen = Almacen::create(['nombre' => 'Origen agrícola EDT53', 'ubicacion' => 'Prueba', 'ambito' => 'agricola', 'activo' => true,
            'responsable_usuarioid' => $f['agricola']->getKey(), 'unidadmedidaid' => $f['kg']->getKey(), 'capacidad' => 1000]);
        $f['cosechas'][0]->update(['almacenid' => $almacen->getKey(), 'cantidad' => '10.000000', 'fechasalida' => null]);
        $f['mayorista'] = CertificadosFixture::usuario('mayorista', 'may53');
        $f['minorista'] = CertificadosFixture::usuario('minorista', 'min53');
        $f['origen'] = Almacen::create(['nombre' => 'Origen mayorista EDT53', 'ubicacion' => 'Prueba', 'ambito' => 'mayorista', 'activo' => true,
            'responsable_usuarioid' => $f['mayorista']->getKey(), 'unidadmedidaid' => $f['kg']->getKey(), 'capacidad' => 1000]);
        $f['producto'] = Insumo::create(['nombre' => 'Producto EDT53', 'almacenid' => $f['origen']->getKey(), 'stock' => 10,
            'unidadmedidaid' => $f['kg']->getKey(), 'tipoinsumoid' => TipoInsumo::firstOrCreate(['nombre' => 'Producto terminado'])->getKey()]);
        $f['presentacion'] = InsumoPresentacion::create(['insumoid' => $f['producto']->getKey(), 'nombre' => 'Bolsa 1 kg', 'tipo_envase' => 'bolsa', 'peso_neto_kg' => 1, 'activo' => true]);
        $f['partida'] = InventarioPresentacionLote::create(['insumoid' => $f['producto']->getKey(), 'almacenid' => $f['origen']->getKey(),
            'insumo_presentacionid' => $f['presentacion']->getKey(), 'cantidad_unidades' => 10, 'cantidad_kg' => 10]);
        $f['pdv'] = PuntoVenta::create(['usuarioid' => $f['minorista']->getKey(), 'nombre' => 'Destino EDT53', 'direccion' => 'Prueba', 'activo' => true]);

        return $f;
    }

    public static function pedido(array $f, string $tipo, string $cantidad = '6.000000'): Pedido|PedidoDistribucion
    {
        if ($tipo === 'agricolas') {
            $pedido = Pedido::create(['numero_solicitud' => 'AGR-'.Str::uuid(), 'estado' => 'sin asignacion', 'creado_por_usuarioid' => $f['agricola']->getKey(),
                'fechapedido' => now(), 'latitud' => -17, 'longitud' => -63]);
            DetallePedido::create(['pedidoid' => $pedido->getKey(), 'producto_ref' => 'cosecha:'.$f['cosechas'][0]->getKey(), 'produccionalmacenamientoid' => $f['cosechas'][0]->getKey(), 'cultivo_personalizado' => 'Tomate', 'cantidad' => $cantidad]);
            EnvioAsignacionMultiple::create(['pedidoid' => $pedido->getKey(), 'externo_envio_id' => $pedido->numero_solicitud, 'estado' => 'pendiente', 'asignadopor_usuarioid' => $f['agricola']->getKey()]);
        } else {
            $pedido = PedidoDistribucion::create(['numero_solicitud' => 'DIS-'.Str::uuid(), 'puntoventaid' => $f['pdv']->getKey(), 'almacen_mayorista_origenid' => $f['origen']->getKey(), 'estado' => 'pendiente', 'tipo_solicitud' => 'stock', 'fechapedido' => now()]);
            DetallePedidoDistribucion::create(['pedidodistribucionid' => $pedido->getKey(), 'insumoid' => $f['producto']->getKey(), 'insumo_presentacionid' => $f['presentacion']->getKey(),
                'inventario_presentacion_loteid' => $f['partida']->getKey(), 'almacen_mayorista_origenid' => $f['origen']->getKey(), 'producto_nombre' => 'Producto EDT53', 'cantidad' => $cantidad,
                'datos_solicitud' => ['unidad' => 'bolsas', 'cantidad_kg' => $cantidad]]);
        }

        return $pedido;
    }
}
