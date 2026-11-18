<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\Api\ProduccionResource;
use App\Services\CosechaRegistroService;
use Illuminate\Http\Request;

class ProduccionController extends Controller
{
    public function __construct(private readonly CosechaRegistroService $registro) {}

    public function index(Request $request, ?int $lote = null)
    {
        $data = $request->validate(['loteid' => 'sometimes|integer|min:1']);
        $loteId = $lote ?? ($data['loteid'] ?? null);
        $query = $this->registro->consulta($request->user())->with('unidadMedida');
        if ($loteId !== null) {
            $this->registro->loteVisible($request->user(), (int) $loteId);
            $query->where('loteid', $loteId);
        }

        // Preserve the existing bare array contract, with exact decimal strings.
        return response()->json($query->orderByDesc('fechacosecha')->orderByDesc('produccionid')->get()
            ->map(fn ($p) => (new ProduccionResource($p))->resolve($request)));
    }

    public function show(Request $request, int $produccion, ?int $lote = null)
    {
        return response()->json((new ProduccionResource($this->registro->detalle($request->user(), $produccion, $lote)))->resolve($request));
    }

    public function showEnLote(Request $request, int $lote, int $produccion)
    {
        return $this->show($request, $produccion, $lote);
    }

    public function store(Request $request)
    {
        return response()->json((new ProduccionResource($this->registro->registrar($request)))->resolve($request), 201);
    }

    public function configuracion(Request $request, int $lote)
    {
        return response()->json($this->registro->configuracion($request->user(), $lote));
    }

    public function update(Request $request, int $produccion)
    {
        $this->registro->detalle($request->user(), $produccion);

        return response()->json(['message' => 'Las cosechas registradas son de solo lectura.'], 405);
    }

    public function destroy(Request $request, int $produccion)
    {
        return $this->update($request, $produccion);
    }
}
