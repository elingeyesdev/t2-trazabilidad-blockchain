<?php

namespace App\Services;

use App\Models\CatalogoTamanoConteo;
use App\Models\Lote;
use App\Models\Produccion;
use App\Models\ProduccionAlmacenamiento;
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Validation\ValidationException;

/**
 * Convierte kg de cosecha en unidades y cajas según el calibre planificado.
 */
class CosechaPresentacionService
{
    public function __construct(
        private readonly AlmacenCapacidadService $capacidadService,
        private readonly PlanificacionCosechaService $planificacion,
    ) {}

    /**
     * En campo la cosecha se cuenta en cajas; el saco es solo traslado agrícola→planta.
     */
    public static function tipoEmpaqueParaCosechaEnCampo(?string $nombreTipo): ?string
    {
        $n = mb_strtolower(trim($nombreTipo ?? ''));
        if ($n === 'saco' || str_contains($n, 'saco')) {
            return 'Caja de cartón';
        }

        return $nombreTipo;
    }

    public static function etiquetaEmpaque(?string $nombreTipo): string
    {
        $n = mb_strtolower(trim($nombreTipo ?? ''));

        if ($n === '' || $n === 'empaque') {
            return 'Empaque';
        }
        if ($n === 'saco' || str_contains($n, 'saco')) {
            return 'Saco';
        }
        if (str_contains($n, 'canasta')) {
            return 'Canasta';
        }
        if (str_contains($n, 'caja')) {
            return 'Caja';
        }
        if (str_contains($n, 'bolsa')) {
            return 'Bolsa';
        }
        if (str_contains($n, 'bandeja')) {
            return 'Bandeja';
        }

        return $nombreTipo ?: 'Empaque';
    }

    public static function etiquetaEmpaquePlural(?string $nombreTipo): string
    {
        $singular = self::etiquetaEmpaque($nombreTipo);

        return match (mb_strtolower($singular)) {
            'caja' => 'Cajas',
            'saco' => 'Sacos',
            'canasta' => 'Canastas',
            'bolsa' => 'Bolsas',
            'bandeja' => 'Bandejas',
            default => $singular.'s',
        };
    }

    /** @return array<string, mixed> */
    public function desdeKg(string|int|float $kg, ?CatalogoTamanoConteo $calibre): array
    {
        $kg = BigDecimal::of((string) $kg)->toScale(6, RoundingMode::HALF_UP);
        if (! $calibre || ! BigDecimal::of((string) $calibre->peso_promedio_kg)->isPositive()
            || (int) $calibre->conteo_por_empaque <= 0) {
            return [
                'ok' => false,
                'kg' => (string) $kg,
                'unidades' => null,
                'empaques' => null,
                'empaque_label' => 'Cajas',
                'calibre_nombre' => null,
            ];
        }

        $pesoUnit = (string) $calibre->peso_promedio_kg;
        $conteo = (int) $calibre->conteo_por_empaque;
        $unidadesDecimal = $kg->dividedBy($pesoUnit, 0, RoundingMode::HALF_UP);
        $empaquesDecimal = $unidadesDecimal->dividedBy($conteo, 0, RoundingMode::CEILING);
        // unsignedInteger is a signed INTEGER on PostgreSQL; keep both channels portable.
        if ($unidadesDecimal->isGreaterThan('2147483647') || $empaquesDecimal->isGreaterThan('2147483647')) {
            throw ValidationException::withMessages(['cantidad' => 'La equivalencia en unidades o empaques supera la capacidad de almacenamiento.']);
        }
        $unidades = $unidadesDecimal->toInt();
        $empaques = $empaquesDecimal->toInt();
        $empaqueLabel = self::etiquetaEmpaquePlural(
            self::tipoEmpaqueParaCosechaEnCampo($calibre->tipoEmpaque?->nombre)
        );

        return [
            'ok' => true,
            'kg' => (string) $kg,
            'unidades' => $unidades,
            'empaques' => $empaques,
            'empaque_label' => $empaqueLabel,
            'empaque_singular' => self::etiquetaEmpaque(
                self::tipoEmpaqueParaCosechaEnCampo($calibre->tipoEmpaque?->nombre)
            ),
            'calibre_nombre' => $calibre->nombre,
            'calibre_id' => (int) $calibre->catalogotamanoconteoid,
            'conteo_por_empaque' => $conteo,
            'peso_promedio_kg' => $pesoUnit,
            'resumen' => number_format($empaques, 0, ',', '.').' '.$empaqueLabel
                .' · '.number_format($unidades, 0, ',', '.').' unidades',
        ];
    }

    /** @return array<string, mixed> */
    public function paraProduccion(Produccion $produccion, ?Lote $lote = null): array
    {
        if (is_array($produccion->presentacion_cosecha)) {
            return $produccion->presentacion_cosecha + ['historica_sin_factor' => false];
        }

        // Historical records keep only what was persisted. Never reconstruct missing
        // quantities/factors using the lot's or catalog's current configuration.
        $completa = $produccion->cantidad_unidades !== null && $produccion->cantidad_empaques !== null;

        return [
            'ok' => $completa,
            'kg' => $produccion->cantidad_base,
            'unidades' => $produccion->cantidad_unidades,
            'empaques' => $produccion->cantidad_empaques,
            'calibre_id' => $produccion->catalogotamanoconteoid,
            'calibre_nombre' => null,
            'empaque_label' => 'Empaques',
            'peso_promedio_kg' => null,
            'conteo_por_empaque' => null,
            'historica_sin_factor' => true,
            'resumen' => $completa ? $produccion->cantidad_empaques.' empaques · '.$produccion->cantidad_unidades.' unidades' : null,
        ];
    }

    /** @return array<string, mixed> */
    public function paraAlmacenamiento(ProduccionAlmacenamiento $row): array
    {
        $row->loadMissing([
            'produccion.unidadMedida',
            'produccion.lote.catalogoTamanoConteo.tipoEmpaque',
            'catalogoTamanoConteo.tipoEmpaque',
            'unidadMedida',
        ]);

        if ($row->cantidad_empaques !== null && $row->cantidad_unidades !== null) {
            $calibre = $row->catalogoTamanoConteo ?? $row->produccion?->lote?->catalogoTamanoConteo;
            $empaqueLabel = self::etiquetaEmpaquePlural(
                self::tipoEmpaqueParaCosechaEnCampo($calibre?->tipoEmpaque?->nombre)
            );

            return [
                'ok' => true,
                'kg' => round((float) $this->capacidadService->convertirAKg((float) $row->cantidad, $row->unidadMedida), 2),
                'unidades' => (int) $row->cantidad_unidades,
                'empaques' => (int) $row->cantidad_empaques,
                'empaque_label' => $empaqueLabel,
                'empaque_singular' => self::etiquetaEmpaque(
                    self::tipoEmpaqueParaCosechaEnCampo($calibre?->tipoEmpaque?->nombre)
                ),
                'calibre_nombre' => $calibre?->nombre,
                'calibre_id' => $calibre ? (int) $calibre->catalogotamanoconteoid : null,
                'resumen' => number_format((int) $row->cantidad_empaques, 0, ',', '.').' '.$empaqueLabel
                    .' · '.number_format((int) $row->cantidad_unidades, 0, ',', '.').' unidades',
            ];
        }

        return $this->paraProduccion($row->produccion, $row->produccion?->lote);
    }

}
