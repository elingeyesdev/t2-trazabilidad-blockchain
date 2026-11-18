<?php

namespace App\Http\Resources\Api;

use App\Services\CosechaPresentacionService;
use App\Support\EvidenciaFoto;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ProduccionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $presentacion = app(CosechaPresentacionService::class)->paraProduccion($this->resource);
        unset($presentacion['version']);

        return [
            'produccionid' => (int) $this->produccionid, 'loteid' => (int) $this->loteid,
            'cantidad' => $this->cantidad, 'unidadmedidaid' => $this->unidadmedidaid,
            'unidad' => $presentacion['unidad_abreviatura'] ?? $this->unidadMedida?->abreviatura,
            'cantidad_base' => $this->cantidad_base, 'cantidadkg' => $this->cantidad_base,
            'catalogotamanoconteoid' => $this->catalogotamanoconteoid,
            'cantidad_unidades' => $this->cantidad_unidades, 'cantidad_empaques' => $this->cantidad_empaques,
            'fechacosecha' => $this->fechacosecha?->format('Y-m-d'),
            'destinoproduccionid' => $this->destinoproduccionid,
            'observaciones' => $this->observaciones, 'imagenurl' => $this->imagenurl,
            'evidencia_foto_url' => EvidenciaFoto::urlDesdeImagenUrl($this->imagenurl),
            'presentacion' => $presentacion,
        ];
    }
}
