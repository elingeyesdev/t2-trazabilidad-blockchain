<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Actividad;
use App\Models\EvidenciaPublicacion;
use App\Services\EvidenciaPublicacionService;
use Illuminate\Http\Request;

class EvidenciaPublicacionController extends Controller
{
    public function index(Request $request, EvidenciaPublicacionService $service)
    {
        $f = $request->validate(['page' => 'nullable|integer|min:1', 'per_page' => 'nullable|integer|between:1,50']);

        return $service->consulta($request->user())->with('eventos')->orderByDesc('evidenciapublicacionid')
            ->paginate($f['per_page'] ?? 15)->withQueryString()->through(fn ($p) => $this->datos($p));
    }

    public function solicitar(Request $request, Actividad $actividad, EvidenciaPublicacionService $service)
    {
        $data = $request->validate(['motivo' => 'required|string|max:1000', 'loteproduccionpedidoid' => 'nullable|integer|min:1']);
        $p = $service->solicitar($request->user(), $actividad, $data['motivo'], $data['loteproduccionpedidoid'] ?? null);

        return response()->json($this->datos($p), 201);
    }

    public function aprobar(Request $request, int $publicacion, EvidenciaPublicacionService $service)
    {
        $request->validate(['motivo' => 'required|string|max:1000']);

        return response()->json($this->datos($service->aprobar($request->user(), $publicacion, $request->input('motivo'))));
    }

    public function solicitarRetiro(Request $request, int $publicacion, EvidenciaPublicacionService $service)
    {
        $request->validate(['motivo' => 'required|string|max:1000']);

        return response()->json($this->datos($service->solicitarRetiro($request->user(), $publicacion, $request->input('motivo'))));
    }

    public function retirar(Request $request, int $publicacion, EvidenciaPublicacionService $service)
    {
        $request->validate(['motivo' => 'required|string|max:1000']);

        return response()->json($this->datos($service->retirar($request->user(), $publicacion, $request->input('motivo'))));
    }

    public function archivo(Request $request, int $publicacion, EvidenciaPublicacionService $service)
    {
        return $service->revisarArchivo($request->user(), $publicacion);
    }

    private function datos(EvidenciaPublicacion $p): array
    {
        $p->loadMissing('eventos');

        return ['id' => (int) $p->getKey(), 'actividadid' => $p->actividadid, 'loteproduccionpedidoid' => $p->loteproduccionpedidoid,
            'estado' => $p->estado, 'solicitado_por_usuarioid' => $p->solicitadopor_usuarioid,
            'fecha_solicitud' => $p->created_at?->toIso8601String(), 'aprobado_en' => $p->aprobado_en?->toIso8601String(),
            'retirado_en' => $p->retirado_en?->toIso8601String(),
            'archivo_revision_url' => route('api.evidencias-publicacion.archivo', $p->getKey()),
            'historial' => $p->eventos->sortBy('evidenciapublicacioneventoid')->values()->map(fn ($e) => [
                'usuarioid' => $e->usuarioid, 'accion' => $e->accion, 'motivo' => $e->motivo, 'fecha' => $e->fecha?->toIso8601String(),
            ])->all()];
    }
}
