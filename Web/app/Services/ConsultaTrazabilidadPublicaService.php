<?php

namespace App\Services;

use App\Http\Resources\Api\TrazabilidadPublicaResource;
use App\Models\Insumo;
use App\Models\Lote;
use App\Support\CodigoTrazabilidadPublica;
use Illuminate\Http\Request;

/** Shared read-only query. Only the public resource leaves this service. */
class ConsultaTrazabilidadPublicaService
{
    public function __construct(
        private RecorridoPublicoService $recorrido,
        private CertificacionPublicaService $certificados,
        private EvidenciaPublicacionService $evidencias,
    ) {}

    public function consultar(string $codigo, Request $request): array
    {
        $codigo = CodigoTrazabilidadPublica::normalizar($codigo);
        $pdv = str_starts_with($codigo, 'TRZ-PDV-');
        $query = $pdv ? Insumo::query() : Lote::query();
        $resultados = $query->whereRaw('UPPER(codigo_trazabilidad) = ?', [$codigo])->limit(2)->get();
        abort_if($resultados->isEmpty(), 404, 'No se encontró trazabilidad registrada para este código.');
        abort_if($resultados->count() > 1, 409, 'El código de trazabilidad es ambiguo; no se puede identificar un único registro.');

        $base = $pdv ? $this->recorrido->desdePdv($resultados->sole()) : $this->recorrido->desdeLote($resultados->sole());
        $base['evidencias'] = $this->evidencias->visibles($base['_actividades_publicables']);
        $base['estado_evidencias'] = $base['evidencias'] ? 'con_evidencias_publicas' : 'sin_evidencias_publicas_disponibles';
        $certificacion = $this->certificados->proyectar($base['_lotes_campo'], $base['_lotes_planta']);

        return (new TrazabilidadPublicaResource([
            ...$base, ...$certificacion, 'codigo' => $codigo, 'tipo' => $pdv ? 'pdv' : 'lote_agricola',
        ]))->resolve($request);
    }
}
