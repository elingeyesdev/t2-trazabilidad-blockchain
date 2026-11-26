<?php

namespace App\Http\Resources\Api;

use App\Support\ActividadConsulta;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ActividadConsultaResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $pendiente = $this->resource->estaPendiente();
        $consulta = ActividadConsulta::presentar($this->resource, true);

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
            ...$consulta,
            // Keep the legacy key without disclosing a private storage locator.
            'evidencia_foto_path' => null,
            'pendiente' => $pendiente,
            'completada' => $this->fechafin !== null,
            'estado_tarea' => $this->cancelada_en ? 'cancelada' : ($pendiente ? 'pendiente' : 'completada'),
            'cancelada_en' => $this->cancelada_en,
            'motivo_cancelacion' => $this->motivo_cancelacion,
            'responsable' => $this->whenLoaded('usuario', fn () => $this->presentarUsuario($this->usuario)),
            'usuario' => $this->whenLoaded('usuario', fn () => $this->presentarUsuario($this->usuario)),
            'ejecutor' => $this->whenLoaded('ejecutor', fn () => $this->presentarUsuario($this->ejecutor)),
            'responsable_cierre' => $pendiente ? null : $this->whenLoaded('ejecutor', fn () => $this->presentarUsuario($this->ejecutor)),
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
                'insumosemillaid' => $this->lote->insumosemillaid === null ? null : (int) $this->lote->insumosemillaid,
                'cantidad_semilla_planificada' => $this->lote->cantidad_semilla_planificada === null
                    ? null
                    : (string) $this->lote->getRawOriginal('cantidad_semilla_planificada'),
                'insumo_semilla' => $this->lote->relationLoaded('insumoSemilla') && $this->lote->insumoSemilla ? [
                    'insumoid' => (int) $this->lote->insumoSemilla->insumoid,
                    'almacenid' => $this->lote->insumoSemilla->almacenid === null ? null : (int) $this->lote->insumoSemilla->almacenid,
                    'nombre' => $this->lote->insumoSemilla->nombre,
                    'unidadmedidaid' => (int) $this->lote->insumoSemilla->unidadmedidaid,
                    'unidad' => $this->lote->insumoSemilla->unidadMedida?->abreviatura ?? $this->lote->insumoSemilla->unidadMedida?->nombre,
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
