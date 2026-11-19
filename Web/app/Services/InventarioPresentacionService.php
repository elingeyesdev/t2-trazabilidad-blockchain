<?php

namespace App\Services;

use App\Models\Insumo;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use InvalidArgumentException;

class InventarioPresentacionService
{
    /** @return Collection<int, InventarioPresentacionLote> */
    public function lotesDisponibles(int $almacenId, int $presentacionId): Collection
    {
        return InventarioPresentacionLote::query()
            ->with(['presentacion.tipoEmpaque', 'loteProduccion'])
            ->where('almacenid', $almacenId)
            ->where('insumo_presentacionid', $presentacionId)
            ->where('cantidad_unidades', '>', 0)
            ->where(fn ($q) => $q->whereNull('fecha_vencimiento')->orWhere('fecha_vencimiento', '>=', now(config('app.timezone'))->toDateString()))
            ->orderBy('referencia_lote')
            ->orderBy('inventario_presentacion_loteid')
            ->get();
    }

    public function stockTotalUnidades(int $almacenId, int $presentacionId): float
    {
        return (float) InventarioPresentacionLote::query()
            ->where('almacenid', $almacenId)
            ->where('insumo_presentacionid', $presentacionId)
            ->sum('cantidad_unidades');
    }

    public function stockTotalKg(int $almacenId, int $presentacionId): float
    {
        return (float) InventarioPresentacionLote::query()
            ->where('almacenid', $almacenId)
            ->where('insumo_presentacionid', $presentacionId)
            ->sum('cantidad_kg');
    }

    public function obtenerLote(int $inventarioId, int $almacenId, int $presentacionId): InventarioPresentacionLote
    {
        $lote = InventarioPresentacionLote::query()
            ->with('presentacion')
            ->where('inventario_presentacion_loteid', $inventarioId)
            ->where('almacenid', $almacenId)
            ->where('insumo_presentacionid', $presentacionId)
            ->first();

        if ($lote === null) {
            throw new InvalidArgumentException('El lote de inventario seleccionado no es válido.');
        }

        return $lote;
    }

    public function validarDisponibilidad(InventarioPresentacionLote $inventario, float $unidades, float $kg): void
    {
        if (app(InventarioExistenciaService::class)->estadoFecha($inventario->fecha_vencimiento?->toDateString()) === 'vencido') {
            throw new InvalidArgumentException('La partida de inventario está vencida.');
        }
        if ($unidades <= 0) {
            throw new InvalidArgumentException('La cantidad en unidades debe ser mayor a cero.');
        }

        if (! $inventario->tieneStockSuficiente($unidades)) {
            $etiqueta = $inventario->presentacion?->nombre ?? 'presentación';
            throw new InvalidArgumentException(
                'Stock insuficiente en lote «'.$inventario->etiquetaLote().'» para «'.$etiqueta.'»: '
                .'solicitado '.number_format($unidades, 0).' unidades, '
                .'disponible '.number_format((float) $inventario->cantidad_unidades, 0).' unidades.'
            );
        }

        $stockUnidades = (float) $inventario->cantidad_unidades;
        if ($unidades >= $stockUnidades - 0.0001) {
            return;
        }

        if ($kg > (float) $inventario->cantidad_kg + 0.0001) {
            throw new InvalidArgumentException(
                'Stock insuficiente en kg para el lote «'.$inventario->etiquetaLote().'».'
            );
        }
    }

    public function descontar(InventarioPresentacionLote $inventario, float|string $unidades, float $kg, ?int $excluirPedidoId = null): void
    {
        DB::transaction(function () use ($inventario, $unidades, $excluirPedidoId) {
            $existencias = app(InventarioExistenciaService::class);
            $insumo = $existencias->bloquear([(int) $inventario->insumoid])->get($inventario->insumoid);
            if (! $insumo) { throw new InvalidArgumentException('El producto ya no existe.'); }
            // Kg derivados de las cantidades históricas de la partida; no del catálogo actual.
            $insumo->decrementarStock('0.000001', null, false, $excluirPedidoId,
                (int) $inventario->inventario_presentacion_loteid, (string) $unidades);
            $inventario->refresh();
        }, 5);
    }

