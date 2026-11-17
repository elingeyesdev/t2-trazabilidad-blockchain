<?php

namespace App\Support;

final class InterfazContexto
{
    public static function datos(): array
    {
        $authUser    = auth()->user();
        $userFull    = $authUser ? trim(($authUser->nombre ?? '') . ' ' . ($authUser->apellido ?? '')) : 'Usuario';
        if ($authUser && ! $userFull) {
            $userFull = $authUser->nombreusuario ?? 'Usuario';
        }
        $userImg     = $authUser ? $authUser->avatarUrl() : \App\Support\UsuarioAvatar::placeholder();
        $userImgFallback = \App\Support\UsuarioAvatar::placeholder();
        $userRole    = $authUser ? ($authUser->getRoleNames()->first() ?? 'sin rol') : 'invitado';
        $isAdmin     = \App\Support\UsuarioRol::esAdminGlobal($authUser);
        $esJefeAgr = $authUser && \App\Support\UsuarioRol::esJefeAgricultor($authUser);
        $esAgricultorOperativo = $authUser && \App\Support\UsuarioRol::debeAcotarPorAsignacion($authUser);
        $esPlantaOperativo = $authUser && \App\Support\UsuarioRol::esPlantaOperativo($authUser) && ! $isAdmin;
        $esTransportistaOperativo = $authUser && \App\Support\UsuarioRol::esTransportista($authUser) && ! $isAdmin;
        $esMinoristaOperativo = $authUser && \App\Support\UsuarioRol::esMinorista($authUser) && ! $isAdmin;
        $esMayoristaOperativo = $authUser && \App\Support\UsuarioRol::esMayorista($authUser) && ! $isAdmin;
        $pendientesSolicitudes = $isAdmin
            ? \App\Models\Usuario::where('estado_cuenta', \App\Support\CuentaEstado::PENDIENTE)->count()
            : 0;
        $roleCss     = strtolower($userRole);
        return compact('authUser', 'userFull', 'userImg', 'userImgFallback', 'userRole', 'isAdmin', 'esJefeAgr', 'esAgricultorOperativo', 'esPlantaOperativo', 'esTransportistaOperativo', 'esMinoristaOperativo', 'esMayoristaOperativo', 'pendientesSolicitudes', 'roleCss');
    }
}
