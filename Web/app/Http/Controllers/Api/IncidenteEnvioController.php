<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\IncidenteRegistroRequest;
use App\Http\Requests\IncidenteResolucionRequest;
use App\Http\Resources\Api\IncidenteEnvioResource;
use App\Models\IncidenteEnvio;
use App\Services\IncidenteConsultaService;
use App\Services\IncidenteReferenciaService;
use App\Services\IncidenteSeguimientoService;
use Illuminate\Http\Request;

class IncidenteEnvioController extends Controller
{
    public function responsables(Request $request, IncidenteReferenciaService $referencias, IncidenteSeguimientoService $service)
    {
        $actor = $request->user();
        abort_unless(\App\Support\UsuarioRol::puedeOperar($actor)
            && ($actor->can('incidentes.create') || $actor->can('incidentes.update')), 403);
        $datos = $request->validate(['afectado_tipo' => ['required', \Illuminate\Validation\Rule::in(IncidenteReferenciaService::TIPOS)],
            'afectado_id' => ['required', 'integer', 'min:1']]);
        $modelo = $referencias->buscar($datos['afectado_tipo'], (int) $datos['afectado_id'], $actor);
        abort_unless($actor->can('incidentes.create') || $referencias->puedeAtenderTipo($datos['afectado_tipo'], $actor), 403);

        return response()->json($service->responsables($datos['afectado_tipo'], $modelo));
    }

    public function asignar(Request $request, IncidenteEnvio $incidente, IncidenteReferenciaService $referencias, IncidenteSeguimientoService $service)
    {
        $service->obtener((int) $incidente->getKey(), $request->user());
        abort_unless($referencias->puedeAtenderTipo((string) $incidente->afectado_tipo, $request->user()), 403);
        $datos = $request->validate(['responsable_usuarioid' => ['required', 'integer', 'min:1']]);
        $asignado = $service->actualizar($request->user(), (int) $incidente->getKey(), $datos);

        return response()->json((new IncidenteEnvioResource($service->obtener((int) $asignado->getKey(), $request->user())))->resolve($request));
    }

    public function index(Request $request, IncidenteConsultaService $consulta)
    {
        return response()->json($consulta->listado($request));
    }

    public function show(Request $request, IncidenteEnvio $incidente, IncidenteSeguimientoService $service)
    {
        return response()->json((new IncidenteEnvioResource($service->obtener((int) $incidente->getKey(), $request->user())))->resolve($request));
    }

    public function anidado(Request $request, string $tipo, int $afectado, IncidenteEnvio $incidente, IncidenteReferenciaService $referencias, IncidenteSeguimientoService $service)
    {
        $referencias->buscar($tipo, $afectado, $request->user());
        abort_unless($incidente->afectado_tipo === $tipo && (int) $incidente->{$referencias->columna($tipo)} === $afectado, 404);

        return $this->show($request, $incidente, $service);
    }

    public function store(IncidenteRegistroRequest $request, IncidenteSeguimientoService $service)
    {
        $incidente = $service->registrar($request->user(), $request->validated());

        return response()->json((new IncidenteEnvioResource($service->obtener((int) $incidente->getKey(), $request->user())))->resolve($request), 201);
    }

    public function resolve(IncidenteResolucionRequest $request, IncidenteEnvio $incidente, IncidenteSeguimientoService $service)
    {
        $resuelto = $service->resolver($request->user(), (int) $incidente->getKey(), $request->validated('nota_resolucion'));

        return response()->json((new IncidenteEnvioResource($service->obtener((int) $resuelto->getKey(), $request->user())))->resolve($request));
    }
}