    public function descontarFifo(int $almacenId, int $presentacionId, float|string $unidades, float $kg, ?int $excluirPedidoId = null): void
    {
        DB::transaction(function () use ($almacenId, $presentacionId, $unidades, $excluirPedidoId) {
            if (DB::getDriverName() === 'sqlite') {
                DB::table('inventario_presentacion_lote')->where('almacenid', $almacenId)->where('insumo_presentacionid', $presentacionId)->update(['cantidad_kg' => DB::raw('cantidad_kg')]);
            }
            $presentacion = InsumoPresentacion::findOrFail($presentacionId);
            app(InventarioExistenciaService::class)->bloquear([(int) $presentacion->insumoid]);
            $restante = \App\Support\InventarioDecimal::unidades($unidades);
            if ($restante <= 0) { throw new InvalidArgumentException('La cantidad debe ser mayor a cero.'); }
            $lotes = InventarioPresentacionLote::where('almacenid', $almacenId)->where('insumo_presentacionid', $presentacionId)
                ->where('insumoid', $presentacion->insumoid)->orderBy('referencia_lote')->orderBy('inventario_presentacion_loteid')->lockForUpdate()->get();
            if ($lotes->contains(fn ($lote) => $lote->fecha_vencimiento !== null && \App\Support\InventarioDecimal::unidades($lote->getRawOriginal('cantidad_unidades')) > 0)) {
                throw new InvalidArgumentException('Selecciona una partida para conservar su fecha de vencimiento en la salida.');
            }
            if ($lotes->sum(fn ($lote) => \App\Support\InventarioDecimal::unidades($lote->getRawOriginal('cantidad_unidades'))) < $restante) {
                throw new InvalidArgumentException('Stock insuficiente en lotes para completar el descuento.');
            }
            foreach ($lotes as $lote) {
                if ($restante === 0) { break; }
                $tomar = min($restante, \App\Support\InventarioDecimal::unidades($lote->getRawOriginal('cantidad_unidades')));
                if ($tomar > 0) { $this->descontar($lote, \App\Support\InventarioDecimal::texto($tomar), 0, $excluirPedidoId); }
                $restante -= $tomar;
            }
        }, 5);
    }

    public function ingresar(
        int $almacenId,
        int $insumoId,
        int $presentacionId,
        ?int $loteProduccionId,
        ?string $referenciaLote,
        float|string $unidades,
        float|string $kg,
        ?string $fechaVencimiento = null
    ): InventarioPresentacionLote {
        return DB::transaction(function () use ($almacenId, $insumoId, $presentacionId, $loteProduccionId, $referenciaLote, $unidades, $kg, $fechaVencimiento) {
            $insumo = app(InventarioExistenciaService::class)->bloquear([$insumoId])->get($insumoId);
            if (! $insumo || (int) $insumo->almacenid !== $almacenId || ! InsumoPresentacion::where('insumoid', $insumoId)->whereKey($presentacionId)->exists()) {
                throw new InvalidArgumentException('La presentación no pertenece al producto y almacén.');
            }
        if ($unidades <= 0 || $kg <= 0) {
            throw new InvalidArgumentException('Las cantidades de ingreso deben ser mayores a cero.');
        }

        $query = InventarioPresentacionLote::query()
            ->where('almacenid', $almacenId)
            ->where('insumo_presentacionid', $presentacionId)->where('insumoid', $insumoId)->where('fecha_vencimiento', $fechaVencimiento);

        if ($loteProduccionId !== null) {
            $query->where('loteproduccionpedidoid', $loteProduccionId);
        } elseif ($referenciaLote !== null && $referenciaLote !== '') {
            $query->where('referencia_lote', $referenciaLote)->whereNull('loteproduccionpedidoid');
        } else {
            $query->whereNull('loteproduccionpedidoid')->whereNull('referencia_lote');
        }

        $existente = $query->lockForUpdate()->first();

        if ($existente !== null) {
            $existente->update([
                'cantidad_unidades' => \App\Support\InventarioDecimal::texto(\App\Support\InventarioDecimal::unidades($existente->getRawOriginal('cantidad_unidades')) + \App\Support\InventarioDecimal::unidades($unidades)),
                'cantidad_kg' => \App\Support\InventarioDecimal::texto(\App\Support\InventarioDecimal::unidades($existente->getRawOriginal('cantidad_kg')) + \App\Support\InventarioDecimal::unidades($kg)),
            ]);
            $this->sincronizarStockAgregadoInsumo($insumoId);

            return $existente->fresh();
        }

        $inventario = InventarioPresentacionLote::create([
            'almacenid' => $almacenId,
            'insumoid' => $insumoId,
            'insumo_presentacionid' => $presentacionId,
            'loteproduccionpedidoid' => $loteProduccionId,
            'referencia_lote' => $referenciaLote,
            'fecha_vencimiento' => $fechaVencimiento,
            'cantidad_unidades' => $unidades,
            'cantidad_kg' => $kg,
        ]);

        $this->sincronizarStockAgregadoInsumo($insumoId);

        return $inventario;
        }, 5);
    }

    public function sincronizarStockAgregadoInsumo(int $insumoId): void
    {
        $insumo = Insumo::query()->find($insumoId);
        if ($insumo === null || ! $insumo->almacenid) {
            return;
        }

        $totalKg = \Brick\Math\BigDecimal::zero();
        foreach (InventarioPresentacionLote::where('insumoid', $insumoId)->where('almacenid', $insumo->almacenid)->get() as $partida) {
            $totalKg = $totalKg->plus((string) $partida->getRawOriginal('cantidad_kg'));
        }
        if ($totalKg->isPositive()) {
            $insumo->update(['stock' => (string) $totalKg->toScale(6)]);
            return;
        }

        $presentacionesActivas = InsumoPresentacion::query()
            ->where('insumoid', $insumoId)
            ->where('activo', true)
            ->exists();

        if ($presentacionesActivas) {
            $insumo->update(['stock' => 0]);
        }
    }

