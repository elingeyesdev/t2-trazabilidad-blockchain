<?php

namespace App\Support;

use App\Models\LoteProduccionPedido;
use App\Models\Usuario;
use Illuminate\Database\Eloquent\Builder;

final class ProduccionPlantaAcceso
{
    public static function scope(Builder $query, ?Usuario $usuario): Builder
    {
        if (! $usuario || ! $usuario->can('lote_produccion.view')) {
            return $query->whereRaw('1 = 0');
        }
        if (UsuarioRol::esAdminGlobal($usuario)) {
            return $query;
        }
        if (UsuarioRol::esOperarioPlanta($usuario)) {
            return $query->whereHas('asignacionesEtapa', fn ($q) => $q->where('operador_usuarioid', $usuario->getKey()));
        }
        if (! UsuarioRol::esJefePlanta($usuario)) {
            return $query->whereRaw('1 = 0');
        }

        return $query->where(function ($q) use ($usuario) {
            $q->where(fn ($propios) => CertificadoAcceso::scopePlanta($propios, $usuario))
                ->orWhereHas('almacenajes', fn ($a) => $a->whereIn('almacenid', PlantaAccess::idsAlmacenesPlanta($usuario)));
        });
    }

    public static function puedeVer(Usuario $usuario, LoteProduccionPedido $lote): bool
    {
        return self::scope(LoteProduccionPedido::whereKey($lote->getKey()), $usuario)->exists();
    }
}
