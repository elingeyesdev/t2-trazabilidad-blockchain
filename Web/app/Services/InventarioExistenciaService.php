<?php

namespace App\Services;

use App\Models\Almacen;
use App\Models\Insumo;
use App\Models\InventarioPresentacionLote;
use App\Models\MateriaPrimaLote;
use App\Support\InventarioDecimal as Decimal;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** insumo.stock es el saldo físico; las partidas desglosan ese saldo, nunca lo suman de nuevo. */
class InventarioExistenciaService
{
    public function seleccion(array $fila): array
    {
        if (! filled($fila['partida'] ?? null)) {
            return $fila;
        }
        if (isset($fila['materiaprimaloteid']) || isset($fila['inventario_presentacion_loteid'])) {
            throw ValidationException::withMessages(['partida' => 'Selecciona una sola partida.']);
        }
        if ((string) $fila['partida'] === '0') {
            $fila['materiaprimaloteid'] = 0;
        } elseif (preg_match('/^([mp]):([1-9][0-9]*)$/D', (string) $fila['partida'], $m)) {
            $fila[$m[1] === 'm' ? 'materiaprimaloteid' : 'inventario_presentacion_loteid'] = (int) $m[2];
        } else {
            throw ValidationException::withMessages(['partida' => 'Selecciona una partida válida.']);
        }
        unset($fila['partida']);

        return $fila;
    }

    public function estadoFecha(?string $fecha): string
    {
        if (! $fecha) {
            return 'sin_fecha_registrada';
        }
        $hoy = now(config('app.timezone'))->toDateString();
        if ($fecha < $hoy || ($fecha === $hoy && ! config('inventario.consumir_dia_vencimiento'))) {
            return 'vencido';
        }

        return $fecha <= now(config('app.timezone'))->addDays(config('inventario.dias_aviso_vencimiento'))->toDateString()
            ? 'proximo_a_vencer' : 'vigente';
    }

    public function utilizable(MateriaPrimaLote $partida): bool
    {
        return $partida->conformidad_recepcion !== false
            && $this->estadoFecha($partida->fecha_vencimiento?->toDateString()) !== 'vencido'
            && ($partida->fecha_vencimiento !== null || config('inventario.permitir_sin_fecha'));
    }

    /** Debe llamarse dentro de transacción: almacenes y luego productos en orden estable. */
    public function bloquear(array $ids): \Illuminate\Support\Collection
    {
        if (DB::transactionLevel() === 0) {
            throw new \LogicException('La protección de existencias requiere una transacción.');
        }
        if (DB::getDriverName() === 'sqlite') {
            // SQLite no implementa FOR UPDATE: adquirir su bloqueo de escritura ANTES de leer saldos.
            DB::table('insumo')->whereIn('insumoid', $ids)->update(['stock' => DB::raw('stock')]);
        }
        $almacenIds = Insumo::whereIn('insumoid', $ids)->whereNotNull('almacenid')->orderBy('almacenid')->pluck('almacenid')->unique();
        if (DB::getDriverName() !== 'sqlite') {
            Almacen::whereIn('almacenid', $almacenIds)->orderBy('almacenid')->lockForUpdate()->get();
        }

        return Insumo::whereIn('insumoid', $ids)->orderBy('insumoid')->lockForUpdate()->get()->keyBy('insumoid');
    }

    public function partidas(Insumo $insumo, bool $bloquear = false)
    {
        return MateriaPrimaLote::where('insumoid', $insumo->insumoid)->where('almacenid', $insumo->almacenid)
            ->orderBy('materiaprimaloteid')->when($bloquear, fn ($q) => $q->lockForUpdate())->get();
    }

