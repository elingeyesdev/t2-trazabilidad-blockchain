<?php

namespace App\Services;

use App\Models\Almacen;
use App\Models\DetallePedidoDistribucion;
use App\Models\Insumo;
use App\Models\PedidoDistribucion;
use App\Support\PedidoDistribucionCatalogo;
use App\Support\InventarioDecimal;
use Brick\Math\BigDecimal;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

/**
 * Reserva de stock mayorista para pedidos de distribución (MAY-10).
 *
 * No es un sistema paralelo de inventario: la reserva se DERIVA de los pedidos confirmados que
 * aún no salieron (estado «confirmado»), así que
 *   pedido confirmado → reserva
 *   inicio de ruta     → consumo (la salida se descuenta y el pedido pasa a «en tránsito»)
 *   rechazo/cancelación/reapertura → libera (el pedido deja de estar confirmado).
 * PedidoReservaService (Support) cubre los pedidos agrícolas y descuenta al aceptar; aquí el
 * descuento real sigue ocurriendo al iniciar la ruta, como ya lo hacía la distribución.
 *
 * Para que dos confirmaciones concurrentes no consuman el mismo stock, se bloquean las filas de
 * los almacenes de origen (lockForUpdate) y se revalida el disponible dentro de la transacción.
 */
class PedidoDistribucionReservaService
{
    public function __construct(
        private readonly InventarioPresentacionService $inventarioPresentacion,
    ) {}

    /**
     * Debe llamarse dentro de una transacción, antes de pasar el pedido a «confirmado».
     *
     * @throws InvalidArgumentException
     */
    public function reservar(PedidoDistribucion $pedido): void
    {
        if (DB::transactionLevel() === 0) {
            throw new \LogicException('La reserva de stock debe ejecutarse dentro de una transacción.');
        }

        $pedido->loadMissing(['detalles.presentacion', 'detalles.insumo']);
        $almacenIds = $pedido->detalles
            ->map(fn (DetallePedidoDistribucion $d) => $this->almacenDeLinea($d, $pedido))
            ->filter()
            ->unique()
            ->values()
            ->all();

        if ($almacenIds === []) {
            return;
        }

        // Adquirir los locks compartidos de existencias antes de consultar disponibilidad.
        app(InventarioExistenciaService::class)->bloquear($pedido->detalles->pluck('insumoid')->filter()->unique()->values()->all());

        // Mutex por almacén: serializa reservas que compiten por el mismo stock.
        Almacen::query()->whereIn('almacenid', $almacenIds)->orderBy('almacenid')->lockForUpdate()->get();

        foreach ($pedido->detalles as $detalle) {
            if ($detalle->es_solicitud_custom || (int) $detalle->insumoid <= 0) {
                continue;
            }

            $almacenId = $this->almacenDeLinea($detalle, $pedido);
            $solicitado = (float) $detalle->cantidad;
            $disponible = $this->disponible($detalle, $almacenId, (int) $pedido->pedidodistribucionid);

            if ($solicitado > $disponible + 0.0001) {
                $nombre = $detalle->producto_nombre ?: 'Producto';
                throw new InvalidArgumentException(
                    "Stock insuficiente para «{$nombre}»: solicitado ".number_format($solicitado, 2)
                    .', disponible sin reservar '.number_format(max(0, $disponible), 2).'.'
                );
            }
        }

        // Las líneas legadas sin presentación expresan cantidad en la unidad del producto.
        // Acumularlas: comprobar cada línea por separado permitiría comprometer dos veces el saldo.
        $legadas = $pedido->detalles->filter(fn ($d) => ! $d->es_solicitud_custom && $d->insumoid && ! $d->insumo_presentacionid)
            ->groupBy(fn ($d) => $this->almacenDeLinea($d, $pedido).':'.$d->insumoid);
        foreach ($legadas as $lineas) {
            $detalle = $lineas->first();
            $origen = Insumo::with(['almacen', 'unidadMedida'])->findOrFail($detalle->insumoid);
            $existencias = app(InventarioExistenciaService::class);
            $resumen = $existencias->resumen($origen);
            $stock = BigDecimal::of($resumen['cantidad_fisica'])->minus($resumen['cantidad_vencida'])->minus($resumen['cantidad_bloqueada'])
                ->minus(InventarioDecimal::texto($existencias->reservado($origen, (int) $pedido->getKey())));
            $cantidad = BigDecimal::zero();
            foreach ($lineas as $linea) {
                $cantidad = $cantidad->plus((string) $linea->getRawOriginal('cantidad'));
            }
            if (! $resumen['saldo_coherente'] || $cantidad->isGreaterThan($stock)) {
                throw new InvalidArgumentException('Las líneas acumuladas superan las existencias sin reservar del producto.');
            }
        }

        // Mantener el error de dominio histórico antes de validar acumulados y vencimientos.
        app(PedidoEntradaService::class)->distribucion(request(), $pedido->detalles->filter(fn ($d) => !$d->es_solicitud_custom && $d->insumo_presentacionid)->map(fn ($d) => [
            'insumoid' => $d->insumoid, 'insumo_presentacionid' => $d->insumo_presentacionid,
            'inventario_presentacion_loteid' => $d->inventario_presentacion_loteid,
            'cantidad' => (string) $d->getRawOriginal('cantidad'), 'datos_solicitud' => $d->datos_solicitud,
        ])->all(), (int) $pedido->getKey(), false);
    }

