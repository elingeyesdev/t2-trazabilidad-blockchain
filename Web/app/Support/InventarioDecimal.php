<?php

namespace App\Support;

use InvalidArgumentException;

/** Decimal(18,6) represented as scaled integers; no binary floating point arithmetic. */
final class InventarioDecimal
{
    public static function unidades(string|int|float $valor): int
    {
        $texto = (string) $valor;
        // PDO/SQLite may stringify an already stored small decimal in exponent notation.
        if (preg_match('/^([0-9]+)(?:\.([0-9]+))?[eE]([+-]?[0-9]+)$/D', $texto, $exponente)) {
            $digitos = $exponente[1].($exponente[2] ?? '');
            $punto = strlen($exponente[1]) + (int) $exponente[3];
            if ($punto < -6 || $punto > 12) {
                throw new InvalidArgumentException('Cantidad fuera de la precisión decimal admitida.');
            }
            $texto = $punto <= 0 ? '0.'.str_repeat('0', -$punto).$digitos
                : substr(str_pad($digitos, $punto, '0'), 0, $punto).'.'.substr($digitos, $punto);
            $texto = rtrim(rtrim($texto, '0'), '.');
        }
        if (! preg_match('/^(0|[1-9][0-9]{0,11})(?:\.([0-9]{1,6}))?$/D', $texto, $m)) {
            throw new InvalidArgumentException('Cantidad decimal fuera de rango o con precisión no admitida.');
        }

        return ((int) $m[1]) * 1000000 + (int) str_pad($m[2] ?? '', 6, '0');
    }

    public static function texto(int $unidades, int $escala = 6): string
    {
        if ($unidades < 0) {
            throw new InvalidArgumentException('La cantidad no puede ser negativa.');
        }

        return intdiv($unidades, 1000000).'.'.substr(str_pad((string) ($unidades % 1000000), 6, '0', STR_PAD_LEFT), 0, $escala);
    }

    public static function consumo(string|int|float $valor): string
    {
        if (! preg_match('/^(0|[1-9][0-9]{0,10})(?:\.[0-9]{1,3})?$/D', (string) $valor)) {
            throw new InvalidArgumentException('Indique una cantidad positiva con hasta tres decimales.');
        }
        $unidades = self::unidades($valor);
        if ($unidades === 0) {
            throw new InvalidArgumentException('La cantidad debe ser mayor a cero.');
        }

        return self::texto($unidades, 3);
    }
}
