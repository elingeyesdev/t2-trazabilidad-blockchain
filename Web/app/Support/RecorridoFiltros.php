<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

final class RecorridoFiltros
{
    public static function validar(Request $request): array
    {
        $f = $request->validate([
            'desde' => ['nullable', 'required_with:hasta', 'date_format:Y-m-d'],
            'hasta' => ['nullable', 'required_with:desde', 'date_format:Y-m-d', 'after_or_equal:desde'],
            'almacenid' => ['nullable', 'integer', 'min:1'],
            'tipo' => ['nullable', 'required_with:partida', 'in:cosecha,planta'],
            'partida' => ['nullable', 'required_with:tipo', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:1,50'],
            'pendientes_page' => ['nullable', 'integer', 'min:1'],
            'bajas_page' => ['nullable', 'integer', 'min:1'],
        ]);
        if (! empty($f['desde']) && CarbonImmutable::parse($f['desde'])->diffInDays(CarbonImmutable::parse($f['hasta'])) > 366) {
            throw ValidationException::withMessages(['hasta' => 'El intervalo máximo es de 366 días.']);
        }
        if (! empty($f['almacenid'])) {
            abort_unless($request->user()->can('inventario.view')
                && in_array((int) $f['almacenid'], AlmacenAcceso::idsVisibles($request->user()), true), 404);
        }

        return $f;
    }

    /** Dates without time stay calendar dates; datetimes use the application timezone. */
    public static function coincide(?string $fecha, ?int $almacen, array $f, bool $almacenAplica = true): bool
    {
        if (! empty($f['almacenid']) && $almacenAplica && $almacen !== (int) $f['almacenid']) {
            return false;
        }
        if (empty($f['desde'])) {
            return true;
        }
        if (! $fecha) {
            return false;
        }
        $dia = strlen($fecha) === 10 ? $fecha : CarbonImmutable::parse($fecha, config('app.timezone'))->setTimezone(config('app.timezone'))->toDateString();

        return $dia >= $f['desde'] && $dia <= $f['hasta'];
    }
}