    public function resumen(Insumo $insumo): array
    {
        $fisico = Decimal::unidades($insumo->getRawOriginal('stock'));
        $vencido = $bloqueado = $registrado = 0;
        $partidas = $this->partidas($insumo)->map(function ($p) use (&$vencido, &$bloqueado, &$registrado) {
            $cantidad = Decimal::unidades($p->getRawOriginal('cantidad_disponible'));
            $registrado += $cantidad;
            $estado = $this->estadoFecha($p->fecha_vencimiento?->toDateString());
            if ($estado === 'vencido') {
                $vencido += $cantidad;
            } elseif (! $this->utilizable($p)) {
                $bloqueado += $cantidad;
            }

            return ['materiaprimaloteid' => $p->materiaprimaloteid, 'inventario_presentacion_loteid' => null, 'referencia' => $p->lote_proveedor,
                'cantidad_fisica' => Decimal::texto($cantidad), 'fecha_recepcion' => $p->fecha_recepcion?->toDateString(),
                'fecha_vencimiento' => $p->fecha_vencimiento?->toDateString(), 'vencimiento_estado' => $estado,
                'utilizable' => $this->utilizable($p)];
        });
        foreach (InventarioPresentacionLote::where('insumoid', $insumo->insumoid)->where('almacenid', $insumo->almacenid)->get() as $p) {
            // El inventario por presentación ya registra kg y envases por separado.
            if (! in_array(mb_strtolower($insumo->unidadMedida?->abreviatura ?? ''), ['kg', 'kilogramo'], true)) {
                continue;
            }
            $cantidad = Decimal::unidades($p->getRawOriginal('cantidad_kg'));
            $registrado += $cantidad;
            $estado = $this->estadoFecha($p->fecha_vencimiento?->toDateString());
            if ($estado === 'vencido') {
                $vencido += $cantidad;
            } elseif ($p->fecha_vencimiento === null && ! config('inventario.permitir_sin_fecha')) {
                $bloqueado += $cantidad;
            }
            $partidas->push(['materiaprimaloteid' => null, 'inventario_presentacion_loteid' => $p->inventario_presentacion_loteid,
                'referencia' => $p->referencia_lote, 'cantidad_fisica' => Decimal::texto($cantidad),
                'cantidad_unidades' => $p->cantidad_unidades, 'fecha_recepcion' => null,
                'fecha_vencimiento' => $p->fecha_vencimiento?->toDateString(), 'vencimiento_estado' => $estado,
                'utilizable' => $estado !== 'vencido' && ($p->fecha_vencimiento !== null || config('inventario.permitir_sin_fecha'))]);
        }
        $sinPartida = max(0, $fisico - $registrado);
        if (! config('inventario.permitir_sin_fecha')) {
            $bloqueado += $sinPartida;
        }
        $reservado = $this->reservado($insumo);
        $coherente = $registrado <= $fisico;
        $disponible = $coherente ? max(0, $fisico - $vencido - $bloqueado - $reservado) : 0;
        $minimo = $insumo->getRawOriginal('stockminimo');

        return ['cantidad_fisica' => Decimal::texto($fisico), 'cantidad_disponible' => Decimal::texto($disponible),
            'cantidad_vencida' => Decimal::texto($vencido), 'cantidad_bloqueada' => Decimal::texto($bloqueado),
            'cantidad_reservada' => Decimal::texto($reservado), 'cantidad_sin_partida' => Decimal::texto($sinPartida),
            'minimo' => $minimo === null ? null : Decimal::texto(Decimal::unidades($minimo)),
            'existencias_bajas' => $minimo !== null && $disponible <= Decimal::unidades($minimo),
            'saldo_coherente' => $coherente, 'partidas' => $partidas->all(),
            'presentaciones' => $insumo->presentaciones()->where('activo', true)->orderBy('nombre')->get(['insumo_presentacionid', 'nombre'])->toArray()];
    }

