<?php

namespace App\Support;

use App\Models\Insumo;
use App\Models\PuntoVenta;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/** Persistent identity of the product held in a PDV warehouse, not of a presentation. */
final class CodigoTrazabilidadPdv
{
    public static function elegible(Insumo $insumo): bool
    {
        return $insumo->almacenid !== null
            && PuntoVenta::where('almacenid', $insumo->almacenid)->exists();
    }

    public static function generar(): string
    {
        // Reuse the UUID format already issued by conserved PDV receptions.
        // The unique index on insumo.codigo_trazabilidad arbitrates concurrent inserts.
        return 'TRZ-PDV-'.strtoupper((string) Str::uuid());
    }

    public static function asegurar(Insumo $insumo): string
    {
        if (filled($insumo->codigo_trazabilidad)) {
            return $insumo->codigo_trazabilidad;
        }
        if (! self::elegible($insumo)) {
            throw ValidationException::withMessages(['codigo_trazabilidad' => 'El producto no pertenece a un punto de venta registrado.']);
        }
        $codigo = self::generar();
        // Atomic compare-and-set: parallel regularizations never overwrite the winner.
        Insumo::whereKey($insumo->getKey())->where('almacenid', $insumo->almacenid)
            ->whereIn('almacenid', PuntoVenta::whereNotNull('almacenid')->select('almacenid'))
            ->where(fn ($q) => $q->whereNull('codigo_trazabilidad')
                ->orWhereRaw("TRIM(codigo_trazabilidad) = ''"))->update(['codigo_trazabilidad' => $codigo]);
        $insumo->refresh();
        if (blank($insumo->codigo_trazabilidad)) {
            throw ValidationException::withMessages(['codigo_trazabilidad' => 'La existencia cambió durante la regularización. Revise el punto de venta antes de reintentar.']);
        }

        return $insumo->codigo_trazabilidad;
    }

    public static function datos(Insumo $insumo): array
    {
        $codigo = $insumo->codigo_trazabilidad;
        $elegible = self::elegible($insumo);
        $estado = $elegible ? 'sin_codigo_todavia' : 'no_aplica';
        $url = null;
        if ($elegible && filled($codigo)) {
            try {
                $normalizado = CodigoTrazabilidadPublica::normalizar($codigo);
                if (str_starts_with($normalizado, 'TRZ-PDV-')) {
                    $url = self::url($normalizado);
                    $estado = 'disponible';
                } else {
                    $estado = 'codigo_no_admitido';
                }
            } catch (ValidationException) {
                $estado = 'codigo_no_admitido';
            }
        }

        return ['codigo_trazabilidad' => $codigo, 'trazabilidad_url' => $url, 'trazabilidad_estado' => $estado];
    }

    public static function url(string $codigo): string
    {
        $codigo = CodigoTrazabilidadPublica::normalizar($codigo);
        $base = rtrim((string) (config('app.public_url') ?: config('app.url')), '/');
        $partes = parse_url($base);
        if (! is_array($partes) || ! in_array($partes['scheme'] ?? '', ['http', 'https'], true)
            || empty($partes['host']) || isset($partes['user']) || isset($partes['pass'])
            || isset($partes['query']) || isset($partes['fragment'])) {
            throw new \LogicException('Configure APP_URL o APP_PUBLIC_URL con una URL HTTP válida.');
        }

        return $base.route('trazabilidad.publica', ['codigo' => $codigo], false);
    }
}
