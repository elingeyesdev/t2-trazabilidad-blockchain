<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\HistorialEstadoLote;
use App\Http\Resources\Api\HistorialEstadoLoteResource;
use App\Support\LoteAcceso;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class HistorialEstadoLoteController extends Controller
{
    public function index(Request $request)
    {
        $filters = $request->validate([
            'loteid' => ['sometimes', 'integer', 'min:1'],
            'estadolotetipoid' => ['sometimes', 'integer', 'min:1'],
            'fecha_desde' => ['sometimes', 'date'],
            'fecha_hasta' => ['sometimes', 'date', 'after_or_equal:fecha_desde'],
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
            'sort' => ['sometimes', 'string', Rule::in(['historial_estado_id', 'loteid', 'fecha_cambio'])],
            'direction' => ['sometimes', 'string', Rule::in(['asc', 'desc'])],
        ]);

        $query = $this->consultaVisible($request->user())->with(['estadoTipo', 'usuario']);
        foreach (['loteid', 'estadolotetipoid'] as $field) {
            if (isset($filters[$field])) {
                $query->where($field, $filters[$field]);
            }
        }
        if (isset($filters['fecha_desde'])) {
            $query->whereDate('fecha_cambio', '>=', $filters['fecha_desde']);
        }
        if (isset($filters['fecha_hasta'])) {
            $query->whereDate('fecha_cambio', '<=', $filters['fecha_hasta']);
        }

        return HistorialEstadoLoteResource::collection(
            $query->orderBy($filters['sort'] ?? 'historial_estado_id', $filters['direction'] ?? 'desc')
                ->paginate($filters['per_page'] ?? 15)
                ->withQueryString()
        );
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'loteid'           => 'required|integer|exists:lote,loteid',
            'estadolotetipoid' => 'required|integer|exists:estadolote_tipo,estadolotetipoid',
            'fecha_cambio'     => 'nullable|date',
            'observaciones'    => 'nullable|string',
            'imagenurl'        => 'nullable|string',
            'usuarioid'        => 'nullable|integer|exists:usuario,usuarioid',
        ]);

        // Si no envías fecha_cambio, se usa el default de la BD
        $historial = HistorialEstadoLote::create($data);

        return response()->json($historial, 201);
    }

    public function show(Request $request, $id)
    {
        return new HistorialEstadoLoteResource(
            $this->consultaVisible($request->user())
                ->with(['estadoTipo', 'usuario'])
                ->findOrFail($id)
        );
    }

    public function update(Request $request, $id)
    {
        $historial = HistorialEstadoLote::findOrFail($id);

        $data = $request->validate([
            'estadolotetipoid' => 'sometimes|integer|exists:estadolote_tipo,estadolotetipoid',
            'fecha_cambio'     => 'sometimes|date',
            'observaciones'    => 'sometimes|nullable|string',
            'imagenurl'        => 'sometimes|nullable|string',
            'usuarioid'        => 'sometimes|nullable|integer|exists:usuario,usuarioid',
        ]);

        $historial->update($data);

        return response()->json($historial);
    }

    public function destroy($id)
    {
        $historial = HistorialEstadoLote::findOrFail($id);
        $historial->delete();

        return response()->json(null, 204);
    }

    /** @return Builder<HistorialEstadoLote> */
    private function consultaVisible($user): Builder
    {
        return HistorialEstadoLote::query()->whereHas('lote', function (Builder $query) use ($user) {
            LoteAcceso::aplicarScopeVisibles($query, $user);
        });
    }
}