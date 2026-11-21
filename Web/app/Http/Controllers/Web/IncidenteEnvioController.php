<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Http\Requests\IncidenteRegistroRequest;
use App\Http\Requests\IncidenteResolucionRequest;
use App\Http\Resources\Api\IncidenteEnvioResource;
use App\Models\IncidenteEnvio;
use App\Services\IncidenteConsultaService;
use App\Services\IncidenteReferenciaService;
use App\Services\IncidenteSeguimientoService;
use App\Support\UsuarioRol;
use Illuminate\Http\Request;

class IncidenteEnvioController extends Controller
{
    public function index(Request $request, IncidenteConsultaService $consulta)
    {
        return view('logistica.incidentes.index', ['incidentes' => $consulta->listado($request)]);
    }

    public function create(Request $request, IncidenteReferenciaService $referencias, IncidenteSeguimientoService $service)
    {
        abort_unless(UsuarioRol::puedeOperar($request->user()), 403);
        $f = $request->validate(['afectado_ref' => ['nullable', 'regex:/^(pedido_agricola|pedido_distribucion|envio_agricola|traslado|distribucion):[1-9][0-9]*$/D'],
            'afectado_tipo' => ['nullable', 'in:pedido_agricola,pedido_distribucion,envio_agricola,traslado,distribucion'], 'afectado_id' => ['nullable', 'integer', 'min:1']]);
        $tipo = old('afectado_tipo', $f['afectado_tipo'] ?? null);
        $id = old('afectado_id', $f['afectado_id'] ?? null);
        if (! empty($f['afectado_ref'])) {
            [$tipo, $id] = explode(':', $f['afectado_ref']);
        }
        $opciones = [];
        foreach (IncidenteReferenciaService::TIPOS as $opcion) {
            $query = $referencias->consulta($opcion, $request->user());
            $clave = $query->getModel()->getKeyName();
            $codigo = in_array($opcion, ['pedido_agricola', 'pedido_distribucion'], true) ? 'numero_solicitud' : ($opcion === 'envio_agricola' ? 'externo_envio_id' : 'codigo');
            foreach ($query->orderByDesc($clave)->limit(100)->get([$clave, $codigo]) as $fila) {
                $opciones[] = ['valor' => $opcion.':'.$fila->getKey(), 'nombre' => str_replace('_', ' ', $opcion).' · '.($fila->{$codigo} ?: '#'.$fila->getKey())];
            }
        }
        $responsables = [];
        if ($tipo && $id) {
            $modelo = $referencias->buscar($tipo, (int) $id, $request->user());
            $responsables = $service->responsables($tipo, $modelo);
        }

        return view('logistica.incidentes.create', compact('opciones', 'tipo', 'id', 'responsables'));
    }

    public function store(IncidenteRegistroRequest $request, IncidenteSeguimientoService $service)
    {
        $incidente = $service->registrar($request->user(), $request->validated());

        return redirect()->route('logistica.incidentes.show', $incidente)->with('success', 'Incidencia registrada correctamente.');
    }

    private function visible(Request $request, IncidenteEnvio $incidente, IncidenteSeguimientoService $service): IncidenteEnvio
    {
        // Preserve the existing web 403 ownership treatment; API detail uses scoped 404.
        abort_unless(app(IncidenteReferenciaService::class)->scope(IncidenteEnvio::whereKey($incidente->getKey()), $request->user())->exists(), 403);

        return $service->obtener((int) $incidente->getKey(), $request->user());
    }

    public function show(Request $request, IncidenteEnvio $incidente, IncidenteSeguimientoService $service)
    {
        $incidente = $this->visible($request, $incidente, $service);
        $datos = (new IncidenteEnvioResource($incidente))->resolve($request);

        return view('logistica.incidentes.show', compact('incidente', 'datos'));
    }

    public function edit(Request $request, IncidenteEnvio $incidente, IncidenteSeguimientoService $service)
    {
        $incidente = $this->visible($request, $incidente, $service);
        abort_unless(UsuarioRol::puedeOperar($request->user()), 403);
        abort_unless(in_array($incidente->estado, ['abierto', 'pendiente'], true), 409, 'La incidencia ya está resuelta.');
        $responsables = [];
        $puedeAsignar = app(IncidenteReferenciaService::class)->puedeAtenderTipo((string) $incidente->afectado_tipo, $request->user());
        if ($puedeAsignar && ! $incidente->responsable_usuarioid && $incidente->afectado_tipo) {
            $referencias = app(IncidenteReferenciaService::class);
            $modelo = $referencias->buscar($incidente->afectado_tipo, (int) $incidente->{$referencias->columna($incidente->afectado_tipo)}, $request->user());
            $responsables = $service->responsables($incidente->afectado_tipo, $modelo);
        }

        return view('logistica.incidentes.edit', compact('incidente', 'responsables', 'puedeAsignar'));
    }

    public function update(Request $request, IncidenteEnvio $incidente, IncidenteSeguimientoService $service)
    {
        $this->visible($request, $incidente, $service);
        foreach (['tipo', 'descripcion'] as $campo) {
            if (is_string($request->input($campo))) {
                $request->merge([$campo => trim($request->input($campo))]);
            }
        }
        $datos = $request->validate(['tipo' => 'required|string|max:100', 'descripcion' => 'required|string|max:3000',
            'responsable_usuarioid' => 'nullable|integer|min:1', 'estado' => 'missing', 'nota_resolucion' => 'missing',
            'externo_envio_id' => 'missing', 'pedidoid' => 'missing', 'afectado_tipo' => 'missing', 'afectado_id' => 'missing',
            'resueltopor_usuarioid' => 'missing', 'reportadopor_usuarioid' => 'missing', 'fecha_resolucion' => 'missing']);
        $service->actualizar($request->user(), (int) $incidente->getKey(), $datos);

        return redirect()->route('logistica.incidentes.show', $incidente)->with('success', 'Incidencia actualizada.');
    }

    public function destroy(Request $request, IncidenteEnvio $incidente, IncidenteSeguimientoService $service)
    {
        $incidente = $this->visible($request, $incidente, $service);
        abort_unless(UsuarioRol::puedeOperar($request->user()) && ! UsuarioRol::esTransportista($request->user()), 403);
        abort_if($incidente->estado === 'resuelto', 409, 'Se conserva la incidencia resuelta.');
        $incidente->delete();

        return redirect()->route('logistica.incidentes.index')->with('success', 'Incidencia eliminada.');
    }

    public function resolve(IncidenteResolucionRequest $request, IncidenteEnvio $incidente, IncidenteSeguimientoService $service)
    {
        $this->visible($request, $incidente, $service);
        $service->resolver($request->user(), (int) $incidente->getKey(), $request->validated('nota_resolucion'));

        return redirect()->route('logistica.incidentes.show', $incidente)->with('success', 'Incidencia resuelta correctamente.');
    }
}
