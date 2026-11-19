<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\PlantaConflictoException;
use App\Http\Controllers\Controller;
use App\Http\Requests\PlantaEtapaRequest;
use App\Http\Requests\PlantaRecepcionRequest;
use App\Http\Resources\Api\RecepcionPlantaResource;
use App\Http\Resources\Api\TareaPlantaResource;
use App\Models\Almacen;
use App\Models\AsignacionEtapaPlanta;
use App\Models\LoteProduccionPedido;
use App\Models\Pedido;
use App\Services\RecepcionPlantaEnvioService;
use App\Support\AsignacionEtapaPlantaService;
use App\Support\LoteProduccionParametrosService;
use App\Support\PlantaAccess;
use App\Support\UsuarioRol;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class PlantaTrabajoController extends Controller
{
    private const TAREA_RELACIONES = ['proceso', 'maquina', 'loteProduccion', 'registro'];

    private const RECEPCION_RELACIONES = ['envioAsignacion', 'detalles.insumo', 'detalles.cosechaAlmacen.produccion'];

    public function tareas(Request $request)
    {
        abort_unless(UsuarioRol::esOperarioPlanta($request->user()), 403);
        $filtros = $request->validate(['estado' => ['sometimes', 'in:pendiente,programada,completada,cancelada'],
            'per_page' => ['sometimes', 'integer', 'between:1,50'], 'page' => ['sometimes', 'integer', 'min:1'],
            'usuarioid' => ['missing'], 'operador_usuarioid' => ['missing']]);
        $query = AsignacionEtapaPlanta::with(self::TAREA_RELACIONES)->where('operador_usuarioid', $request->user()->usuarioid);
        if (isset($filtros['estado'])) {
            $query->where('estado', $filtros['estado']);
        }

        return TareaPlantaResource::collection($query->orderBy('orden')->orderByDesc('creado_en')->orderBy('asignacionetapaplantaid')->paginate($filtros['per_page'] ?? 15)->withQueryString());
    }

    private function autorizarTarea(Request $request, AsignacionEtapaPlanta $asignacion): void
    {
        abort_unless(UsuarioRol::esOperarioPlanta($request->user()), 403);
        abort_unless((int) $asignacion->operador_usuarioid === (int) $request->user()->usuarioid, 404);
    }

    public function tarea(Request $request, AsignacionEtapaPlanta $asignacion, AsignacionEtapaPlantaService $service)
    {
        $this->autorizarTarea($request, $asignacion);
        $asignacion->load(self::TAREA_RELACIONES);
        $bloqueo = $service->motivoBloqueo($asignacion);

        return (new TareaPlantaResource($asignacion))->additional(['meta' => [
            'puede_completar' => $bloqueo === null, 'requisito_pendiente' => $bloqueo,
            'maquinas_elegibles' => $bloqueo === null ? [(int) $asignacion->maquinaplantaid] : [],
            'parametros_requeridos' => app(LoteProduccionParametrosService::class)->parametrosRequeridosParaAsignacion($asignacion),
            'permite_parciales' => false],
            'origen_destino' => app(\App\Services\ProduccionPlantaRecorridoService::class)->consultar($asignacion->loteProduccion, $request->user())]);
    }

    public function tareaAnidada(Request $request, LoteProduccionPedido $loteProduccion, AsignacionEtapaPlanta $asignacion, AsignacionEtapaPlantaService $service)
    {
        abort_unless((int) $asignacion->loteproduccionpedidoid === (int) $loteProduccion->getKey(), 404);
        return $this->tarea($request, $asignacion, $service);
    }

    public function completar(PlantaEtapaRequest $request, LoteProduccionPedido $loteProduccion, AsignacionEtapaPlanta $asignacion, AsignacionEtapaPlantaService $service)
    {
        $this->autorizarTarea($request, $asignacion);
        abort_unless((int) $asignacion->loteproduccionpedidoid === (int) $loteProduccion->getKey(), 404);
        try {
            $service->completar($asignacion, $request->validated(), $request->user());
        } catch (PlantaConflictoException $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        } catch (\InvalidArgumentException $e) {
            throw ValidationException::withMessages(['parametros' => $e->getMessage()]);
        } catch (ValidationException $e) {
            throw $e;
        } catch (\Throwable $e) {
            report($e);

            return response()->json(['message' => 'No se pudo completar la etapa. Intente nuevamente.'], 500);
        }

        return new TareaPlantaResource($asignacion->fresh(self::TAREA_RELACIONES));
    }

    public function recepciones(Request $request, RecepcionPlantaEnvioService $service)
    {
        $filtros = $request->validate(['recibido' => ['sometimes', 'boolean'], 'per_page' => ['sometimes', 'integer', 'between:1,50'], 'page' => ['sometimes', 'integer', 'min:1']]);
        $almacenes = Almacen::where('ambito', 'planta')->where('activo', true)->get();
        $visibles = PlantaAccess::idsAlmacenesPlanta($request->user());
        $query = Pedido::whereHas('envioAsignacion', function ($q) use ($filtros) {
            if ($filtros['recibido'] ?? false) {
                $q->whereNotNull('fecha_recepcion_planta');
            } else {
                $q->whereNull('fecha_recepcion_planta')->whereIn('estado', ['en_transporte_planta', 'en_ruta', 'en_transito']);
            }
        });
        $ids = (clone $query)->get(['pedidoid', 'direccion_texto'])->filter(function ($p) use ($service, $almacenes, $visibles) {
            try {
                return in_array((int) $service->resolverAlmacenPlantaDesdePedido($p, $almacenes)->getKey(), $visibles, true);
            } catch (\InvalidArgumentException) {
                return false;
            }
        })->pluck('pedidoid');

        return RecepcionPlantaResource::collection($query->whereIn('pedidoid', $ids)->with(self::RECEPCION_RELACIONES)
            ->orderByDesc('pedidoid')->paginate($filtros['per_page'] ?? 15)->withQueryString());
    }

    private function autorizarRecepcion(Request $request, Pedido $pedido, RecepcionPlantaEnvioService $service): void
    {
        try {
            $almacen = $service->resolverAlmacenPlantaDesdePedido($pedido);
        } catch (\InvalidArgumentException) {
            abort(404);
        }
        abort_unless(PlantaAccess::puedeVerAlmacen($request->user(), $almacen), 404);
        abort_unless($pedido->envioAsignacion()->exists(), 404);
    }

    public function recepcion(Request $request, Pedido $pedido, RecepcionPlantaEnvioService $service)
    {
        $this->autorizarRecepcion($request, $pedido, $service);

        return new RecepcionPlantaResource($pedido->load(self::RECEPCION_RELACIONES));
    }

    public function confirmar(PlantaRecepcionRequest $request, Pedido $pedido, RecepcionPlantaEnvioService $service)
    {
        abort_unless(UsuarioRol::puedeConfirmarRecepcionPlanta($request->user()), 403);
        $this->autorizarRecepcion($request, $pedido, $service);
        try {
            $service->confirmarDesdePedido($pedido, $request->user(), $request->validated('cantidades'));
        } catch (PlantaConflictoException $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        } catch (\InvalidArgumentException $e) {
            throw ValidationException::withMessages(['cantidades' => $e->getMessage()]);
        } catch (ValidationException $e) {
            throw $e;
        } catch (\Throwable $e) {
            report($e);

            return response()->json(['message' => 'No se pudo registrar la recepción. Intente nuevamente.'], 500);
        }

        return new RecepcionPlantaResource($pedido->fresh(self::RECEPCION_RELACIONES));
    }
}
