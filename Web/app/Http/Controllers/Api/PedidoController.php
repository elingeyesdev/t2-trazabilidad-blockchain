<?php

namespace App\Http\Controllers\Api;

use App\Models\Pedido;
use App\Services\PedidoAgricolaCreacionService;
use Illuminate\Http\Request;

/** Adaptador del contrato agrícola legado: objetos y listas planos con las claves originales. */
class PedidoController extends PedidoMovilController
{
    private function fila(Pedido $pedido): array
    {
        return $pedido->only(['pedidoid', 'numero_solicitud', 'nombre_planta', 'origen_latitud', 'origen_longitud', 'origen_direccion', 'latitud', 'longitud', 'direccion_texto', 'estado', 'fechapedido', 'fechaEntregaDeseada', 'observaciones', 'fecha_aceptacion_agricola', 'aceptado_por_usuarioid']) + [
            'detalles' => $pedido->detalles->map(fn ($d) => $d->only(['detallepedidoid', 'pedidoid', 'insumoid', 'producto_ref', 'produccionalmacenamientoid', 'nombre_planta', 'cultivo_personalizado', 'cantidad', 'observaciones']))->all()];
    }

    public function index(Request $request)
    {
        $data = $request->validate(['per_page' => ['sometimes', 'integer', 'between:1,50'], 'page' => ['sometimes', 'integer', 'min:1']]);
        $pagina = $this->consulta($request)->with('detalles')->orderByDesc('pedidoid')->paginate($data['per_page'] ?? 15);

        return response()->json($pagina->getCollection()->map(fn ($p) => $this->fila($p)))->header('X-Total-Count', (string) $pagina->total())->header('X-Current-Page', (string) $pagina->currentPage());
    }

    public function show(Request $request, string $pedido)
    {
        return response()->json($this->fila($this->consulta($request)->with('detalles')->findOrFail($pedido)));
    }

    public function store(Request $request)
    {
        return response()->json($this->fila(app(PedidoAgricolaCreacionService::class)->crear($request)->load('detalles')), 201);
    }
}
