<?php

namespace App\Services;

use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\Insumo;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\MateriaPrimaLote;
use App\Models\TipoMovimientoAlmacen;
use App\Models\Usuario;
use App\Support\AlmacenAcceso;
use App\Support\InventarioDecimal as Decimal;
use App\Support\UsuarioRol;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

class InventarioMovimientoService
{
    public function __construct(private readonly InventarioExistenciaService $existencias) {}

    public function validar(array $datos): array
    {
        Validator::make($datos, ['partida' => 'nullable|string|max:40'])->validate();
        if (filled($datos['partida'] ?? null)) {
            if (isset($datos['materiaprimaloteid']) || isset($datos['inventario_presentacion_loteid'])) {
                throw ValidationException::withMessages(['partida' => 'Selecciona una sola partida.']);
            }
            if ($datos['partida'] === '0') {
                $datos['materiaprimaloteid'] = 0;
            } elseif (preg_match('/^([mp]):([1-9][0-9]*)$/D', (string) $datos['partida'], $m)) {
                $datos[$m[1] === 'm' ? 'materiaprimaloteid' : 'inventario_presentacion_loteid'] = (int) $m[2];
            } else {
                throw ValidationException::withMessages(['partida' => 'Selecciona una partida válida.']);
            }
        }

        return Validator::make($datos, [
            'almacenid' => 'required|integer', 'insumoid' => 'required|integer',
            'tipo_movimiento_almacenid' => 'required|integer',
            'fecha' => 'required|date_format:Y-m-d|before_or_equal:today',
            'cantidad' => ['required', 'regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/D'],
            'referencia' => 'nullable|string|max:100', 'destino_motivo' => 'nullable|string|max:150',
            'observaciones' => 'nullable|string|max:1000', 'materiaprimaloteid' => 'nullable|integer|min:0',
            'inventario_presentacion_loteid' => 'nullable|integer|min:1', 'insumo_presentacionid' => 'nullable|integer|min:1',
            'cantidad_unidades' => ['nullable', 'regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/D'],
            'lote_proveedor' => 'nullable|string|max:100', 'fecha_vencimiento' => 'nullable|date_format:Y-m-d',
            'usuarioid' => 'missing', 'responsable' => 'missing', 'stock' => 'missing',
            'saldo_anterior' => 'missing', 'saldo_posterior' => 'missing', 'unidadmedidaid' => 'missing',
        ], ['cantidad.regex' => 'Indica una cantidad positiva con hasta seis decimales y punto decimal.',
            'fecha.before_or_equal' => 'La fecha del movimiento no puede ser futura.',
            'missing' => 'El campo :attribute se determina en el servidor.'])->validate();
    }

