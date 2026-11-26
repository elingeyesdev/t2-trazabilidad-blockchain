<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Insumo;
use App\Support\AlmacenAcceso;
use App\Support\AlmacenAmbito;
use App\Support\InsumoCatalogo;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class InsumoController extends Controller
{
    public function index(Request $request)
    {
        return response()->json(
            $this->scopeVisibles(Insumo::query(), $request)
                ->with(['tipo', 'unidadMedida'])
                ->get()
                ->each(fn ($insumo) => $insumo->setAttribute('existencia', app(\App\Services\InventarioExistenciaService::class)->resumen($insumo)))
                ->makeVisible(['tipo', 'unidadMedida'])
                ->map(fn ($insumo) => (new \App\Http\Resources\Api\InsumoInventarioResource($insumo))->resolve($request))
        );
    }

    public function show(Request $request, $id)
    {
        $insumo = $this->scopeVisibles(Insumo::query(), $request)
            ->with(['tipo', 'unidadMedida', 'loteInsumos'])
            ->findOrFail($id)
            ->makeVisible(['tipo', 'unidadMedida']);

        $insumo->setAttribute('existencia', app(\App\Services\InventarioExistenciaService::class)->resumen($insumo));
        return response()->json((new \App\Http\Resources\Api\InsumoInventarioResource($insumo))->resolve($request));
    }

    public function store(Request $request)
    {
        $data = $this->validarInsumo($request);
        // El mínimo pertenece a esta existencia; no imponer el umbral global.

        unset($data['motivo_ajuste'], $data['materiaprimaloteid']);
        $data['stockminimo'] = $data['stockminimo'] ?? null;
        $insumo = Insumo::create($data);

        return response()->json((new \App\Http\Resources\Api\InsumoInventarioResource($insumo->load(['tipo', 'unidadMedida'])->makeVisible(['tipo', 'unidadMedida'])))->resolve($request), 201);
    }

    public function update(Request $request, $id)
    {
        $insumo = Insumo::findOrFail($id);
        $this->asegurarPuedeModificar($request, $insumo);

        $data = $this->validarInsumo($request, partial: true);

        // El mínimo pertenece a esta existencia; no imponer el umbral global.

        app(\App\Services\InventarioMovimientoService::class)->actualizarFicha($request->user(), $insumo, $data, $request->input('motivo_ajuste'), $request->filled('materiaprimaloteid') ? (int) $request->input('materiaprimaloteid') : null);

        return response()->json((new \App\Http\Resources\Api\InsumoInventarioResource($insumo->load(['tipo', 'unidadMedida'])->makeVisible(['tipo', 'unidadMedida'])))->resolve($request));
    }

    public function indexPdv(Request $request)
    {
        $query = $this->consultaPdv($request)->with(['tipo', 'unidadMedida'])->get();

        return response()->json($query->map(function ($insumo) use ($request) {
            $insumo->setAttribute('existencia', app(\App\Services\InventarioExistenciaService::class)->resumen($insumo));

            return (new \App\Http\Resources\Api\InsumoInventarioResource($insumo->makeVisible(['tipo', 'unidadMedida'])))->resolve($request);
        }));
    }

    public function showPdv(Request $request, int $insumo)
    {
        $producto = $this->consultaPdv($request)->with(['tipo', 'unidadMedida'])->findOrFail($insumo);
        $producto->setAttribute('existencia', app(\App\Services\InventarioExistenciaService::class)->resumen($producto));

        return response()->json((new \App\Http\Resources\Api\InsumoInventarioResource($producto->makeVisible(['tipo', 'unidadMedida'])))->resolve($request));
    }

    private function consultaPdv(Request $request)
    {
        $puntos = \App\Support\PuntoVentaAccess::scopePuntosDelUsuario(\App\Models\PuntoVenta::query(), $request->user());

        return Insumo::whereIn('almacenid', $puntos->whereNotNull('almacenid')->select('almacenid'));
    }

    public function destroy(Request $request, $id)
    {
        $insumo = Insumo::findOrFail($id);
        $this->asegurarPuedeModificar($request, $insumo);
        $insumo->delete();

        return response()->json(['message' => 'Eliminado correctamente']);
    }

    /**
     * Insumos sin almacén (catálogo agrícola) siguen visibles según el permiso de la ruta; los que
     * pertenecen a un almacén solo si ese almacén es visible para el usuario (MAY-05).
     */
    private function scopeVisibles($query, Request $request)
    {
        $ids = AlmacenAcceso::idsVisibles($request->user());

        return $query->where(function ($q) use ($ids) {
            $q->whereNull('almacenid')->orWhereIn('almacenid', $ids ?: [-1]);
        });
    }

    private function asegurarPuedeModificar(Request $request, Insumo $insumo): void
    {
        $insumo->loadMissing('almacen');
        if ($insumo->almacen !== null) {
            AlmacenAcceso::asegurarPuedeGestionar($request->user(), $insumo->almacen);
        }
    }

    private function esInventarioComercial(Insumo $insumo): bool
    {
        $insumo->loadMissing('almacen');

        return $insumo->almacen !== null && in_array(
            AlmacenAmbito::resolverAmbito($insumo->almacen),
            [AlmacenAmbito::MAYORISTA, AlmacenAmbito::PUNTO_VENTA],
            true
        );
    }

    private function validarInsumo(Request $request, bool $partial = false): array
    {
        InsumoCatalogo::asegurarCatalogosBase();
        $tiposIds = InsumoCatalogo::tiposOrdenados()->pluck('tipoinsumoid')->all();

        $rules = [
            'nombre' => ($partial ? 'sometimes|' : '').'required|string|max:100',
            'tipoinsumoid' => ($partial ? 'sometimes|' : '').'required|'.Rule::in($tiposIds),
            'unidadmedidaid' => ($partial ? 'sometimes|' : '').'required|exists:unidadmedida,unidadmedidaid',
            'stock' => ($partial ? 'sometimes|' : '').'required|numeric|min:0',
            'stockminimo' => ['nullable', 'regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/D'],
            'motivo_ajuste' => 'nullable|string|max:150',
            'materiaprimaloteid' => 'nullable|integer|min:0',
            'descripcion' => 'nullable|string',
        ];

        $data = $request->validate($rules);

        if (isset($data['tipoinsumoid'], $data['unidadmedidaid'])) {
            $this->validarUnidadParaTipo((int) $data['tipoinsumoid'], (int) $data['unidadmedidaid']);
        } elseif (isset($data['unidadmedidaid']) && $request->filled('tipoinsumoid')) {
            $this->validarUnidadParaTipo((int) $request->input('tipoinsumoid'), (int) $data['unidadmedidaid']);
        }

        return $data;
    }

    private function validarUnidadParaTipo(int $tipoinsumoid, int $unidadmedidaid): void
    {
        $tipo = InsumoCatalogo::tiposOrdenados()->firstWhere('tipoinsumoid', $tipoinsumoid);
        $slug = InsumoCatalogo::slugFromNombreTipo($tipo?->nombre);
        $permitidas = collect(InsumoCatalogo::unidadesPorTipoParaJs()[$slug] ?? [])->pluck('id')->all();

        if ($permitidas !== [] && ! in_array($unidadmedidaid, $permitidas, true)) {
            throw \Illuminate\Validation\ValidationException::withMessages([
                'unidadmedidaid' => 'La unidad no corresponde al tipo de insumo seleccionado.',
            ]);
        }
    }
}
