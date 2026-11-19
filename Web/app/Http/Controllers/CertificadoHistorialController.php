<?php

namespace App\Http\Controllers;

use App\Http\Resources\Api\CertificadoEmisionResource;
use App\Models\CertificacionLote;
use App\Models\EvaluacionFinalLoteProduccion;
use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Support\CertificadoAcceso;
use App\Support\ProductoAntecedentesService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class CertificadoHistorialController extends Controller
{
    public function campo(Request $request, CertificacionLote $certificacion)
    {
        abort_unless($certificacion->lote && CertificadoAcceso::campo($request->user(), $certificacion->lote), 404);

        return $this->detalle($request, $certificacion, 'campo');
    }

    public function planta(Request $request, EvaluacionFinalLoteProduccion $evaluacionFinalLoteProduccion)
    {
        abort_unless($evaluacionFinalLoteProduccion->loteProduccionPedido
            && CertificadoAcceso::planta($request->user(), $evaluacionFinalLoteProduccion->loteProduccionPedido), 404);

        return $this->detalle($request, $evaluacionFinalLoteProduccion, 'planta');
    }

    private function detalle(Request $request, $emision, string $ambito)
    {
        if ($request->is('api/*')) {
            return response()->json((new CertificadoEmisionResource($emision))->resolve($request));
        }

        return view('certificados.detalle', compact('emision', 'ambito'));
    }

    public function campoAnidado(Request $request, Lote $lote, CertificacionLote $certificacion)
    {
        abort_unless((int) $certificacion->loteid === (int) $lote->getKey(), 404);

        return $this->campo($request, $certificacion);
    }

    public function plantaAnidado(Request $request, LoteProduccionPedido $loteProduccion, EvaluacionFinalLoteProduccion $evaluacionFinalLoteProduccion)
    {
        abort_unless((int) $evaluacionFinalLoteProduccion->loteproduccionpedidoid === (int) $loteProduccion->getKey(), 404);

        return $this->planta($request, $evaluacionFinalLoteProduccion);
    }

    public function historialCampo(Request $request, Lote $lote)
    {
        abort_unless(CertificadoAcceso::campo($request->user(), $lote), 404);

        return $this->historial($request, $lote, 'campo');
    }

    public function historialPlanta(Request $request, LoteProduccionPedido $loteProduccion)
    {
        abort_unless(CertificadoAcceso::planta($request->user(), $loteProduccion), 404);

        return $this->historial($request, $loteProduccion, 'planta');
    }

    private function historial(Request $request, $producto, string $ambito)
    {
        $request->validate(['page' => ['sometimes', 'integer', 'min:1'], 'per_page' => ['sometimes', 'integer', 'between:1,50']]);
        $query = $ambito === 'campo' ? $producto->certificaciones() : $producto->evaluacionesFinales();
        $certificados = $query->orderByDesc($ambito === 'campo' ? 'fecha_certificacion' : 'fecha_evaluacion')
            ->orderByDesc($ambito === 'campo' ? 'certificacionid' : 'evaluacionfinalloteid')->paginate($request->integer('per_page', 20))->withQueryString();
        if ($request->is('api/*')) {
            return CertificadoEmisionResource::collection($certificados);
        }

        return view('certificados.historial', compact('producto', 'ambito', 'certificados'));
    }

    public function archivoCampo(Request $request, CertificacionLote $certificacion)
    {
        abort_unless($certificacion->lote && CertificadoAcceso::campo($request->user(), $certificacion->lote), 404);

        return $this->archivo($certificacion);
    }

    public function archivoPlanta(Request $request, EvaluacionFinalLoteProduccion $evaluacionFinalLoteProduccion)
    {
        abort_unless($evaluacionFinalLoteProduccion->loteProduccionPedido
            && CertificadoAcceso::planta($request->user(), $evaluacionFinalLoteProduccion->loteProduccionPedido), 404);

        return $this->archivo($evaluacionFinalLoteProduccion);
    }

    private function archivo($emision)
    {
        $path = $emision->archivo_path;
        abort_unless(is_string($path) && preg_match('#^certificados/(campo|planta)/[0-9A-HJKMNP-TV-Z]{26}\.pdf$#D', $path)
            && Storage::disk('local')->exists($path), 404, 'No hay un documento archivado disponible para esta emisión.');

        return Storage::disk('local')->download($path, $emision->codigo_certificado.'.pdf', ['Content-Type' => 'application/pdf']);
    }

    public function recorridoCampo(Request $request, Lote $lote, ProductoAntecedentesService $service)
    {
        return response()->json(['datos_actuales' => $service->campo($lote, $request->user()),
            'emisiones' => $lote->certificaciones()->orderByDesc('fecha_certificacion')->orderByDesc('certificacionid')->pluck('certificacionid')]);
    }

    public function recorridoPlanta(Request $request, LoteProduccionPedido $loteProduccion, ProductoAntecedentesService $service)
    {
        return response()->json(['datos_actuales' => $service->planta($loteProduccion, $request->user()),
            'emisiones' => $loteProduccion->evaluacionesFinales()->orderByDesc('fecha_evaluacion')->orderByDesc('evaluacionfinalloteid')->pluck('evaluacionfinalloteid')]);
    }
}
