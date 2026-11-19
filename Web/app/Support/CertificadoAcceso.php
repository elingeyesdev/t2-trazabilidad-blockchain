<?php

namespace App\Support;

use App\Models\Lote;
use App\Models\LoteProduccionPedido;
use App\Models\Usuario;
use Illuminate\Database\Eloquent\Builder;

final class CertificadoAcceso
{
    public static function campo(Usuario $usuario, Lote $lote): bool
    {
        return $usuario->can('certificaciones.view') && LoteAcceso::puedeVer($usuario, $lote);
    }

    public static function scopePlanta(Builder $query, Usuario $usuario): Builder
    {
        if (UsuarioRol::esAdminGlobal($usuario)) {
            return $query;
        }
        $almacenes = PlantaAccess::idsAlmacenesPlanta($usuario);

        return $query->where(function ($q) use ($usuario, $almacenes) {
            $q->whereHas('materiasPrimas.insumo', fn ($i) => $i->whereIn('almacenid', $almacenes))
                ->orWhereHas('asignacionesEtapa', fn ($a) => $a->where('asignado_por_usuarioid', $usuario->getKey()))
                ->orWhereHas('evaluacionesFinales', fn ($e) => $e->where('inspector_usuarioid', $usuario->getKey()));
        });
    }

    public static function planta(Usuario $usuario, LoteProduccionPedido $lote): bool
    {
        return $usuario->can('lote_produccion.view') && ! UsuarioRol::esOperarioPlanta($usuario)
            && self::scopePlanta(LoteProduccionPedido::whereKey($lote->getKey()), $usuario)->exists();
    }
}
