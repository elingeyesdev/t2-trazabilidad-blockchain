<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\Api\ProduccionPlantaRecorridoResource;
use App\Models\LoteProduccionPedido;
use App\Services\ProduccionPlantaRecorridoService;
use Illuminate\Http\Request;

class ProduccionPlantaRecorridoController extends Controller
{
    public function show(Request $request, LoteProduccionPedido $loteProduccion, ProduccionPlantaRecorridoService $service)
    {
        return new ProduccionPlantaRecorridoResource($service->consultar($loteProduccion, $request->user()));
    }
}
