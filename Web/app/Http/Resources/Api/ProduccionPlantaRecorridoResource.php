<?php

namespace App\Http\Resources\Api;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** Recibe exclusivamente el DTO autorizado, nunca modelos ni relaciones serializadas. */
class ProduccionPlantaRecorridoResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return ['nivel' => $this->resource['nivel'], 'lote_produccion' => $this->resource['lote_produccion'],
            'productos_obtenidos' => $this->resource['productos_obtenidos'], 'origenes' => $this->resource['origenes'], 'ingresos_produccion' => $this->resource['ingresos_produccion'],
            'ubicaciones_actuales' => $this->resource['ubicaciones_actuales'], 'restricciones' => $this->resource['restricciones']];
    }
}