    /** Reserva comercial existente: cantidades sin presentación en unidad del insumo. */
    public function reservado(Insumo $insumo, ?int $excluirPedidoId = null): int
    {
        if (! $insumo->almacenid || ($insumo->almacen?->ambito ?? '') !== 'mayorista') {
            return 0;
        }
        $filas = \App\Models\DetallePedidoDistribucion::query()->join('pedido_distribucion as p', 'p.pedidodistribucionid', '=', 'detalle_pedido_distribucion.pedidodistribucionid')
            ->where('p.estado', \App\Support\PedidoDistribucionCatalogo::ESTADO_CONFIRMADO)
            ->when($excluirPedidoId !== null, fn ($q) => $q->where('p.pedidodistribucionid', '!=', $excluirPedidoId))
            ->where('detalle_pedido_distribucion.insumoid', $insumo->insumoid)
            ->whereRaw('COALESCE(detalle_pedido_distribucion.almacen_mayorista_origenid, p.almacen_mayorista_origenid) = ?', [$insumo->almacenid])
            ->get(['detalle_pedido_distribucion.cantidad', 'detalle_pedido_distribucion.insumo_presentacionid']);
        $total = 0;
        foreach ($filas as $fila) {
            if ($fila->insumo_presentacionid) {
                // Estas líneas reservan envases, no kg. Usar su inventario real proporcional,
                // sin sumar envases a unidades incompatibles ni inventar un factor histórico.
                $inventarios = \App\Models\InventarioPresentacionLote::where('almacenid', $insumo->almacenid)
                    ->where('insumoid', $insumo->insumoid)->where('insumo_presentacionid', $fila->insumo_presentacionid)->get();
                $unidades = $kg = \Brick\Math\BigDecimal::zero();
                foreach ($inventarios as $inventario) {
                    $unidades = $unidades->plus((string) $inventario->getRawOriginal('cantidad_unidades'));
                    $kg = $kg->plus((string) $inventario->getRawOriginal('cantidad_kg'));
                }
                if ($unidades->isPositive() && in_array(mb_strtolower($insumo->unidadMedida?->abreviatura ?? ''), ['kg', 'kilogramo'], true)) {
                    $total += Decimal::unidades((string) $kg->multipliedBy((string) $fila->getRawOriginal('cantidad'))->dividedBy($unidades, 6, \Brick\Math\RoundingMode::CEILING));
                } else {
                    // Sin equivalencia verificable, impedir ajustes que comprometan la reserva.
                    return Decimal::unidades($insumo->getRawOriginal('stock'));
                }
            } else {
                $total += Decimal::unidades($fila->getRawOriginal('cantidad'));
            }
        }

        return $total;
    }

