<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\EmisionCertificadoRequest;
use App\Http\Resources\Api\CertificadoEmisionResource;
use App\Models\CertificacionLote;
use App\Models\Lote;
use App\Services\CertificadoEmisionService;
use App\Support\LoteAcceso;
use Illuminate\Http\Request;

class CertificacionController extends Controller
{
    public function index(Request $request)
    {
        $certificados = CertificacionLote::with(['lote', 'usuario'])->whereHas('lote', function ($q) use ($request) {
            LoteAcceso::aplicarScopeVisibles($q, $request->user());
        })->orderByDesc('fecha_certificacion')->orderByDesc('certificacionid')->get();

        return response()->json($certificados->map(fn ($c) => (new CertificadoEmisionResource($c))->resolve($request)));
    }

    public function store(EmisionCertificadoRequest $request, CertificadoEmisionService $service)
    {
        $cert = $service->emitirCampo($request->user(), Lote::findOrFail($request->validated('loteid')), $request->validated());

        return response()->json((new CertificadoEmisionResource($cert))->resolve($request), 201);
    }
}
