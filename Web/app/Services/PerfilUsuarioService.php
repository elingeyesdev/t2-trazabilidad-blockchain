<?php

namespace App\Services;

use App\Models\Usuario;
use App\Support\UsuarioAvatar;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Support\Facades\DB;
use Throwable;

class PerfilUsuarioService
{
    public function actualizar(Usuario $usuario, array $datos): Usuario
    {
        $imagenAnterior = null;
        $imagenNueva = null;

        try {
            $actualizado = DB::transaction(function () use ($usuario, $datos, &$imagenAnterior, &$imagenNueva) {
                $actual = Usuario::query()->lockForUpdate()->findOrFail($usuario->getKey());

                if (! $actual->cuentaAprobada()) {
                    throw new AuthorizationException('No tienes autorización para modificar este perfil.');
                }

                if (isset($datos['nombreusuario'])) {
                    $nombre = trim($datos['nombreusuario']);
                    if ($nombre !== $actual->nombreusuario) {
                        if ($actual->nombreusuario_editado) {
                            throw new AuthorizationException('Ya utilizaste tu cambio de nombre de usuario.');
                        }
                        $actual->nombreusuario = $nombre;
                        $actual->nombreusuario_editado = true;
                    }
                }

                if (isset($datos['imagen'])) {
                    $imagenAnterior = $actual->imagenurl;
                    $imagenNueva = UsuarioAvatar::storeUpload($actual, $datos['imagen']);
                    $actual->imagenurl = $imagenNueva;
                }

                $actual->fechamodificacion = now();
                $actual->save();

                return $actual;
            });
        } catch (Throwable $exception) {
            if ($imagenNueva !== null) {
                UsuarioAvatar::deleteStoredFile($imagenNueva);
            }
            throw $exception;
        }

        if ($imagenNueva !== null && $imagenAnterior !== null) {
            UsuarioAvatar::deleteStoredFile($imagenAnterior);
        }

        return $actualizado;
    }
}
