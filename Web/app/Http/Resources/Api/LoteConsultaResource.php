<?php

namespace App\Http\Resources\Api;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Collection;

class LoteConsultaResource extends JsonResource
{
    private ?Collection $historialConsulta = null;

    public function withHistorial(Collection $historial): self
    {
        $this->historialConsulta = $historial;

        return $this;
    }

    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $actividades = $this->whenLoaded('actividades', fn () => ActividadConsultaResource::collection($this->actividades));
        $data = [
            'loteid' => (int) $this->loteid,
            'usuarioid' => $this->usuarioid === null ? null : (int) $this->usuarioid,
            'nombre' => $this->nombre,
            'ubicacion' => $this->ubicacion,
            'superficie' => $this->superficie,
            'unidadsuperficieid' => $this->unidadsuperficieid === null ? null : (int) $this->unidadsuperficieid,
            'cultivoid' => $this->cultivoid === null ? null : (int) $this->cultivoid,
            'insumosemillaid' => $this->insumosemillaid === null ? null : (int) $this->insumosemillaid,
            'cantidad_semilla_planificada' => $this->cantidad_semilla_planificada,
            'codigo_trazabilidad' => $this->codigo_trazabilidad,
            'fechasiembra' => $this->fechasiembra?->toDateString(),
            'fechacreacion' => $this->fechacreacion,
            'fechamodificacion' => $this->fechamodificacion,
            'estadolotetipoid' => $this->estadolotetipoid === null ? null : (int) $this->estadolotetipoid,
            'latitud' => $this->latitud,
            'longitud' => $this->longitud,
            'imagenurl' => $this->imagenurl,
            'cultivo_etiqueta' => $this->cultivo_etiqueta,
            'usuario' => $this->whenLoaded('usuario', fn () => $this->presentarUsuario($this->usuario)),
            'cultivo' => $this->whenLoaded('cultivo', fn () => $this->cultivo ? [
                'cultivoid' => (int) $this->cultivo->cultivoid,
                'nombre' => $this->cultivo->nombre,
                'detalle' => $this->cultivo->detalle,
            ] : null),
            'estado_tipo' => $this->whenLoaded('estadoTipo', fn () => $this->estadoTipo ? [
                'estadolotetipoid' => (int) $this->estadoTipo->estadolotetipoid,
                'nombre' => $this->estadoTipo->nombre,
            ] : null),
            'estadoTipo' => $this->whenLoaded('estadoTipo', fn () => $this->estadoTipo ? [
                'estadolotetipoid' => (int) $this->estadoTipo->estadolotetipoid,
                'nombre' => $this->estadoTipo->nombre,
            ] : null),
            'insumo_semilla' => $this->whenLoaded('insumoSemilla', fn () => $this->insumoSemilla ? [
                'insumoid' => (int) $this->insumoSemilla->insumoid,
                'nombre' => $this->insumoSemilla->nombre,
            ] : null),
            'unidad_superficie' => $this->whenLoaded('unidadSuperficie', fn () => $this->unidadSuperficie ? [
                'unidadmedidaid' => (int) $this->unidadSuperficie->unidadmedidaid,
                'nombre' => $this->unidadSuperficie->nombre,
                'abreviatura' => $this->unidadSuperficie->abreviatura,
            ] : null),
            'actividades' => $actividades,
            'actividades_pendientes' => $this->whenLoaded(
                'actividades',
                fn () => $this->actividades->whereNull('fechafin')->count()
            ),
            'producciones' => $this->whenLoaded('producciones', fn () => $this->producciones->map(fn ($produccion) => [
                'produccionid' => (int) $produccion->produccionid,
                'cantidad' => $produccion->cantidad,
                'unidadmedidaid' => (int) $produccion->unidadmedidaid,
                'fechacosecha' => $produccion->fechacosecha,
                'imagenurl' => $produccion->imagenurl,
                'destinoproduccionid' => $produccion->destinoproduccionid === null ? null : (int) $produccion->destinoproduccionid,
            ])),
        ];

        if ($this->historialConsulta !== null) {
            $data['historial'] = $this->historialConsulta->values();
        }

        return $data;
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
