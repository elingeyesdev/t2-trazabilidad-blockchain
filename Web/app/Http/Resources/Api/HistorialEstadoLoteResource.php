<?php

namespace App\Http\Resources\Api;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class HistorialEstadoLoteResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'historial_estado_id' => (int) $this->historial_estado_id,
            'loteid' => (int) $this->loteid,
            'estadolotetipoid' => (int) $this->estadolotetipoid,
            'fecha_cambio' => $this->fecha_cambio,
            'observaciones' => $this->observaciones,
            'imagenurl' => $this->imagenurl,
            'usuarioid' => (int) $this->usuarioid,
            'estado_tipo' => $this->whenLoaded('estadoTipo', fn () => $this->estadoTipo ? [
                'estadolotetipoid' => (int) $this->estadoTipo->estadolotetipoid,
                'nombre' => $this->estadoTipo->nombre,
            ] : null),
            'usuario' => $this->whenLoaded('usuario', fn () => $this->usuario ? [
                'usuarioid' => (int) $this->usuario->usuarioid,
                'nombre' => $this->usuario->nombre,
                'apellido' => $this->usuario->apellido,
            ] : null),
        ];
    }
}
