<?php

namespace App\Support;

use App\Models\Almacen;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\Usuario;
use Illuminate\Database\Eloquent\Builder;

final class PedidoMovilAcceso
{
    public static function agricola(Builder $query, Usuario $user): Builder
    {
        PedidoCatalogo::aplicarFiltroLogistica($query);
        if (UsuarioRol::esAdminGlobal($user)) {
            return $query;
        }
        if (UsuarioRol::esTransportista($user)) {
            return $query->whereHas('envioAsignacion', fn ($q) => $q->where('transportista_usuarioid', $user->getKey()));
        }
        if (! UsuarioRol::esJefeAgricultor($user) && ! UsuarioRol::esJefePlanta($user)) {
            return $query->whereRaw('1=0');
        }
        $almacenes = UsuarioRol::esJefeAgricultor($user)
            ? CampoAccess::scopeAlmacenesAgricolas(Almacen::query(), $user)->pluck('almacenid')->all()
            : PlantaAccess::idsAlmacenesPlanta($user);

        return $query->where(function ($q) use ($user, $almacenes) {
            $q->where('creado_por_usuarioid', $user->getKey())
                ->orWhereHas('envioAsignacion', fn ($e) => $e->where('asignadopor_usuarioid', $user->getKey()))
                ->orWhereHas('detalles.insumo', fn ($i) => $i->whereIn('almacenid', $almacenes))
                ->orWhereHas('detalles.cosechaAlmacen', fn ($c) => $c->whereIn('almacenid', $almacenes))
                ->orWhereExists(fn ($m) => $m->selectRaw('1')->from('materia_prima_lote')->join('detallepedido as d', 'd.detallepedidoid', '=', 'materia_prima_lote.detallepedidoid')
                    ->whereColumn('d.pedidoid', 'pedido.pedidoid')->whereIn('materia_prima_lote.almacenid', $almacenes));
        });
    }

    public static function asegurar(Usuario $user, Pedido|PedidoDistribucion $pedido): void
    {
        $query = $pedido->newQuery()->whereKey($pedido->getKey());
        $query = $pedido instanceof Pedido ? self::agricola($query, $user) : PuntoVentaAccess::scopePedidosDelUsuario($query, $user);
        abort_unless($query->exists(), 404);
    }
}
