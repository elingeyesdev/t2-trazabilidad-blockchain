<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\ActualizarPerfilRequest;
use App\Http\Resources\PerfilUsuarioResource;
use App\Services\PerfilUsuarioService;
use Illuminate\Http\JsonResponse;

class PerfilUsuarioController extends Controller
{
    public function update(ActualizarPerfilRequest $request, PerfilUsuarioService $perfiles): JsonResponse
    {
        $usuario = $perfiles->actualizar($request->user(), $request->validated());

        return response()->json((new PerfilUsuarioResource($usuario))->resolve($request));
    }
}
