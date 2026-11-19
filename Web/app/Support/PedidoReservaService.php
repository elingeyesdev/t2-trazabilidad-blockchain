<?php

namespace App\Support;

use App\Models\AlmacenMovimiento;
use App\Models\Insumo;
use App\Models\Pedido;
use App\Models\ProduccionAlmacenamiento;
use App\Models\TipoMovimientoAlmacen;
use App\Services\InventarioExistenciaService;
use App\Services\PedidoEntradaService;
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

final class PedidoReservaService
{
    public function verificarDisponibilidad(Pedido $pedido): array
    {
        try {
            $this->comprobar($pedido, false);

            return [];
        } catch (InvalidArgumentException $e) {
            return [$e->getMessage()];
        }
    }

    private function comprobar(Pedido $pedido, bool $bloquear): array
    {
        $pedido->loadMissing('detalles');
        $lineas = $pedido->detalles->sortBy(fn ($d) => $d->producto_ref ?: 'insumo:'.$d->insumoid);
        $fuentes = [];
        $totales = [];
        foreach ($lineas as $d) {
            $cosecha = $d->produccionalmacenamientoid || str_starts_with($d->producto_ref ?? '', 'cosecha:');
            $id = $cosecha ? ($d->produccionalmacenamientoid ?: (int) substr($d->producto_ref, 8)) : ($d->insumoid ?: (int) substr($d->producto_ref ?? '', 7));
            $parteId = $d->materiaprimaloteid ? (int) $d->materiaprimaloteid : null;
            $clave = ($cosecha ? 'cosecha:' : 'insumo:').$id.':'.($parteId ?? 0);
            if (! $id) {
                throw new InvalidArgumentException('El pedido no identifica existencias reales para todas sus líneas.');
            }
            if (! isset($fuentes[$clave])) {
                $query = $cosecha ? ProduccionAlmacenamiento::with(['unidadMedida', 'produccion', 'almacen'])->whereKey($id) : Insumo::with(['unidadMedida', 'almacen'])->whereKey($id);
                if ($bloquear && ! $cosecha) {
                    app(InventarioExistenciaService::class)->bloquear([(int) $id]);
                }
                if ($bloquear) {
                    $query->lockForUpdate();
                }
                $origen = $query->first();
                if (! $origen) {
                    throw new InvalidArgumentException('El origen del pedido ya no existe.');
                }
                if ($bloquear && (! $origen->almacen || ! CampoAccess::puedeGestionarAlmacen(auth()->user(), $origen->almacen))) {
                    abort(403, 'No puede comprometer existencias de un almacén agrícola ajeno.');
                }
                $factor = $d->datos_solicitud['factor_origen_kg'] ?? ($cosecha ? ($origen->produccion?->presentacion_cosecha['unidad_factor_kg'] ?? null) : null) ?? app(PedidoEntradaService::class)->factor($origen->unidadMedida);
                if ($factor === null) {
                    throw new InvalidArgumentException('No hay equivalencia verificable en kg para el origen.');
                }
                $stock = $cosecha ? ($origen->fechasalida ? '0' : $origen->getRawOriginal('cantidad')) : app(InventarioExistenciaService::class)->resumen($origen)['cantidad_disponible'];
                if (! $cosecha) {
                    $partidas = app(InventarioExistenciaService::class)->partidas($origen, $bloquear);
                    if ($partidas->isNotEmpty() && ! $parteId) {
                        throw new InvalidArgumentException('El pedido debe identificar la partida de material que realmente se consume.');
                    }
                    if ($parteId) {
                        $parte = $partidas->firstWhere('materiaprimaloteid', $parteId);
                        if (! $parte || ! app(InventarioExistenciaService::class)->utilizable($parte)) {
                            throw new InvalidArgumentException('La partida de material no pertenece al producto o ya no está habilitada.');
                        }
                        $stockParte = BigDecimal::of((string) $parte->getRawOriginal('cantidad_disponible'));
                        $stock = (string) ($stockParte->isLessThan((string) $stock) ? $stockParte : BigDecimal::of((string) $stock));
                    }
                }
                $fuentes[$clave] = compact('origen', 'factor', 'stock', 'cosecha', 'parteId');
            }
            $totales[$clave] = ($totales[$clave] ?? BigDecimal::zero())->plus((string) $d->getRawOriginal('cantidad'));
        }
        foreach ($totales as $clave => $cantidad) {
            $f = $fuentes[$clave];
            try {
                $nativa = $cantidad->dividedBy($f['factor'], 6, RoundingMode::UNNECESSARY);
            } catch (\Brick\Math\Exception\MathException $e) {
                throw new InvalidArgumentException('La cantidad no es representable en la unidad de origen con seis decimales.');
            }
            if ($nativa->isGreaterThan((string) $f['stock'])) {
                throw new InvalidArgumentException('La cantidad acumulada supera las existencias disponibles del origen '.$clave.'.');
            }
            $fuentes[$clave]['cantidad'] = (string) $nativa;
        }

        return $fuentes;
    }

    public function reservar(Pedido $pedido): void
    {
        DB::transaction(function () use ($pedido) {
            foreach ($this->comprobar($pedido, true) as $f) {
                $origen = $f['origen'];
                $cantidad = $f['cantidad'];
                if ($f['cosecha']) {
                    $saldo = BigDecimal::of((string) $origen->getRawOriginal('cantidad'))->minus($cantidad);
                    $origen->update(['cantidad' => (string) $saldo->toScale(6), 'fechasalida' => $saldo->isZero() ? now() : null,
                        'observaciones' => trim(($origen->observaciones ?? '').' Reservado para pedido '.$pedido->numero_solicitud.'.')]);
                } else {
                    $origen->decrementarStock($cantidad, $f['parteId']);
                    $tipo = TipoMovimientoAlmacen::activosPorNaturaleza('salida')->firstOrFail();
                    AlmacenMovimiento::create(['almacenid' => $origen->almacenid, 'insumoid' => $origen->getKey(), 'tipo_movimiento_almacenid' => $tipo->getKey(),
                        'fecha' => now(), 'cantidad' => $cantidad, 'materiaprimaloteid' => $f['parteId'], 'unidadmedidaid' => $origen->unidadmedidaid, 'referencia' => $pedido->numero_solicitud, 'destino_motivo' => 'Reserva pedido planta', 'usuarioid' => auth()->id()]);
                }
            }
        }, 5);
    }
}
