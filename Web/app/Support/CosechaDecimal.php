<?php

namespace App\Support;

use App\Models\UnidadMedida;
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Validation\ValidationException;

/** Exact decimal arithmetic using brick/math, already locked by Laravel's dependencies. */
final class CosechaDecimal
{
    public const MAXIMO = '999999999999.999999';

    public static function cantidad(mixed $valor, string $campo = 'cantidad'): string
    {
        if (! is_scalar($valor) || is_bool($valor)
            || ! preg_match('/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/D', (string) $valor)) {
            throw ValidationException::withMessages([$campo => 'Indica un número positivo, sin separadores de miles, con punto decimal y hasta seis decimales (máximo '.self::MAXIMO.').']);
        }
        $numero = BigDecimal::of((string) $valor);
        if (! $numero->isPositive()) {
            throw ValidationException::withMessages([$campo => 'La cantidad debe ser mayor que cero.']);
        }

        return (string) $numero->toScale(6);
    }

    /** Factors already used by AlmacenCapacidadService; exact aliases, never a fallback to kg. */
    public static function factorUnidad(UnidadMedida $unidad): ?string
    {
        if ($unidad->categoria !== 'peso') {
            return null;
        }

        return match (mb_strtolower(trim($unidad->abreviatura ?: $unidad->nombre))) {
            'kg', 'kilogramo', 'kilogramos' => '1',
            'g', 'gr', 'gramo', 'gramos' => '0.001',
            't', 'tn', 'ton', 'tonelada', 'toneladas' => '1000',
            'qq', 'quintal', 'quintales' => '46',
            'lb', 'libra', 'libras' => '0.453592',
            default => null,
        };
    }

    public static function kg(string $cantidad, string $factor): string
    {
        $exacto = BigDecimal::of($cantidad)->multipliedBy($factor);
        // Check before rounding: an overflowing input must not round back into range.
        if ($exacto->isGreaterThan(self::MAXIMO)) {
            throw ValidationException::withMessages(['cantidad' => 'La equivalencia en kg supera la capacidad de almacenamiento.']);
        }
        $kg = $exacto->toScale(6, RoundingMode::HALF_UP);
        if (! $kg->isPositive()) {
            throw ValidationException::withMessages(['cantidad' => 'La equivalencia es menor que la precisión mínima de 0.000001 kg.']);
        }

        return (string) $kg;
    }

    /** Formatting for Blade without turning the persisted decimal into a float. */
    public static function mostrar(string|int|float|null $numero): string
    {
        if ($numero === null) {
            return '—';
        }
        $texto = (string) BigDecimal::of((string) $numero)->toScale(6, RoundingMode::HALF_UP);

        return rtrim(rtrim($texto, '0'), '.');
    }
}