    public function descontar(Insumo $insumo, string|int|float $cantidad, ?int $partidaId = null, bool $retiro = false, ?int $excluirPedidoId = null, ?int $presentacionLoteId = null, ?string $unidades = null): void
    {
        $delta = Decimal::unidades($cantidad);
        if ($delta <= 0) {
            throw ValidationException::withMessages(['cantidad' => 'Indica una cantidad mayor a cero.']);
        }
        DB::transaction(function () use ($insumo, $delta, $partidaId, $retiro, $excluirPedidoId, $presentacionLoteId, $unidades) {
            $actual = $this->bloquear([$insumo->insumoid])->get($insumo->insumoid);
            abort_unless($actual, 404);
            $saldo = Decimal::unidades($actual->getRawOriginal('stock'));
            $partidas = $this->partidas($actual, true);
            $registrado = $partidas->sum(fn ($p) => Decimal::unidades($p->getRawOriginal('cantidad_disponible')));
            $presentaciones = InventarioPresentacionLote::where('insumoid', $actual->insumoid)->where('almacenid', $actual->almacenid)
                ->orderBy('inventario_presentacion_loteid')->lockForUpdate()->get();
            $registrado += $presentaciones->sum(fn ($p) => Decimal::unidades($p->getRawOriginal('cantidad_kg')));
            if ($presentacionLoteId) {
                $presentacion = $presentaciones->firstWhere('inventario_presentacion_loteid', $presentacionLoteId);
                if (! $presentacion || $partidaId !== null) {
                    throw ValidationException::withMessages(['inventario_presentacion_loteid' => 'Selecciona una sola partida del mismo producto y almacén.']);
                }
                if (! in_array(mb_strtolower($actual->unidadMedida?->abreviatura ?? ''), ['kg', 'kilogramo'], true)) {
                    throw ValidationException::withMessages(['unidadmedidaid' => 'La existencia por presentación debe estar expresada en kilogramos.']);
                }
                if (! $retiro && ($this->estadoFecha($presentacion->fecha_vencimiento?->toDateString()) === 'vencido'
                    || ($presentacion->fecha_vencimiento === null && ! config('inventario.permitir_sin_fecha')))) {
                    throw ValidationException::withMessages(['inventario_presentacion_loteid' => 'La partida de presentación está vencida.']);
                }
                $kgPartida = Decimal::unidades($presentacion->getRawOriginal('cantidad_kg'));
                $unidadesPartida = Decimal::unidades($presentacion->getRawOriginal('cantidad_unidades'));
                if ($kgPartida <= 0 || $unidadesPartida <= 0) {
                    throw ValidationException::withMessages(['cantidad' => 'La partida seleccionada no tiene existencia.']);
                }
                try {
                    if ($unidades !== null) {
                        $unidadesRetirar = Decimal::unidades($unidades);
                        $delta = (int) \Brick\Math\BigDecimal::of($kgPartida)->multipliedBy($unidadesRetirar)->dividedBy($unidadesPartida, 0, \Brick\Math\RoundingMode::HALF_UP)->__toString();
                    } else {
                        $unidadesRetirar = (int) \Brick\Math\BigDecimal::of($delta)->multipliedBy($unidadesPartida)->dividedBy($kgPartida, 0, \Brick\Math\RoundingMode::UNNECESSARY)->__toString();
                    }
                } catch (\Brick\Math\Exception\RoundingNecessaryException) {
                    throw ValidationException::withMessages(['cantidad' => 'La cantidad no corresponde a unidades representables de esta partida.']);
                }
                if ($delta <= 0 || $delta > $kgPartida || $unidadesRetirar <= 0 || $unidadesRetirar > $unidadesPartida) {
                    throw ValidationException::withMessages(['cantidad' => 'Stock insuficiente en la presentación seleccionada.']);
                }
                $presentacion->update(['cantidad_kg' => Decimal::texto($kgPartida - $delta), 'cantidad_unidades' => Decimal::texto($unidadesPartida - $unidadesRetirar)]);
            }
            if ($registrado > $saldo) {
                throw ValidationException::withMessages(['cantidad' => 'El desglose de partidas no coincide con el saldo físico. Revise el inventario.']);
            }
            if ($saldo < $delta || $saldo - $delta < $this->reservado($actual, $excluirPedidoId)) {
                throw ValidationException::withMessages(['cantidad' => 'Stock insuficiente o comprometido por reservas.']);
            }
            if ($partidaId === null && ! $presentacionLoteId && $registrado > 0) {
                throw ValidationException::withMessages(['materiaprimaloteid' => 'Selecciona la partida que realmente se utiliza; no se elige automáticamente.']);
            }
            if ($partidaId) {
                $partida = $partidas->firstWhere('materiaprimaloteid', $partidaId);
                if (! $partida) {
                    throw ValidationException::withMessages(['materiaprimaloteid' => 'La partida no pertenece a este producto y almacén.']);
                }
                if (! $retiro && ! $this->utilizable($partida)) {
                    throw ValidationException::withMessages(['materiaprimaloteid' => 'La partida está vencida o bloqueada y no puede utilizarse.']);
                }
                $disponible = Decimal::unidades($partida->getRawOriginal('cantidad_disponible'));
                if ($disponible < $delta) {
                    throw ValidationException::withMessages(['cantidad' => 'Stock insuficiente en la partida seleccionada.']);
                }
                $partida->update(['cantidad_disponible' => Decimal::texto($disponible - $delta)]);
            } elseif (! $presentacionLoteId && ($saldo - $registrado < $delta || (! $retiro && ! config('inventario.permitir_sin_fecha')))) {
                throw ValidationException::withMessages(['cantidad' => 'Cantidad insuficiente utilizable sin partida registrada.']);
            }
            $actual->update(['stock' => Decimal::texto($saldo - $delta)]);
            $insumo->refresh();
        }, 5);
    }
}