    public function registrar(Usuario $usuario, array $entrada, string $naturaleza): AlmacenMovimiento
    {
        abort_unless(in_array($naturaleza, ['ingreso', 'salida'], true), 404);
        Validator::make($entrada, ['almacenid' => 'required|integer'])->validate();
        $almacen = Almacen::query()->findOrFail($entrada['almacenid'] ?? 0);
        AlmacenAcceso::asegurarPuedeGestionar($usuario, $almacen);
        abort_if(UsuarioRol::debeAcotarPorAsignacion($usuario) || UsuarioRol::esOperarioPlanta($usuario), 403);
        $ajustePdv = ($almacen->ambito ?? '') === 'punto_venta' && $usuario->can('punto_venta.ajuste_stock');
        abort_unless($ajustePdv || $usuario->can($naturaleza === 'ingreso' ? 'almacen.ingresos.create' : 'almacen.salidas.create'), 403);
        $datos = $this->validar($entrada);

        return DB::transaction(function () use ($usuario, $datos, $naturaleza, $almacen, $ajustePdv) {
            $insumo = $this->existencias->bloquear([$datos['insumoid']])->get($datos['insumoid']);
            abort_unless($insumo && (int) $insumo->almacenid === (int) $almacen->almacenid, 404);
            $tipo = TipoMovimientoAlmacen::where('activo', true)->where('naturaleza', $naturaleza)
                ->lockForUpdate()->findOrFail($datos['tipo_movimiento_almacenid']);
            $ajuste = str_contains(TipoMovimientoAlmacen::normalizeNombre($tipo->nombre), 'ajuste');
            if ($ajustePdv) {
                abort_unless($ajuste, 403);
            }
            $retiro = $ajuste || TipoMovimientoAlmacen::normalizeNombre($tipo->nombre) === 'merma';
            if ($ajuste && blank($datos['destino_motivo'] ?? null)) {
                throw ValidationException::withMessages(['destino_motivo' => 'Describe el motivo obligatorio del ajuste.']);
            }
            $cantidad = Decimal::unidades($datos['cantidad']);
            if ($cantidad === 0) {
                throw ValidationException::withMessages(['cantidad' => 'La cantidad debe ser mayor a cero.']);
            }
            $anterior = Decimal::unidades($insumo->getRawOriginal('stock'));
            $partidaId = $datos['materiaprimaloteid'] ?? null;
            $presentacionLoteId = $datos['inventario_presentacion_loteid'] ?? null;
            if ($naturaleza === 'salida') {
                if (filled($datos['fecha_vencimiento'] ?? null) || filled($datos['lote_proveedor'] ?? null)) {
                    throw ValidationException::withMessages(['fecha_vencimiento' => 'Una salida no modifica los datos de la partida.']);
                }
                $insumo->decrementarStock(Decimal::texto($cantidad), $partidaId, $retiro, null, $presentacionLoteId);
            } else {
                app(AlmacenCapacidadService::class)->validarIngresoKg($almacen,
                    app(AlmacenCapacidadService::class)->convertirAKg((float) Decimal::texto($cantidad), $insumo->unidadMedida));
                if ($anterior > 999999999999999999 - $cantidad) {
                    throw ValidationException::withMessages(['cantidad' => 'La cantidad supera la capacidad decimal del saldo.']);
                }
                if ($presentacionLoteId || isset($datos['insumo_presentacionid'])) {
                    if ($partidaId !== null || ! in_array(mb_strtolower($insumo->unidadMedida?->abreviatura ?? ''), ['kg', 'kilogramo'], true)) {
                        throw ValidationException::withMessages(['partida' => 'La presentación utiliza kg y no puede combinarse con otra partida.']);
                    }
                    if ($ajuste && (filled($datos['fecha_vencimiento'] ?? null) || filled($datos['lote_proveedor'] ?? null))) {
                        throw ValidationException::withMessages(['fecha_vencimiento' => 'Un ajuste conserva la fecha de la partida.']);
                    }
                    $unidades = isset($datos['cantidad_unidades']) ? Decimal::unidades($datos['cantidad_unidades']) : 0;
                    if ($unidades <= 0) {
                        throw ValidationException::withMessages(['cantidad_unidades' => 'Indica las unidades físicas de presentación, además de los kg.']);
                    }
                    if ($ajuste) {
                        $inventario = InventarioPresentacionLote::where('insumoid', $insumo->insumoid)->where('almacenid', $almacen->almacenid)->lockForUpdate()->findOrFail($presentacionLoteId);
                        if (Decimal::unidades($inventario->getRawOriginal('cantidad_unidades')) > 999999999999999999 - $unidades) {
                            throw ValidationException::withMessages(['cantidad_unidades' => 'La cantidad de envases supera la precisión admitida.']);
                        }
                        $inventario->update(['cantidad_kg' => Decimal::texto(Decimal::unidades($inventario->getRawOriginal('cantidad_kg')) + $cantidad),
                            'cantidad_unidades' => Decimal::texto(Decimal::unidades($inventario->getRawOriginal('cantidad_unidades')) + $unidades)]);
                    } else {
                        if ($presentacionLoteId) {
                            throw ValidationException::withMessages(['partida' => 'Un ingreso crea una partida nueva.']);
                        }
                        $presentacion = InsumoPresentacion::where('insumoid', $insumo->insumoid)->where('activo', true)->findOrFail($datos['insumo_presentacionid']);
                        $inventario = InventarioPresentacionLote::create(['almacenid' => $almacen->almacenid, 'insumoid' => $insumo->insumoid,
                            'insumo_presentacionid' => $presentacion->insumo_presentacionid, 'referencia_lote' => $datos['lote_proveedor'] ?? null,
                            'fecha_vencimiento' => $datos['fecha_vencimiento'] ?? null, 'cantidad_unidades' => Decimal::texto($unidades), 'cantidad_kg' => Decimal::texto($cantidad)]);
                        $presentacionLoteId = $inventario->inventario_presentacion_loteid;
                    }
                } elseif ($ajuste) {
                    if (filled($datos['fecha_vencimiento'] ?? null) || filled($datos['lote_proveedor'] ?? null)) {
                        throw ValidationException::withMessages(['fecha_vencimiento' => 'Un ajuste no puede alterar el vencimiento de la existencia.']);
                    }
                    $partidas = $this->existencias->partidas($insumo, true);
                    if ($partidas->isNotEmpty() && $partidaId === null) {
                        throw ValidationException::withMessages(['materiaprimaloteid' => 'Indica qué partida se está ajustando.']);
                    }
                    if ($partidaId) {
                        $partida = $partidas->firstWhere('materiaprimaloteid', $partidaId);
                        if (! $partida) {
                            throw ValidationException::withMessages(['materiaprimaloteid' => 'La partida no pertenece al producto y almacén.']);
                        }
                        $partida->update(['cantidad_disponible' => Decimal::texto(Decimal::unidades($partida->getRawOriginal('cantidad_disponible')) + $cantidad)]);
                    }
                } else {
                    if ($insumo->presentaciones()->where('activo', true)->exists()) {
                        throw ValidationException::withMessages(['insumo_presentacionid' => 'Selecciona la presentación y registra sus unidades físicas.']);
                    }
                    if ($partidaId !== null) {
                        throw ValidationException::withMessages(['materiaprimaloteid' => 'Un ingreso crea su propia partida; no reutiliza una partida anterior.']);
                    }
                    $partida = MateriaPrimaLote::create(['insumoid' => $insumo->insumoid, 'almacenid' => $almacen->almacenid,
                        'proveedor_actorid' => $insumo->actorid, 'lote_proveedor' => $datos['lote_proveedor'] ?? null,
                        'fecha_recepcion' => $datos['fecha'], 'fecha_vencimiento' => $datos['fecha_vencimiento'] ?? null,
                        'cantidad' => Decimal::texto($cantidad), 'cantidad_disponible' => Decimal::texto($cantidad)]);
                    $partidaId = $partida->materiaprimaloteid;
                }
                $insumo->incrementarStock(Decimal::texto($cantidad));
            }

            return AlmacenMovimiento::create([
                'almacenid' => $almacen->almacenid, 'insumoid' => $insumo->insumoid,
                'tipo_movimiento_almacenid' => $tipo->tipo_movimiento_almacenid,
                'usuarioid' => $usuario->usuarioid, 'fecha' => $datos['fecha'], 'cantidad' => Decimal::texto($cantidad),
                'referencia' => $datos['referencia'] ?? null, 'destino_motivo' => $datos['destino_motivo'] ?? null,
                'observaciones' => $datos['observaciones'] ?? null, 'materiaprimaloteid' => $partidaId ?: null,
                'inventario_presentacion_loteid' => $presentacionLoteId, 'cantidad_unidades' => $datos['cantidad_unidades'] ?? null,
                'unidadmedidaid' => $insumo->unidadmedidaid, 'saldo_anterior' => Decimal::texto($anterior),
                'saldo_posterior' => $insumo->getRawOriginal('stock'),
            ]);
        }, 5);
    }

