<?php

namespace App\Http\Resources\Api;

use App\Support\CodigoTrazabilidadPdv;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class InsumoInventarioResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // Additive representation: retain existing inventory keys and hidden attributes.
        return [...$this->resource->toArray(), ...CodigoTrazabilidadPdv::datos($this->resource)];
    }
}
