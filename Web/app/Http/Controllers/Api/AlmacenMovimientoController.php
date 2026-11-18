<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Almacen;
use App\Models\AlmacenMovimiento;
use App\Models\Insumo;
use App\Models\TipoMovimientoAlmacen;
use App\Support\AlmacenAcceso;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AlmacenMovimientoController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        $q = AlmacenAcceso::scopeVisibles(AlmacenMovimiento::query(), $user)
            ->with(['almacen', 'insumo', 'tipo', 'usuario'])
            ->orderByDesc('fecha')
            ->orderByDesc('almacen_movimientoid');

        $filtros = $request->validate(['almacenid' => 'nullable|integer', 'insumoid' => 'nullable|integer', 'naturaleza' => 'nullable|in:ingreso,salida', 'page' => 'nullable|integer|min:1']);
        if (isset($filtros['almacenid'])) {
            AlmacenAcceso::scopeVisibles(Almacen::query(), $user)->findOrFail($filtros['almacenid']);
            $q->where('almacenid', $filtros['almacenid']);
        }
        $q->when($filtros['insumoid'] ?? null, fn ($query, $id) => $query->where('insumoid', $id))
            ->when($filtros['naturaleza'] ?? null, fn ($query, $naturaleza) => $query->whereHas('tipo', fn ($tipo) => $tipo->where('naturaleza', $naturaleza)));
        return response()->json($q->paginate(20)->withQueryString()->through(fn ($movimiento) => $this->contratoExistente($movimiento)));
    }

    public function store(Request $request, string $naturaleza)
    {
        $movimiento = app(\App\Services\InventarioMovimientoService::class)->registrar($request->user(), $request->all(), $naturaleza);
        return response()->json($this->contratoExistente($movimiento->load(['almacen', 'insumo', 'tipo', 'usuario'])), 201);
    }

    private function contratoExistente(AlmacenMovimiento $movimiento): array
    {
        return [...$movimiento->toArray(), 'cantidad' => (float) $movimiento->cantidad, 'cantidad_decimal' => $movimiento->cantidad];
    }
}
