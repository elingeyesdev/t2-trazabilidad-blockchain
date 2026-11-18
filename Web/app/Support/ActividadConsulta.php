<?php

namespace App\Support;

use App\Models\Actividad;
use Illuminate\Support\Facades\Storage;

/** Read-only presentation shared by the activity detail and its API resource. */
final class ActividadConsulta
{
    public static function presentar(Actividad $actividad, bool $api = false): array
    {
        $cerrada = $actividad->fechafin !== null;
        $detalle = json_decode($actividad->detalle_json ?? '', true);
        $detalle = is_array($detalle) ? $detalle : [];
        $foto = self::archivo($actividad);
        $estado = ! $cerrada || ! filled($actividad->evidencia_foto_path) ? 'sin_fotografia'
            : ($foto && Storage::disk($foto['disk'])->exists($foto['path']) ? 'disponible' : 'no_disponible');
        $consumos = [];
        if ($cerrada && ! empty($detalle['stock_aplicado'])) {
            foreach ($detalle['insumos'] ?? [] as $fila) {
                if (! is_array($fila)) {
                    continue;
                }
                $consumos[] = [
                    'insumoid' => (int) ($fila['insumoid'] ?? 0),
                    'nombre' => $fila['nombre'] ?? null,
                    'cantidad' => (string) ($fila['cantidad'] ?? ''),
                    'unidadmedidaid' => isset($fila['unidadmedidaid']) ? (int) $fila['unidadmedidaid'] : null,
                    'unidad' => $fila['unidad'] ?? null,
                    'unidad_historica' => isset($fila['unidad']),
                    'almacenid' => isset($fila['almacenid']) ? (int) $fila['almacenid'] : null,
                    'materiaprimaloteid' => $fila['materiaprimaloteid'] ?? null,
                ];
            }
        } elseif ($cerrada) {
            $actividad->loadMissing('consumos.insumo.unidadMedida');
            foreach ($actividad->consumos as $consumo) {
                // Never use unassigned lot consumptions, including malformed cross-lot rows.
                if ((int) $consumo->loteid !== (int) $actividad->loteid) {
                    continue;
                }
                $consumos[] = [
                    'insumoid' => (int) $consumo->insumoid,
                    'nombre' => $consumo->insumo?->nombre,
                    'cantidad' => InventarioDecimal::texto(InventarioDecimal::unidades($consumo->getRawOriginal('cantidadusada'))),
                    'unidadmedidaid' => $consumo->insumo?->unidadmedidaid,
                    'unidad' => $consumo->insumo?->unidadMedida?->abreviatura ?? $consumo->insumo?->unidadMedida?->nombre,
                    'unidad_historica' => false,
                    // Legacy consumption has no historical warehouse column.
                    'almacenid' => null,
                ];
            }
        }

        return [
            'resultado' => $cerrada ? ($detalle['cierre']['resultado'] ?? null) : null,
            'consumos' => $consumos,
            'evidencia_estado' => $estado,
            'evidencia_foto_url' => $estado === 'disponible'
                ? route($api ? 'api.actividades.evidencia' : 'actividades.evidencia', ['actividad' => $actividad->actividadid]) : null,
            'tiene_evidencia' => $cerrada && filled($actividad->evidencia_foto_path),
        ];
    }

    public static function archivo(Actividad $actividad): ?array
    {
        $path = $actividad->evidencia_foto_path;
        if (! is_string($path) || str_contains($path, '..') || str_contains($path, '\\') || str_contains($path, "\0")) {
            return null;
        }
        if (preg_match('#^actividades_privadas/'.$actividad->actividadid.'/[^/]+$#D', $path)) {
            return ['disk' => 'local', 'path' => $path];
        }
        if (preg_match('#^actividades_evidencia/[^/]+$#D', $path)) {
            return ['disk' => 'public', 'path' => $path];
        }

        return null;
    }
}