    /** Stock de la línea menos lo ya reservado por OTROS pedidos confirmados del mismo almacén. */
    public function disponible(DetallePedidoDistribucion $detalle, int $almacenId, ?int $excluirPedidoId = null): float
    {
        $presentacionId = (int) ($detalle->insumo_presentacionid ?? 0);

        if ($presentacionId > 0) {
            $stock = $this->inventarioPresentacion->stockTotalUnidades($almacenId, $presentacionId);
        } else {
            $stock = (float) (Insumo::query()->whereKey($detalle->insumoid)->value('stock') ?? 0);
        }

        return $stock - $this->reservado($almacenId, (int) $detalle->insumoid, $presentacionId ?: null, $excluirPedidoId);
    }

    public function reservado(int $almacenId, int $insumoId, ?int $presentacionId, ?int $excluirPedidoId = null): float
    {
        return (float) DetallePedidoDistribucion::query()
            ->join('pedido_distribucion as p', 'p.pedidodistribucionid', '=', 'detalle_pedido_distribucion.pedidodistribucionid')
            ->where('p.estado', PedidoDistribucionCatalogo::ESTADO_CONFIRMADO)
            ->when($excluirPedidoId, fn ($q) => $q->where('p.pedidodistribucionid', '!=', $excluirPedidoId))
            ->where(function ($q) use ($almacenId) {
                $q->where('detalle_pedido_distribucion.almacen_mayorista_origenid', $almacenId)
                    ->orWhere(function ($sinLinea) use ($almacenId) {
                        $sinLinea->whereNull('detalle_pedido_distribucion.almacen_mayorista_origenid')
                            ->where('p.almacen_mayorista_origenid', $almacenId);
                    });
            })
            ->where('detalle_pedido_distribucion.insumoid', $insumoId)
            ->when(
                $presentacionId,
                fn ($q) => $q->where('detalle_pedido_distribucion.insumo_presentacionid', $presentacionId),
                fn ($q) => $q->whereNull('detalle_pedido_distribucion.insumo_presentacionid')
            )
            ->sum('detalle_pedido_distribucion.cantidad');
    }

    private function almacenDeLinea(DetallePedidoDistribucion $detalle, PedidoDistribucion $pedido): int
    {
        return (int) ($detalle->almacen_mayorista_origenid ?: $pedido->almacen_mayorista_origenid ?: 0);
    }
}
