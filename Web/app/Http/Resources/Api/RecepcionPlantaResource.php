<?php

namespace App\Http\Resources\Api;

use App\Support\CosechaDecimal;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class RecepcionPlantaResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $envio = $this->envioAsignacion;

        return ['pedidoid' => (int) $this->getKey(), 'numero_solicitud' => $this->numero_solicitud,
            'envioasignacionmultipleid' => (int) $envio->getKey(), 'externo_envio_id' => $envio->externo_envio_id,
            'estado' => $envio->estado, 'almacenid' => $envio->almacenid,
            'fecha_recepcion_planta' => $envio->fecha_recepcion_planta?->toIso8601String(),
            'recepcion_usuarioid' => $envio->recepcion_usuarioid,
            'lineas' => $this->detalles->map(fn ($d) => ['detallepedidoid' => (int) $d->getKey(),
                'producto' => $d->cultivo_personalizado ?: $d->insumo?->nombre,
                'cantidad_enviada' => CosechaDecimal::mostrar($d->getRawOriginal('cantidad')), 'unidad' => 'kg',
                'produccionalmacenamientoid' => $d->produccionalmacenamientoid,
                'produccionid' => $d->cosechaAlmacen?->produccionid, 'loteid' => $d->cosechaAlmacen?->produccion?->loteid]),
            'recepcion' => $envio->recepcion_planta_datos['lineas'] ?? null];
    }
}
