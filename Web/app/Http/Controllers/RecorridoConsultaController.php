<?php

namespace App\Http\Controllers;

use App\Services\ProductoRecorridoConsultaService;
use App\Services\RecorridoIndicadoresService;
use App\Support\CuentaEstado;
use App\Support\RecorridoFiltros;
use Illuminate\Http\Request;

class RecorridoConsultaController extends Controller
{
    public function index(Request $request, RecorridoIndicadoresService $indicadores, ProductoRecorridoConsultaService $recorrido)
    {
        $usuario = $request->user();
        abort_unless(CuentaEstado::puedeIniciarSesion($usuario->estado_cuenta ?? CuentaEstado::APROBADO, (bool) $usuario->activo), 403);
        abort_unless($usuario->can('lotes.view') || $usuario->can('lote_produccion.view') || $usuario->can('inventario.view'), 403);
        $filtros = RecorridoFiltros::validar($request);
        $datos = $indicadores->consultar($request->user(), $filtros);
        $datos['recorrido'] = ! empty($filtros['partida'])
            ? $recorrido->consultar($filtros['tipo'], (int) $filtros['partida'], $request->user(), $filtros) : null;
        $datos['filtros'] = $filtros;
        if ($request->is('api/*')) {
            return response()->json(['data' => $datos]);
        }

        return view('consultas.recorrido', $datos);
    }
}
