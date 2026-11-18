<?php

namespace App\Services;

use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Insumo;
use App\Models\Pedido;
use App\Models\TipoMovimientoAlmacen;
use App\Models\UnidadMedida;
use App\Models\Usuario;
use App\Support\AlmacenAmbito;
use App\Support\EnvioAsignacionEstadoCatalogo;
use App\Support\InsumoCatalogo;
use App\Support\PlantaAccess;
use App\Support\UsuarioRol;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class RecepcionPlantaEnvioService
{
    public function confirmar(
        EnvioAsignacionMultiple $asignacion,
        Usuario $usuario,
        int $almacenid,
        int $insumoid,
        float $cantidad,
        ?string $observaciones = null
    ): void {
        $pedido = $asignacion->pedido;
        if (! $pedido || $pedido->detalles()->count() !== 1) {
            throw new \InvalidArgumentException('Use el pesaje por línea del pedido para confirmar esta recepción.');
        }
        $almacen = $this->resolverAlmacenPlantaDesdePedido($pedido);
        $insumo = Insumo::findOrFail($insumoid);
        $detalle = $pedido->detalles()->with('insumo')->firstOrFail();
        $producto = trim((string) ($detalle->cultivo_personalizado ?: $detalle->insumo?->nombre));
        if ((int) $almacen->getKey() !== $almacenid || (int) $insumo->almacenid !== $almacenid || $insumo->nombre !== $producto) {
            throw new \InvalidArgumentException('El producto y el almacén deben corresponder al destino del pedido.');
        }
        $this->confirmarDesdePedido($pedido, $usuario, [$detalle->getKey() => $cantidad]);
    }

    /**
     * Confirma recepción en planta con pesaje (JPL-08).
     *
     * @param  array<int, float>  $cantidadesRecibidas  mapa detallepedidoid => kg recibidos (obligatorio).
     *                                                  No hay path legacy sin pesaje: transportista/cierre/simulación no pueden acreditar stock.
     */
    public function confirmarDesdePedido(Pedido $pedido, Usuario $usuario, ?array $cantidadesRecibidas = null): void
    {
        if (! UsuarioRol::puedeConfirmarRecepcionPlanta($usuario)) {
            throw new \InvalidArgumentException('Solo el jefe de planta puede confirmar la recepción con pesaje.');
        }
        if (! $cantidadesRecibidas) {
            throw new \InvalidArgumentException('Debe indicar la cantidad recibida (pesaje) para cada producto.');
        }
        $cantidades = [];
        foreach ($cantidadesRecibidas as $id => $cantidad) {
            if (! ctype_digit((string) $id) || (int) $id < 1) {
                throw \Illuminate\Validation\ValidationException::withMessages(['cantidades' => 'Identifique las líneas del pedido.']);
            }
            $cantidades[(int) $id] = \App\Support\CosechaDecimal::cantidad($cantidad, 'cantidades.'.$id);
        }
        ksort($cantidades);
        $huella = hash('sha256', json_encode($cantidades, JSON_THROW_ON_ERROR));
        DB::transaction(function () use ($pedido, $usuario, $cantidades, $huella) {
            if (DB::getDriverName() === 'sqlite') {
                DB::table('pedido')->where('pedidoid', $pedido->pedidoid)->update(['estado' => DB::raw('estado')]);
            }
            $pedido = Pedido::whereKey($pedido->pedidoid)->lockForUpdate()->firstOrFail();
            $almacen = $this->resolverAlmacenPlantaDesdePedido($pedido);
            if (! PlantaAccess::puedeGestionarAlmacen($usuario, $almacen)) {
                throw new \InvalidArgumentException('No puede confirmar recepción en un almacén de otra planta.');
            }
            $almacen = Almacen::whereKey($almacen->almacenid)->lockForUpdate()->firstOrFail();
            if (! $almacen->activo || ! PlantaAccess::puedeGestionarAlmacen($usuario, $almacen)) {
                throw new \InvalidArgumentException('El almacén destino no está disponible para esta recepción.');
            }
            $asignacion = $pedido->envioAsignacion()->lockForUpdate()->first();
            if (! $asignacion) {
                throw new \InvalidArgumentException('El pedido no tiene envío registrado.');
            }
            if ($asignacion->fecha_recepcion_planta) {
                if (($asignacion->recepcion_planta_datos['huella'] ?? null) === $huella) {
                    return;
                }
                throw new \App\Exceptions\PlantaConflictoException('Este envío ya fue confirmado en planta con otro pesaje o sin comprobante verificable.');
            }
            if (! in_array($asignacion->estado, ['en_transporte_planta', 'en_ruta', 'en_transito'], true)) {
                throw new \InvalidArgumentException('El envío debe estar en transporte hacia planta para confirmar la recepción.');
            }
            $detalles = $pedido->detalles()->with(['insumo', 'cosechaAlmacen.produccion'])->orderBy('detallepedidoid')->lockForUpdate()->get();
            if ($detalles->isEmpty() || $detalles->pluck('detallepedidoid')->map(fn ($id) => (int) $id)->sort()->values()->all() !== array_keys($cantidades)) {
                throw \Illuminate\Validation\ValidationException::withMessages(['cantidades' => 'Indique exactamente una cantidad para cada línea de este pedido.']);
            }
            $tipo = $this->tipoMovimientoIngresoRecepcion();
            $kg = UnidadMedida::where('categoria', 'peso')->get()->first(fn ($u) => \App\Support\CosechaDecimal::factorUnidad($u) === '1');
            if (! $kg) {
                throw new \InvalidArgumentException('No está configurada la unidad de pesaje en kilogramos.');
            }
            $lineas = [];
            foreach ($detalles as $detalle) {
                $campo = 'cantidades.'.$detalle->detallepedidoid;
                $cantidad = $cantidades[$detalle->detallepedidoid];
                $enviada = \App\Support\CosechaDecimal::cantidad($detalle->getRawOriginal('cantidad'), $campo);
                if (\App\Support\InventarioDecimal::unidades($cantidad) > \App\Support\InventarioDecimal::unidades($enviada)) {
                    throw \Illuminate\Validation\ValidationException::withMessages([$campo => 'El pesaje recibido no puede superar la cantidad enviada.']);
                }
                // El origen ya se descontó al aceptar el pedido: no volver a consumirlo aquí.
                $origen = $this->origenDetalle($detalle, $pedido);
                $producto = trim((string) ($detalle->cultivo_personalizado ?: $detalle->insumo?->nombre ?: $detalle->cosechaAlmacen?->produccion?->lote?->cultivo?->nombre));
                if ($producto === '') {
                    throw \Illuminate\Validation\ValidationException::withMessages([$campo => 'La línea no tiene un producto de origen identificable.']);
                }
                // Coincidencia exacta y unidad kg: no fusionar productos por semejanza de nombre.
                $insumo = Insumo::where('almacenid', $almacen->almacenid)->where('nombre', $producto)
                    ->where('unidadmedidaid', $kg->unidadmedidaid)->orderBy('insumoid')->lockForUpdate()->first();
                if (! $insumo) {
                    $insumo = $this->crearInsumoRecepcionEnAlmacen($almacen, $producto, $pedido->numero_solicitud, $detalle->insumo);
                    $insumo->update(['unidadmedidaid' => $kg->unidadmedidaid]);
                }
                app(InventarioExistenciaService::class)->bloquear([(int) $insumo->insumoid]);
                $insumo->refresh();
                $antes = \App\Support\InventarioDecimal::unidades($insumo->getRawOriginal('stock'));
                $despues = $antes + \App\Support\InventarioDecimal::unidades($cantidad);
                $saldo = \App\Support\InventarioDecimal::texto($despues);
                \App\Support\InventarioDecimal::unidades($saldo);
                $partida = \App\Models\MateriaPrimaLote::create([
                    'insumoid' => $insumo->insumoid, 'almacenid' => $almacen->almacenid,
                    'detallepedidoid' => $detalle->detallepedidoid, 'lote_proveedor' => $asignacion->externo_envio_id,
                    'fecha_recepcion' => now()->toDateString(), 'fecha_vencimiento' => $origen['fecha_vencimiento'],
                    'cantidad' => $cantidad, 'cantidad_disponible' => $cantidad, 'conformidad_recepcion' => true,
                    'observaciones' => 'Recepción pedido '.$pedido->numero_solicitud.'; línea '.$detalle->detallepedidoid,
                ]);
                $obs = '[Recepción planta — '.$asignacion->externo_envio_id.'] '.$producto
                    .' · '.$this->textoRecepcionPedido($pedido->numero_solicitud)
                    .' · enviado '.\App\Support\CosechaDecimal::mostrar($enviada).' kg · recibido '.\App\Support\CosechaDecimal::mostrar($cantidad).' kg';
                if ($cantidad !== $enviada) {
                    $obs .= ' · discrepancia -'.\App\Support\CosechaDecimal::mostrar(\App\Support\InventarioDecimal::texto(\App\Support\InventarioDecimal::unidades($enviada) - \App\Support\InventarioDecimal::unidades($cantidad))).' kg';
                }
                $mov = AlmacenMovimiento::create([
                    'almacenid' => $almacen->almacenid, 'insumoid' => $insumo->insumoid,
                    'tipo_movimiento_almacenid' => $tipo->getKey(), 'usuarioid' => $usuario->usuarioid,
                    'fecha' => now()->toDateString(), 'cantidad' => $cantidad, 'unidadmedidaid' => $kg->unidadmedidaid,
                    'referencia' => $asignacion->externo_envio_id, 'destino_motivo' => $almacen->nombre,
                    'observaciones' => $obs, 'materiaprimaloteid' => $partida->getKey(),
                    'saldo_anterior' => \App\Support\InventarioDecimal::texto($antes), 'saldo_posterior' => $saldo,
                ]);
                $insumo->update(['stock' => $saldo]);
                $lineas[] = ['detallepedidoid' => (int) $detalle->getKey(), 'cantidad_enviada' => $enviada,
                    'cantidad_recibida' => $cantidad, 'unidadmedidaid' => (int) $kg->getKey(), 'unidad' => 'kg',
                    'materiaprimaloteid' => (int) $partida->getKey(), 'almacenmovimientoid' => (int) $mov->getKey(),
                    'insumoid' => (int) $insumo->getKey(), 'producto' => $producto, 'origen' => $origen];
            }
            $asignacion->update(EnvioAsignacionEstadoCatalogo::applyToAttributes([
                'estado' => 'recibido_planta', 'almacenid' => $almacen->almacenid,
                'fecha_recepcion_planta' => now(), 'recepcion_usuarioid' => $usuario->usuarioid,
                'recepcion_planta_datos' => ['huella' => $huella, 'lineas' => $lineas],
            ]));
        }, 5);
    }

    private function origenDetalle(\App\Models\DetallePedido $detalle, Pedido $pedido): array
    {
        $fecha = null;
        $materiaId = null;
        if ($detalle->insumoid) {
            $salidas = AlmacenMovimiento::where('insumoid', $detalle->insumoid)->where('referencia', $pedido->numero_solicitud)
                ->whereHas('tipo', fn ($q) => $q->where('naturaleza', 'salida'))->get();
            $ids = $salidas->pluck('materiaprimaloteid')->filter()->unique();
            if ($ids->count() > 1) {
                throw \Illuminate\Validation\ValidationException::withMessages(['cantidades.'.$detalle->getKey() => 'El origen contiene varias partidas sin distribución verificable por línea.']);
            }
            $materiaId = $ids->first();
            if ($materiaId) {
                $partida = \App\Models\MateriaPrimaLote::whereKey($materiaId)->lockForUpdate()->firstOrFail();
                if ((int) $partida->insumoid !== (int) $detalle->insumoid || ! app(InventarioExistenciaService::class)->utilizable($partida)) {
                    throw \Illuminate\Validation\ValidationException::withMessages(['cantidades.'.$detalle->getKey() => 'La partida de origen está vencida, bloqueada o no corresponde al producto.']);
                }
                $fecha = $partida->fecha_vencimiento?->toDateString();
            } elseif (\App\Models\MateriaPrimaLote::where('insumoid', $detalle->insumoid)->exists()
                || \App\Models\InventarioPresentacionLote::where('insumoid', $detalle->insumoid)->exists()) {
                throw \Illuminate\Validation\ValidationException::withMessages(['cantidades.'.$detalle->getKey() => 'Falta identificar la partida efectivamente despachada en el movimiento de origen.']);
            }
        }
        $cosecha = $detalle->cosechaAlmacen;

        return ['insumoid' => $detalle->insumoid, 'produccionalmacenamientoid' => $detalle->produccionalmacenamientoid,
            'produccionid' => $cosecha?->produccionid, 'loteid' => $cosecha?->produccion?->loteid,
            'materiaprimaloteid' => $materiaId, 'fecha_vencimiento' => $fecha];
    }

    public function puedeRecibirPedido(Pedido $pedido, Usuario $usuario): bool
    {
        if (! UsuarioRol::puedeConfirmarRecepcionPlanta($usuario)) {
            return false;
        }

        try {
            $almacen = $this->resolverAlmacenPlantaDesdePedido($pedido);
        } catch (\InvalidArgumentException) {
            return false;
        }

        return PlantaAccess::puedeGestionarAlmacen($usuario, $almacen);
    }

    public function resolverAlmacenPlantaDesdePedido(Pedido $pedido, ?\Illuminate\Support\Collection $almacenes = null): Almacen
    {
        $texto = (string) ($pedido->direccion_texto ?? '');
        $nombre = trim(explode('·', $texto)[0]);
        $nombre = trim(explode('GPS', $nombre)[0]);

        $almacenes ??= AlmacenAmbito::scope(
            Almacen::query()->where('activo', true), AlmacenAmbito::PLANTA
        )->get();

        if ($nombre === '') {
            throw new \InvalidArgumentException(
                'No se pudo determinar el almacén de planta destino del pedido. Indique un destino inequívoco.'
            );
        }

        $coincidencias = $almacenes->filter(fn ($a) => str_contains(mb_strtolower($a->nombre), mb_strtolower($nombre)));

        if ($coincidencias->count() === 1) {
            return $coincidencias->first();
        }

        if ($coincidencias->count() > 1) {
            throw new \InvalidArgumentException(
                'Hay varios almacenes de planta que coinciden con «'.$nombre.'». Especifique el destino exacto.'
            );
        }

        throw new \InvalidArgumentException(
            'No se encontró un almacén de planta destino para «'.$nombre.'».'
        );
    }

    private function crearInsumoRecepcionEnAlmacen(
        Almacen $almacen,
        string $nombreProducto,
        string $numeroSolicitud,
        ?Insumo $referencia = null
    ): Insumo {
        InsumoCatalogo::asegurarCatalogosBase();

        $tipoId = $referencia?->tipoinsumoid
            ?? InsumoCatalogo::tiposOrdenados()->firstWhere(
                fn ($t) => InsumoCatalogo::slugFromNombreTipo($t->nombre) === 'material_siembra'
            )?->tipoinsumoid
            ?? InsumoCatalogo::tiposOrdenados()->first()?->tipoinsumoid;

        $unidadId = $referencia?->unidadmedidaid
            ?? UnidadMedida::query()->where('nombre', 'Kilogramo')->value('unidadmedidaid')
            ?? UnidadMedida::query()->value('unidadmedidaid');

        return Insumo::query()->create([
            'nombre' => $nombreProducto,
            'tipoinsumoid' => (int) $tipoId,
            'unidadmedidaid' => (int) $unidadId,
            'stock' => 0,
            'stockminimo' => null,
            'almacenid' => $almacen->almacenid,
            'descripcion' => $this->textoRecepcionPedido($numeroSolicitud),
        ]);
    }

    private function textoRecepcionPedido(string $numeroSolicitud, ?\DateTimeInterface $fecha = null): string
    {
        $fecha = $fecha ?? now();

        return 'Recepción pedido '.$numeroSolicitud.' · '.$fecha->format('d/m/Y');
    }

    private function aplicarDetalleRecepcionPedido(Insumo $insumo, string $numeroSolicitud): void
    {
        if (! $this->debeActualizarDetalleRecepcionPedido($insumo)) {
            return;
        }

        $insumo->update([
            'descripcion' => $this->textoRecepcionPedido($numeroSolicitud),
        ]);
    }

    private function debeActualizarDetalleRecepcionPedido(Insumo $insumo): bool
    {
        $actual = trim((string) $insumo->descripcion);
        if ($actual === '') {
            return true;
        }

        $lower = Str::lower($actual);

        return Str::contains($lower, 'creado automáticamente')
            || Str::contains($lower, 'confirmar llegada de pedido');
    }

    /**
     * Corrige insumos que quedaron con el detalle automático anterior.
     */
    public function corregirDetallesRecepcionLegacy(): int
    {
        $actualizados = 0;

        Insumo::query()
            ->where(function ($query) {
                $query->where('descripcion', 'like', '%automáticamente%')
                    ->orWhere('descripcion', 'like', '%confirmar llegada%');
            })
            ->each(function (Insumo $insumo) use (&$actualizados) {
                $movimiento = AlmacenMovimiento::query()
                    ->where('insumoid', $insumo->insumoid)
                    ->where('observaciones', 'like', '%Recepción planta%')
                    ->orderByDesc('fecha')
                    ->first();

                if ($movimiento === null || $movimiento->referencia === null) {
                    return;
                }

                $asignacion = EnvioAsignacionMultiple::query()
                    ->where('externo_envio_id', $movimiento->referencia)
                    ->with('pedido')
                    ->first();

                $pedido = $asignacion?->pedido;
                if ($pedido === null) {
                    return;
                }

                $fecha = $asignacion->fecha_recepcion_planta ?? $movimiento->fecha;
                $insumo->update([
                    'descripcion' => $this->textoRecepcionPedido($pedido->numero_solicitud, $fecha),
                ]);
                $actualizados++;
            });

        return $actualizados;
    }

    /**
     * @return array{cantidad: float, producto: ?string}
     */
    public function sugerenciaDesdeEnvio(EnvioAsignacionMultiple $asignacion): array
    {
        $detalles = is_array($asignacion->detalles_productos) ? $asignacion->detalles_productos : [];
        $primero = $detalles[0] ?? [];

        $cantidad = (float) ($primero['cantidad'] ?? $primero['peso_kg'] ?? $primero['peso'] ?? 0);
        $producto = (string) ($primero['producto'] ?? $primero['nombre'] ?? $primero['cultivo'] ?? '');

        return [
            'cantidad' => $cantidad > 0 ? $cantidad : 0,
            'producto' => $producto !== '' ? $producto : null,
        ];
    }

    public function resolverInsumoEnAlmacen(Almacen $almacen, ?string $nombreProducto): ?Insumo
    {
        if ($nombreProducto === null || trim($nombreProducto) === '') {
            return null;
        }

        InsumoCatalogo::asegurarCatalogosBase();
        $needle = Str::lower(trim($nombreProducto));

        return Insumo::query()
            ->where('almacenid', $almacen->almacenid)
            ->whereIn('tipoinsumoid', InsumoCatalogo::tiposValidosIds())
            ->get()
            ->first(function (Insumo $insumo) use ($needle) {
                $nombre = Str::lower($insumo->nombre);

                return Str::contains($nombre, $needle) || Str::contains($needle, $nombre);
            });
    }

    private function tipoMovimientoIngresoRecepcion(): TipoMovimientoAlmacen
    {
        $tipo = TipoMovimientoAlmacen::query()
            ->where('naturaleza', 'ingreso')
            ->where('activo', true)
            ->get()
            ->first(fn (TipoMovimientoAlmacen $t) => in_array(
                TipoMovimientoAlmacen::normalizeNombre($t->nombre),
                ['produccion recibida', 'producción recibida', 'compra', 'ajuste positivo'],
                true
            ));

        return $tipo ?? TipoMovimientoAlmacen::activosPorNaturaleza('ingreso')->firstOrFail();
    }
}
