<?php

namespace App\Http\Resources\Api;

use App\Services\IncidenteReferenciaService;
use App\Services\IncidenteSeguimientoService;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class IncidenteEnvioResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $referencia = $this->resource->relationLoaded('consultaReferencia') ? $this->resource->getRelation('consultaReferencia')
            : app(IncidenteReferenciaService::class)->referencia($this->resource, $request->user());
        $persona = fn ($u) => $u ? ['usuarioid' => (int) $u->getKey(), 'nombre' => trim($u->nombre.' '.$u->apellido)] : null;

        return ['incidenteenvioid' => (int) $this->getKey(), 'tipo' => $this->tipo, 'descripcion' => $this->descripcion,
            'estado' => $this->estado, 'afectado' => $referencia,
            'afectado_referencia' => $referencia ? IncidenteReferenciaService::ETIQUETAS[$referencia['tipo']].' #'.$referencia['id'] : null,
            'afectado_estado' => $referencia ? 'disponible' : 'Vínculo no disponible para esta cuenta o sin referencia tipificada histórica',
            'pedidoid' => $referencia ? $this->pedidoid : null,
            'externo_envio_id' => $referencia ? $this->externo_envio_id : null,
            'responsable_usuarioid' => $this->responsable_usuarioid, 'responsable' => $persona($this->responsable),
            'responsable_nombre' => $this->responsable ? trim($this->responsable->nombre.' '.$this->responsable->apellido) : null,
            'seguimiento' => in_array($this->estado, ['abierto', 'pendiente'], true) ? 'Pendiente de resolución' : ($this->estado === 'resuelto' ? 'Resuelta' : $this->estado),
            'reportadopor_usuarioid' => $this->reportadopor_usuarioid, 'reportado_por' => $persona($this->reportadoPor),
            'created_at' => $this->created_at?->toIso8601String(),
            'nota_resolucion' => $this->nota_resolucion, 'fecha_resolucion' => $this->fecha_resolucion?->toIso8601String(),
            'resueltopor_usuarioid' => $this->resueltopor_usuarioid, 'resuelto_por' => $persona($this->resueltoPor),
            'puede_resolver' => $this->resource->relationLoaded('consultaResolver') ? $this->resource->getRelation('consultaResolver')
                : app(IncidenteSeguimientoService::class)->puedeResolver($this->resource, $request->user()),
        ];
    }
}
