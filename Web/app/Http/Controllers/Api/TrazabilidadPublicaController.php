<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\Api\TrazabilidadPublicaResource;
use App\Models\Insumo;
use App\Models\Lote;
use App\Services\CertificacionPublicaService;
use App\Services\RecorridoPublicoService;
use App\Support\CodigoTrazabilidadPublica;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TrazabilidadPublicaController extends Controller
{
    public function show(Request $request, string $codigo, RecorridoPublicoService $recorrido, CertificacionPublicaService $certificados, \App\Services\EvidenciaPublicacionService $evidencias): JsonResponse
    {
        $codigo = CodigoTrazabilidadPublica::normalizar($codigo);
        $pdv = str_starts_with($codigo, 'TRZ-PDV-');
        $query = $pdv ? Insumo::query() : Lote::query();
        // Uppercase also supports UUID codes historically stored in lowercase.
        $resultados = $query->whereRaw('UPPER(codigo_trazabilidad) = ?', [$codigo])->limit(2)->get();
        abort_if($resultados->isEmpty(), 404, 'No se encontró trazabilidad registrada para este código.');
        abort_if($resultados->count() > 1, 409, 'El código de trazabilidad es ambiguo; no se puede identificar un único registro.');

        $base = $pdv ? $recorrido->desdePdv($resultados->sole()) : $recorrido->desdeLote($resultados->sole());
        $base['evidencias'] = $evidencias->visibles($base['_actividades_publicables']);
        $base['estado_evidencias'] = $base['evidencias'] ? 'con_evidencias_publicas' : 'sin_evidencias_publicas_disponibles';
        $certificacion = $certificados->proyectar($base['_lotes_campo'], $base['_lotes_planta']);
        $datos = [...$base, ...$certificacion, 'codigo' => $codigo, 'tipo' => $pdv ? 'pdv' : 'lote_agricola'];

        return response()->json((new TrazabilidadPublicaResource($datos))->resolve($request))
            ->header('Cache-Control', 'no-store, private');
    }
}
