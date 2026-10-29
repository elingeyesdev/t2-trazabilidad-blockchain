<?php

namespace App\Http\Resources\Api;

use App\Support\EvidenciaFoto;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ActividadConsultaResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $pendiente = $this->fechafin === null;

        return [
            'actividadid' => (int) $this->actividadid,
            'loteid' => (int) $this->loteid,
            'usuarioid' => $this->usuarioid === null ? null : (int) $this->usuarioid,
            'usuarioid_ejecutor' => $this->usuarioid_ejecutor === null ? null : (int) $this->usuarioid_ejecutor,
            'descripcion' => $this->descripcion,
            'fechainicio' => $this->fechainicio,
            'fecha_planificada' => $this->fecha_planificada?->toDateString(),
            'fechafin' => $this->fechafin,
            'tipoactividadid' => (int) $this->tipoactividadid,
            'prioridadid' => (int) $this->prioridadid,
            'observaciones' => $this->observaciones,
            'evidencia_foto_path' => $this->evidencia_foto_path,
            'evidencia_foto_url' => EvidenciaFoto::urlDesdePath($this->evidencia_foto_path),
            'tiene_evidencia' => filled($this->evidencia_foto_path),
            'pendiente' => $pendiente,
            'completada' => ! $pendiente,
            'estado_tarea' => $pendiente ? 'pendiente' : 'completada',
            'responsable' => $this->whenLoaded('usuario', fn () => $this->presentarUsuario($this->usuario)),
            'usuario' => $this->whenLoaded('usuario', fn () => $this->presentarUsuario($this->usuario)),
            'ejecutor' => $this->whenLoaded('ejecutor', fn () => $this->presentarUsuario($this->ejecutor)),
            'tipo_actividad' => $this->whenLoaded('tipoActividad', fn () => $this->tipoActividad ? [
                'tipoactividadid' => (int) $this->tipoActividad->tipoactividadid,
                'nombre' => $this->tipoActividad->nombre,
            ] : null),
            'prioridad' => $this->whenLoaded('prioridad', fn () => $this->prioridad ? [
                'prioridadid' => (int) $this->prioridad->prioridadid,
                'nombre' => $this->prioridad->nombre,
            ] : null),
            'lote' => $this->whenLoaded('lote', fn () => $this->lote ? [
                'loteid' => (int) $this->lote->loteid,
                'nombre' => $this->lote->nombre,
                'cultivo' => $this->lote->cultivo ? [
                    'cultivoid' => (int) $this->lote->cultivo->cultivoid,
                    'nombre' => $this->lote->cultivo->nombre,
                ] : null,
                'estado_tipo' => $this->lote->estadoTipo ? [
                    'estadolotetipoid' => (int) $this->lote->estadoTipo->estadolotetipoid,
                    'nombre' => $this->lote->estadoTipo->nombre,
                ] : null,
            ] : null),
        ];
    }

    /** @return array<string, int|string|null>|null */
    private function presentarUsuario($usuario): ?array
    {
        if (! $usuario) {
            return null;
        }

        return [
            'usuarioid' => (int) $usuario->usuarioid,
            'nombre' => $usuario->nombre,
            'apellido' => $usuario->apellido,
        ];
    }
}
