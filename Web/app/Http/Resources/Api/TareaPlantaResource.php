<?php

namespace App\Http\Resources\Api;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TareaPlantaResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $registro = $this->registro;
        $datos = $registro ? json_decode($registro->variables_ingresadas, true) : [];

        return [
            'asignacionetapaplantaid' => (int) $this->getKey(), 'orden' => (int) $this->orden,
            'estado' => $this->estado, 'creado_en' => $this->creado_en?->toIso8601String(),
            'completada_en' => $this->completada_en?->toIso8601String(),
            'observaciones' => $this->observaciones,
            'proceso' => ['procesoplantaid' => (int) $this->procesoplantaid, 'nombre' => $this->proceso?->nombre],
            'maquina' => ['maquinaplantaid' => (int) $this->maquinaplantaid, 'nombre' => $this->maquina?->nombre,
                'codigo' => $this->maquina?->codigo, 'activo' => (bool) $this->maquina?->activo],
            'lote_produccion' => ['loteproduccionpedidoid' => (int) $this->loteproduccionpedidoid,
                'codigo_lote' => $this->loteProduccion?->codigo_lote, 'nombre' => $this->loteProduccion?->nombre,
                'producto' => $this->loteProduccion?->producto, 'fecha_creacion' => $this->loteProduccion?->fecha_creacion?->toDateString()],
            'resultado' => $registro ? ['registroprocesomaquinaplantaid' => (int) $registro->getKey(),
                'usuarioid' => (int) $registro->usuarioid, 'fecha_registro' => $registro->fecha_registro?->toIso8601String(),
                'parametros' => $datos['parametros'] ?? []] : null,
        ];
    }
}
