<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\Api\ActividadConsultaResource;
use App\Models\Actividad;
use App\Services\ActividadCierreService;
use App\Support\ActividadPermisos;
use App\Support\LoteAcceso;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

class ActividadCierreController extends Controller
{
    public function cerrar(Request $request, Actividad $actividad, ActividadCierreService $cierre)
    {
        try {
            $guardada = $cierre->cerrar($request, $actividad);
        } catch (ValidationException|HttpExceptionInterface $error) {
            throw $error;
        } catch (\Throwable $error) {
            Log::error('Fallo de cierre de actividad', ['actividadid' => $actividad->actividadid, 'exception' => $error]);
            return response()->json(['message' => 'No se pudo cerrar la actividad. No se confirmaron cambios.'], 500);
        }

        return new ActividadConsultaResource($guardada->fresh()->load([
            'lote.cultivo', 'lote.estadoTipo', 'lote.insumoSemilla.unidadMedida', 'usuario:usuarioid,nombre,apellido',
            'ejecutor:usuarioid,nombre,apellido', 'tipoActividad', 'prioridad',
        ]));
    }

    public function evidencia(Request $request, Actividad $actividad)
    {
        abort_unless(ActividadPermisos::puedeAcceder($request->user(), $actividad)
            && $actividad->lote && LoteAcceso::puedeVer($request->user(), $actividad->lote), 404);
        abort_if($actividad->fechafin === null, 404);
        $archivo = \App\Support\ActividadConsulta::archivo($actividad);
        abort_unless($archivo, 404);
        $disk = Storage::disk($archivo['disk']);
        $path = $archivo['path'];
        abort_unless($disk->exists($path), 404);

        return $disk->response($path, null, ['Cache-Control' => 'private, no-store', 'X-Content-Type-Options' => 'nosniff']);
    }
}
