<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\Api\PedidoMovilResource;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Services\DisponibilidadMayoristaPdvService;
use App\Services\NotificacionUsuarioService;
use App\Services\PedidoAgricolaCreacionService;
use App\Services\PedidoDistribucionCreacionService;
use App\Services\PedidoTransicionService;
use App\Services\PuntoVentaAlmacenService;
use App\Support\PedidoMovilAcceso;
use App\Support\PuntoVentaAccess;
use Illuminate\Http\Request;

class PedidoMovilController extends Controller
{
    private function modelo(Request $request): string
    {
        return $request->route('tipo_pedido') === 'distribucion' ? PedidoDistribucion::class : Pedido::class;
    }

    protected function consulta(Request $request)
    {
        $modelo = $this->modelo($request);
        $q = $modelo::query();

        return $modelo === Pedido::class ? PedidoMovilAcceso::agricola($q, $request->user()) : PuntoVentaAccess::scopePedidosDelUsuario($q, $request->user());
    }

    public function index(Request $request)
    {
        $filtros = $request->validate(['per_page' => ['sometimes', 'integer', 'between:1,50'], 'page' => ['sometimes', 'integer', 'min:1'],
            'estado' => ['sometimes', 'string', 'max:40'], 'usuarioid' => ['missing'], 'creado_por_usuarioid' => ['missing']]);
        $query = $this->consulta($request)->with($this->modelo($request) === Pedido::class ? ['detalles', 'envioAsignacion'] : ['detalles', 'puntoVenta']);
        if (isset($filtros['estado'])) {
            $query->where('estado', $filtros['estado']);
        }

        return PedidoMovilResource::collection($query->orderByDesc('fechapedido')->orderByDesc($query->getModel()->getKeyName())->paginate($filtros['per_page'] ?? 15));
    }

    public function show(Request $request, string $pedido)
    {
        $modelo = $this->consulta($request)->findOrFail($pedido);

        return $this->recurso($modelo);
    }

    private function recurso($pedido): PedidoMovilResource
    {
        return new PedidoMovilResource($pedido->load($pedido instanceof Pedido ? ['detalles', 'envioAsignacion'] : ['detalles', 'puntoVenta']));
    }

    public function store(Request $request)
    {
        try {
            $pedido = $this->modelo($request) === Pedido::class ? app(PedidoAgricolaCreacionService::class)->crear($request)
                : app(PedidoDistribucionCreacionService::class)->crear($request, app(DisponibilidadMayoristaPdvService::class), app(PuntoVentaAlmacenService::class), app(NotificacionUsuarioService::class));
        } catch (\InvalidArgumentException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
        }

        return $this->recurso($pedido)->response()->setStatusCode(201);
    }

    public function transicion(Request $request, string $pedido, PedidoTransicionService $service)
    {
        $data = $request->validate(['accion' => ['required', 'string', 'in:aceptar,rechazar,reabrir-revision,confirmar-envio-mayorista'], 'motivo_rechazo' => ['nullable', 'string', 'max:500'],
            'estado' => ['missing'], 'detalles' => ['missing'], 'puntoventaid' => ['missing'], 'creado_por_usuarioid' => ['missing'], 'aceptado_por_usuarioid' => ['missing'], 'cantidad' => ['missing']]);
        $actual = $this->consulta($request)->findOrFail($pedido);
        try {
            return $this->recurso($service->ejecutar($actual, $request->user(), $data['accion'], $data['motivo_rechazo'] ?? null));
        } catch (\InvalidArgumentException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
        }
    }

    public function update(Request $request, string $pedido)
    {
        $this->consulta($request)->findOrFail($pedido);
        throw \Illuminate\Validation\ValidationException::withMessages(['estado' => 'Use la acción autorizada de cambio de estado; esta API no admite reemplazar libremente el pedido.']);
    }

    public function destroy(Request $request, string $pedido)
    {
        $this->consulta($request)->findOrFail($pedido);
        abort(409, 'La eliminación genérica no está disponible; utilice las acciones autorizadas del pedido.');
    }
}