    public function configurarMinimo(Usuario $usuario, Almacen $almacen, Insumo $insumo, mixed $valor): void
    {
        AlmacenAcceso::asegurarPuedeGestionar($usuario, $almacen);
        $permiso = $usuario->can('inventario.update') || (($almacen->ambito ?? '') === 'punto_venta' && $usuario->can('punto_venta.update'));
        abort_unless($permiso && ! UsuarioRol::debeAcotarPorAsignacion($usuario) && ! UsuarioRol::esOperarioPlanta($usuario), 403);
        abort_unless((int) $insumo->almacenid === (int) $almacen->almacenid, 404);
        Validator::make(['stockminimo' => $valor], ['stockminimo' => ['nullable', 'regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/D']],
            ['stockminimo.regex' => 'Indica un mínimo no negativo con hasta seis decimales.'])->validate();
        $insumo->update(['stockminimo' => $valor === null || $valor === '' ? null : Decimal::texto(Decimal::unidades($valor))]);
    }

    /** Los formularios anteriores expresan un conteo final: obtener la variación bajo bloqueo. */
    public function actualizarFicha(Usuario $usuario, Insumo $insumo, array $datos, ?string $motivo, ?int $partidaId = null): void
    {
        DB::transaction(function () use ($usuario, $insumo, $datos, $motivo, $partidaId) {
            unset($datos['motivo_ajuste'], $datos['materiaprimaloteid']);
            $actual = $this->existencias->bloquear([$insumo->insumoid])->get($insumo->insumoid);
            abort_unless($actual, 404);
            if ($actual->almacen) {
                AlmacenAcceso::asegurarPuedeGestionar($usuario, $actual->almacen);
            }
            $anterior = Decimal::unidades($actual->getRawOriginal('stock'));
            if (isset($datos['unidadmedidaid']) && (int) $datos['unidadmedidaid'] !== (int) $actual->unidadmedidaid
                && ($anterior > 0 || $actual->partidas()->exists())) {
                throw ValidationException::withMessages(['unidadmedidaid' => 'No se puede cambiar la unidad de una existencia con saldo o partidas.']);
            }
            if (array_key_exists('stock', $datos)) {
                $nuevo = Decimal::unidades($datos['stock']);
                if ($nuevo !== $anterior) {
                    if (blank($motivo)) {
                        throw ValidationException::withMessages(['motivo_ajuste' => 'Describe el motivo obligatorio para corregir el saldo.']);
                    }
                    abort_unless($actual->almacen, 403);
                    $naturaleza = $nuevo > $anterior ? 'ingreso' : 'salida';
                    $nombre = $nuevo > $anterior ? 'ajuste positivo' : 'ajuste negativo';
                    $tipo = TipoMovimientoAlmacen::where('naturaleza', $naturaleza)->where('activo', true)->get()
                        ->first(fn ($t) => TipoMovimientoAlmacen::normalizeNombre($t->nombre) === $nombre);
                    if (! $tipo) {
                        throw ValidationException::withMessages(['stock' => 'Configure el tipo de ajuste correspondiente antes de corregir el saldo.']);
                    }
                    $this->registrar($usuario, ['almacenid' => $actual->almacenid, 'insumoid' => $actual->insumoid,
                        'tipo_movimiento_almacenid' => $tipo->tipo_movimiento_almacenid, 'fecha' => now()->toDateString(),
                        'cantidad' => Decimal::texto(abs($nuevo - $anterior)), 'destino_motivo' => $motivo,
                        'referencia' => ($actual->almacen->ambito ?? '') === 'punto_venta' ? 'AJUSTE-PDV' : 'Conteo final de existencias',
                        'observaciones' => '[Ajuste '.(($actual->almacen->ambito ?? '') === 'punto_venta' ? 'PDV' : 'inventario').'] '
                            .\Brick\Math\BigDecimal::of(Decimal::texto($anterior))->toScale(2, \Brick\Math\RoundingMode::HALF_UP).' → '
                            .\Brick\Math\BigDecimal::of(Decimal::texto($nuevo))->toScale(2, \Brick\Math\RoundingMode::HALF_UP).' · Motivo: '.$motivo,
                        'materiaprimaloteid' => $partidaId], $naturaleza);
                }
                unset($datos['stock']);
            }
            if (array_key_exists('stockminimo', $datos)) {
                $this->configurarMinimo($usuario, $actual->almacen, $actual, $datos['stockminimo']);
                unset($datos['stockminimo']);
            }
            $actual->update($datos);
            $insumo->refresh();
        }, 5);
    }
}