    /**
     * Si hay presentaciones activas pero sin filas de inventario, reparte el stock agregado del insumo.
     */
    public function asegurarInventarioDesdeStock(int $almacenId, int $insumoId): void
    {
        if (! Schema::hasTable('inventario_presentacion_lote')) {
            return;
        }

        $insumo = Insumo::query()->find($insumoId);
        if ($insumo === null || (int) $insumo->almacenid !== $almacenId || (float) $insumo->stock <= 0) {
            return;
        }

        $presentaciones = InsumoPresentacion::query()
            ->where('insumoid', $insumoId)
            ->where('activo', true)
            ->orderBy('orden')
            ->orderBy('nombre')
            ->get();

        if ($presentaciones->isEmpty()) {
            return;
        }

        $tieneInventario = InventarioPresentacionLote::query()
            ->where('almacenid', $almacenId)
            ->where('insumoid', $insumoId)
            ->where('cantidad_unidades', '>', 0)
            ->where(fn ($q) => $q->whereNull('fecha_vencimiento')->orWhere('fecha_vencimiento', '>=', now(config('app.timezone'))->toDateString()))
            ->exists();

        if ($tieneInventario) {
            return;
        }

        $shareKg = (float) $insumo->stock / $presentaciones->count();
        $distribucion = [];

        foreach ($presentaciones->values() as $idx => $presentacion) {
            $unidades = (int) floor($shareKg / $presentacion->pesoNetoKg());
            if ($unidades <= 0) {
                continue;
            }
            $distribucion[] = [
                'presentacion' => $presentacion,
                'unidades' => (float) $unidades,
                'referencia_lote' => 'AUTO-'.str_pad((string) ($idx + 1), 2, '0', STR_PAD_LEFT),
                'partes' => 2,
            ];
        }

        if ($distribucion === []) {
            return;
        }

        $this->bootstrapDesdeStockAgregado($almacenId, $insumo, $distribucion);
    }

    /**
     * Reparte el stock agregado del insumo en filas de inventario por presentación (demo / bootstrap).
     *
     * @param  list<array{presentacion: InsumoPresentacion, unidades: float}>  $distribucion
     */
    public function bootstrapDesdeStockAgregado(int $almacenId, Insumo $insumo, array $distribucion): void
    {
        DB::transaction(function () use ($almacenId, $insumo, $distribucion) {
            InventarioPresentacionLote::query()
                ->where('almacenid', $almacenId)
                ->where('insumoid', $insumo->insumoid)
                ->delete();

            foreach ($distribucion as $item) {
                /** @var InsumoPresentacion $presentacion */
                $presentacion = $item['presentacion'];
                $unidades = (float) $item['unidades'];
                if ($unidades <= 0) {
                    continue;
                }

                $kg = round($unidades * $presentacion->pesoNetoKg(), 4);
                $referencia = $item['referencia_lote'] ?? null;
                $partes = $item['partes'] ?? 1;

                if ($partes > 1 && $unidades >= $partes) {
                    $base = (int) floor($unidades / $partes);
                    $resto = (int) round($unidades - ($base * $partes));
                    for ($i = 0; $i < $partes; $i++) {
                        $u = $base + ($i === $partes - 1 ? $resto : 0);
                        if ($u <= 0) {
                            continue;
                        }
                        $this->ingresar(
                            $almacenId,
                            (int) $insumo->insumoid,
                            (int) $presentacion->insumo_presentacionid,
                            null,
                            $referencia ? $referencia.'-'.chr(65 + $i) : 'LOTE-'.($i + 1),
                            (float) $u,
                            round($u * $presentacion->pesoNetoKg(), 4)
                        );
                    }

                    continue;
                }

                $this->ingresar(
                    $almacenId,
                    (int) $insumo->insumoid,
                    (int) $presentacion->insumo_presentacionid,
                    null,
                    $referencia,
                    $unidades,
                    $kg
                );
            }

            $this->sincronizarStockAgregadoInsumo((int) $insumo->insumoid);
        });
    }

    public function replicarPresentacionEnInsumo(InsumoPresentacion $origen, Insumo $insumoDestino): InsumoPresentacion
    {
        return InsumoPresentacion::query()->updateOrCreate(
            [
                'insumoid' => $insumoDestino->insumoid,
                'nombre' => $origen->nombre,
            ],
            [
                'tipoempaqueid' => $origen->tipoempaqueid,
                'tipo_envase' => $origen->tipo_envase,
                'peso_neto_kg' => $origen->peso_neto_kg,
                'unidades_por_caja' => $origen->unidades_por_caja,
                'sku' => $origen->sku,
                'codigo_barras' => $origen->codigo_barras,
                'orden' => $origen->orden,
                'activo' => true,
            ]
        );
    }
}
