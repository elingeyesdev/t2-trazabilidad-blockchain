<?php

namespace App\Http\Resources\Api;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** Explicit public envelope. Internal source models are never serialized. */
class TrazabilidadPublicaResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'codigo' => $this->resource['codigo'],
            'tipo' => $this->resource['tipo'],
            'producto' => $this->resource['producto'],
            'origenes' => $this->resource['origenes'],
            'etapas' => $this->resource['etapas'],
            'rutas' => $this->resource['rutas'],
            'evidencias' => $this->resource['evidencias'],
            'estado_evidencias' => $this->resource['estado_evidencias'],
            'certificaciones' => $this->resource['certificaciones'],
            'blockchain' => $this->resource['blockchain'],
        ];
    }
}
