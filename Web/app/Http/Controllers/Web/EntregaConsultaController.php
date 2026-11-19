<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Services\EntregaWebPresentacionService;
use App\Services\EnvioMovilConsultaService;
use Illuminate\Http\Request;
use Illuminate\View\View;

class EntregaConsultaController extends Controller
{
    public function show(Request $request, string $tipo, int $envio, EnvioMovilConsultaService $consulta, EntregaWebPresentacionService $presentacion): View
    {
        $operacion = $consulta->buscar($tipo, $envio, $request->user());

        return view('recepcion.seguimiento', [
            'envio' => $consulta->datos($operacion, $request->user()),
            'comprobantes' => $presentacion->comprobantes($operacion, $request->user()),
        ]);
    }
}
