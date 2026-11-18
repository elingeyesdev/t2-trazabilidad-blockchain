<?php

namespace App\Http\Controllers;

use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\Insumo;
use App\Services\InventarioExistenciaService;
use App\Services\InventarioMovimientoService;
use App\Support\AlmacenAcceso;
use App\Support\AlmacenAmbito;
use Illuminate\Http\Request;

class InventarioExistenciasController extends Controller
{
    public function index(Request $request, Almacen $almacen, InventarioExistenciaService $existencias)
    {
        $this->autorizar($request, $almacen);
        $filtros = $request->validate(['q' => 'nullable|string|max:100', 'estado' => 'nullable|in:bajo,vencido,proximo_a_vencer,sin_fecha_registrada,vigente',
            'per_page' => 'nullable|integer|min:1|max:100', 'page' => 'nullable|integer|min:1']);
        $query = Insumo::where('almacenid', $almacen->almacenid)->with(['unidadMedida', 'tipo', 'almacen'])->orderBy('nombre')->orderBy('insumoid');
        if (filled($filtros['q'] ?? null)) {
            $query->where('nombre', 'like', '%'.$filtros['q'].'%');
        }
        if (filled($filtros['estado'] ?? null)) {
            // Comparar con el mismo cálculo decimal de la respuesta, sin joins que multipliquen saldos.
            $ids = (clone $query)->get()->filter(function ($insumo) use ($existencias, $filtros) {
                $saldo = $existencias->resumen($insumo);
                if ($filtros['estado'] === 'bajo') {
                    return $saldo['existencias_bajas'];
                }
                if ($filtros['estado'] === 'sin_fecha_registrada' && \App\Support\InventarioDecimal::unidades($saldo['cantidad_sin_partida']) > 0) {
                    return true;
                }

                return collect($saldo['partidas'])->contains(fn ($p) => $p['vencimiento_estado'] === $filtros['estado'] && \App\Support\InventarioDecimal::unidades($p['cantidad_fisica']) > 0);
            })->pluck('insumoid');
            $query->whereIn('insumoid', $ids);
        }
        $productos = $query->paginate($filtros['per_page'] ?? 20)->withQueryString();
        $productos->through(fn ($insumo) => ['insumoid' => $insumo->insumoid, 'nombre' => $insumo->nombre,
            'unidadmedidaid' => $insumo->unidadmedidaid, 'unidad' => $insumo->unidadMedida?->abreviatura ?? $insumo->unidadMedida?->nombre,
            ...$existencias->resumen($insumo)]);
        if ($request->is('api/*')) {
            return response()->json($productos);
        }

        return view('almacenes.inventario.existencias', ['almacen' => $almacen, 'productos' => $productos,
            'puedeConfigurar' => AlmacenAcceso::puedeGestionar($request->user(), $almacen) && $request->user()->can('inventario.update'),
            ...AlmacenAmbito::contexto($request)]);
    }

    public function minimo(Request $request, Almacen $almacen, Insumo $insumo, InventarioMovimientoService $movimientos)
    {
        $this->autorizar($request, $almacen);
        $request->validate(['stockminimo' => 'present', 'almacenid' => 'missing', 'insumoid' => 'missing', 'usuarioid' => 'missing']);
        $movimientos->configurarMinimo($request->user(), $almacen, $insumo, $request->input('stockminimo'));
        if ($request->is('api/*')) {
            return response()->json(['insumoid' => $insumo->insumoid, ...app(InventarioExistenciaService::class)->resumen($insumo->fresh())]);
        }

        return back()->with('success', 'Mínimo actualizado para este producto y almacén.');
    }

    public function movimientos(Request $request, Almacen $almacen)
    {
        $this->autorizar($request, $almacen);
        $filtros = $request->validate(['insumoid' => 'nullable|integer', 'naturaleza' => 'nullable|in:ingreso,salida',
            'desde' => 'nullable|date_format:Y-m-d', 'hasta' => 'nullable|date_format:Y-m-d|after_or_equal:desde',
            'per_page' => 'nullable|integer|min:1|max:100', 'page' => 'nullable|integer|min:1']);
        $query = AlmacenMovimiento::where('almacenid', $almacen->almacenid)->with(['tipo', 'insumo.unidadMedida', 'usuario', 'partida', 'presentacionLote', 'unidadMedida']);
        if (! empty($filtros['insumoid'])) {
            Insumo::where('almacenid', $almacen->almacenid)->findOrFail($filtros['insumoid']);
            $query->where('insumoid', $filtros['insumoid']);
        }
        $query->when($filtros['naturaleza'] ?? null, fn ($q, $v) => $q->whereHas('tipo', fn ($t) => $t->where('naturaleza', $v)))
            ->when($filtros['desde'] ?? null, fn ($q, $v) => $q->whereDate('fecha', '>=', $v))
            ->when($filtros['hasta'] ?? null, fn ($q, $v) => $q->whereDate('fecha', '<=', $v));
        $movimientos = $query->orderByDesc('fecha')->orderByDesc('almacen_movimientoid')->paginate($filtros['per_page'] ?? 20)->withQueryString();
        if ($request->is('api/*')) {
            return \App\Http\Resources\Api\InventarioMovimientoResource::collection($movimientos);
        }

        return view('almacenes.inventario.movimientos', ['almacen' => $almacen, 'movimientos' => $movimientos, ...AlmacenAmbito::contexto($request)]);
    }

    public function movimiento(Request $request, Almacen $almacen, AlmacenMovimiento $movimiento)
    {
        $this->autorizar($request, $almacen);
        abort_unless((int) $movimiento->almacenid === (int) $almacen->almacenid, 404);

        return new \App\Http\Resources\Api\InventarioMovimientoResource($movimiento->load(['tipo', 'insumo.unidadMedida', 'usuario', 'partida', 'presentacionLote', 'unidadMedida']));
    }

    private function autorizar(Request $request, Almacen $almacen): void
    {
        abort_unless(AlmacenAcceso::puedeVer($request->user(), $almacen), 404);
        if (! $request->is('api/*')) {
            abort_unless(AlmacenAmbito::resolverAmbito($almacen) === AlmacenAmbito::contexto($request)['ambito'], 404);
        }
    }
}
