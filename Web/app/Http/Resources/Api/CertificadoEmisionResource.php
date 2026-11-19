<?php

namespace App\Http\Resources\Api;

use App\Models\CertificacionLote;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Arr;

class CertificadoEmisionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $campo = $this->resource instanceof CertificacionLote;

        return [
            $campo ? 'certificacionid' : 'evaluacionfinalloteid' => (int) $this->getKey(),
            $campo ? 'loteid' : 'loteproduccionpedidoid' => (int) ($campo ? $this->loteid : $this->loteproduccionpedidoid),
            'codigo_certificado' => $this->codigo_certificado, 'emision_uuid' => $this->emision_uuid,
            $campo ? 'resultado' : 'razon' => $campo ? $this->resultado : $this->razon,
            'observaciones' => $this->observaciones, 'recomendaciones' => $this->recomendaciones,
            $campo ? 'usuarioid' : 'inspector_usuarioid' => $campo ? $this->usuarioid : $this->inspector_usuarioid,
            $campo ? 'fecha_certificacion' : 'fecha_evaluacion' => ($campo ? $this->fecha_certificacion : $this->fecha_evaluacion)?->toIso8601String(),
            'instantanea_disponible' => is_array($this->datos_emision),
            'instantanea' => is_array($this->datos_emision) ? Arr::except($this->datos_emision, ['blockchain_base']) : null,
            'archivo_disponible' => filled($this->archivo_path), 'formato_version' => $this->formato_version,
            // Compatibilidad: relaciones actuales resumidas; los datos históricos están en instantanea.
            'lote' => $campo && $this->lote ? ['loteid' => (int) $this->loteid, 'nombre' => $this->lote->nombre] : null,
            'usuario' => $campo && $this->usuario ? ['usuarioid' => (int) $this->usuarioid, 'nombre' => $this->usuario->nombre, 'apellido' => $this->usuario->apellido] : null,
            'blockchain_estado' => $campo ? $this->blockchain_estado : null,
        ];
    }
}
