<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PerfilUsuarioResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $usuario = $this->resource;
        $usuario->loadMissing('roles');

        return [
            ...$usuario->only([
                'usuarioid',
                'nombre',
                'apellido',
                'email',
                'nombreusuario',
                'telefono',
                'ci_nit',
                'imagenurl',
                'fecharegistro',
                'fechamodificacion',
                'ultimologin',
                'activo',
                'estado_cuenta',
                'nombreusuario_editado',
            ]),
            'roles' => $usuario->roles
                ->map(fn ($rol) => ['id' => $rol->id, 'name' => $rol->name])
                ->values()
                ->all(),
            'permissions' => $usuario->getAllPermissions()
                ->pluck('name')
                ->unique()
                ->sort()
                ->values()
                ->all(),
            'profile_capabilities' => [
                'update_username' => ! $usuario->nombreusuario_editado,
                'update_photo' => true,
            ],
        ];
    }
}
