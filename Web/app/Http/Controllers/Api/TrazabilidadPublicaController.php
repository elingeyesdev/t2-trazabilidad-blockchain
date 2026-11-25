<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\ConsultaTrazabilidadPublicaService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TrazabilidadPublicaController extends Controller
{
    public function show(Request $request, string $codigo, ConsultaTrazabilidadPublicaService $consulta): JsonResponse
    {
        return response()->json($consulta->consultar($codigo, $request))
            ->header('Cache-Control', 'no-store, private');
    }
}
