<?php

namespace App\Http\Resources\Api;

use App\Models\Pedido;
use App\Support\InventarioDecimal;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PedidoMovilResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $agricola = $this->resource instanceof Pedido;

        return ['tipo' => $agricola ? 'agricola' : 'distribucion',
            'id' => (int) $this->getKey(), 'numero_solicitud' => $this->numero_solicitud, 'estado' => $this->estado,
            'fecha' => $this->fechapedido?->toIso8601String(),
            'fecha_entrega_deseada' => ($agricola ? $this->fechaEntregaDeseada : $this->fecha_entrega_deseada)?->toDateString(),
            'creado_por_usuarioid' => $this->creado_por_usuarioid ? (int) $this->creado_por_usuarioid : null,
            'aceptado_por_usuarioid' => $this->aceptado_por_usuarioid ? (int) $this->aceptado_por_usuarioid : null,
            'fecha_aceptacion' => ($agricola ? $this->fecha_aceptacion_agricola : $this->fecha_aceptacion)?->toIso8601String(),
            'envio_iniciado_mayorista' => $agricola ? null : (bool) $this->envio_iniciado_mayorista,
            'fecha_confirmacion_minorista' => $agricola ? null : $this->fecha_confirmacion_minorista?->toIso8601String(),
            'fecha_envio' => $agricola ? null : $this->fecha_envio?->toIso8601String(),
            'fecha_recepcion' => $agricola ? null : $this->fecha_recepcion?->toIso8601String(),
            'envio' => $agricola && $this->envioAsignacion ? [
                'id' => (int) $this->envioAsignacion->getKey(), 'estado' => $this->envioAsignacion->estado,
                'transportista_usuarioid' => $this->envioAsignacion->transportista_usuarioid ? (int) $this->envioAsignacion->transportista_usuarioid : null,
                'fecha_recepcion_planta' => $this->envioAsignacion->fecha_recepcion_planta?->toIso8601String(),
            ] : null,
            'destino' => $agricola ? ['latitud' => $this->latitud, 'longitud' => $this->longitud, 'direccion' => $this->direccion_texto]
                : ['puntoventaid' => (int) $this->puntoventaid, 'nombre' => $this->puntoVenta?->nombre],
            'observaciones' => $this->observaciones,
            'detalles' => $this->detalles->map(fn ($d) => [
                'id' => (int) $d->getKey(), 'producto_ref' => $agricola ? $d->producto_ref : null,
                'insumoid' => $d->insumoid ? (int) $d->insumoid : null,
                'materiaprimaloteid' => $agricola && $d->materiaprimaloteid ? (int) $d->materiaprimaloteid : null,
                'producto' => $agricola ? $d->cultivo_personalizado : $d->producto_nombre,
                'produccionalmacenamientoid' => $agricola && $d->produccionalmacenamientoid ? (int) $d->produccionalmacenamientoid : null,
                'presentacionid' => $agricola ? null : ($d->insumo_presentacionid ? (int) $d->insumo_presentacionid : null),
                'catalogotamanoconteoid' => $agricola ? ($d->datos_solicitud['catalogotamanoconteoid'] ?? null) : null,
                'presentacion' => $d->datos_solicitud['presentacion'] ?? null,
                'cantidad' => InventarioDecimal::texto(InventarioDecimal::unidades($d->getRawOriginal('cantidad'))),
                'unidad' => $d->datos_solicitud['unidad'] ?? ($agricola ? 'kg' : null),
                'cantidad_kg' => $agricola ? InventarioDecimal::texto(InventarioDecimal::unidades($d->getRawOriginal('cantidad'))) : ($d->datos_solicitud['cantidad_kg'] ?? null),
                'almacen_origenid' => $d->datos_solicitud['almacen_id'] ?? ($agricola ? null : $d->almacen_mayorista_origenid),
                'inventario_presentacion_loteid' => $agricola ? null : $d->inventario_presentacion_loteid,
            ])->values()->all()];
    }
}
