<?php

namespace App\Services;

use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\Usuario;
use App\Support\EnvioAsignacionEstadoCatalogo;
use App\Support\EnvioPedidoService;
use App\Support\PedidoCatalogo;
use App\Support\PedidoDistribucionCatalogo;
use App\Support\PedidoMovilAcceso;
use App\Support\PedidoReservaService;
use App\Support\UsuarioRol;
use Illuminate\Support\Facades\DB;

class PedidoTransicionService
{
    public function ejecutar(Pedido|PedidoDistribucion $pedido, Usuario $user, string $accion, ?string $motivo = null)
    {
        $agricola = $pedido instanceof Pedido;
        abort_unless($user->can($agricola ? 'pedidos.update' : 'pedidos_distribucion.update') && UsuarioRol::puedeOperar($user), 403);
        PedidoMovilAcceso::asegurar($user, $pedido);

        return DB::transaction(function () use ($pedido, $user, $accion, $motivo, $agricola) {
            if (DB::getDriverName() === 'sqlite') {
                DB::table($pedido->getTable())->where($pedido->getKeyName(), $pedido->getKey())->update(['estado' => DB::raw('estado')]);
            }
            $actual = $pedido->newQuery()->whereKey($pedido->getKey())->lockForUpdate()->firstOrFail();
            PedidoMovilAcceso::asegurar($user, $actual);
            if ($agricola) {
                abort_unless(UsuarioRol::esJefeAgricultor($user), 403);
                abort_unless(in_array($accion, ['aceptar', 'rechazar'], true), 422, 'Acción no disponible para pedidos agrícolas.');
                $estado = $accion === 'aceptar' ? PedidoCatalogo::ESTADO_CONFIRMADO : PedidoCatalogo::ESTADO_RECHAZADO;
                if ($actual->estado === $estado) {
                    return $actual;
                }
                abort_unless(PedidoCatalogo::pendienteAprobacionAgricola($actual), 409, 'El pedido ya fue procesado; no admite esta transición.');
                abort_unless($actual->envioAsignacion, 409, 'El pedido no tiene envío programado.');
                if ($accion === 'aceptar') {
                    app(PedidoReservaService::class)->reservar($actual);
                    $actual->update(['estado' => $estado, 'fecha_aceptacion_agricola' => now(), 'aceptado_por_usuarioid' => $user->getKey()]);
                    EnvioPedidoService::activarTransportistaProgramado($actual);
                    if ($actual->envioAsignacion?->transportista_usuarioid) {
                        app(NotificacionUsuarioService::class)->envioListoParaRecoger($actual->envioAsignacion->fresh(['pedido.detalles']));
                    }
                } else {
                    $actual->update(['estado' => $estado, 'observaciones' => trim(($actual->observaciones ?? '')."\n[Rechazado agrícola] ".($motivo ?: 'Sin motivo.'))]);
                    $actual->envioAsignacion->update(EnvioAsignacionEstadoCatalogo::applyToAttributes(['estado' => 'cancelado']));
                }
            } else {
                if ($accion === 'confirmar-envio-mayorista') {
                    abort_unless(UsuarioRol::esMinorista($user) && (int) $actual->puntoVenta?->usuarioid === (int) $user->getKey(), 403);
                    if ($actual->fecha_confirmacion_minorista !== null) {
                        return $actual;
                    }
                    abort_unless(PedidoDistribucionCatalogo::pendienteConfirmacionMinorista($actual), 409, 'El pedido no espera confirmación del minorista.');
                    $actual->update(['fecha_confirmacion_minorista' => now()]);
                    app(NotificacionUsuarioService::class)->envioMayoristaConfirmadoPorMinorista($actual->fresh(['transportista', 'puntoVenta', 'detalles.insumo']));
                } else {
                    abort_unless(UsuarioRol::puedeGestionarDistribucionMayorista($user), 403);
                    $service = app(PedidoDistribucionMayoristaService::class);
                    if ($accion === 'aceptar') {
                        if ($actual->estado === 'confirmado') {
                            return $actual;
                        }
                        abort_unless(PedidoDistribucionCatalogo::puedeAceptarMayorista($actual), 409, 'El pedido ya fue procesado.');
                        if ($actual->detalles->contains(fn ($d) => $d->datos_solicitud !== null)) {
                            app(PedidoDistribucionReservaService::class)->reservar($actual);
                            $actual->update(['estado' => 'confirmado', 'fecha_aceptacion' => now(), 'aceptado_por_usuarioid' => $user->getKey(), 'coordinacion_planta_resuelta' => true]);
                        } else {
                            $service->aceptarPedido($actual, (int) $user->getKey());
                        }
                    } elseif ($accion === 'rechazar') {
                        if ($actual->estado === 'rechazado') {
                            return $actual;
                        }
                        abort_unless(PedidoDistribucionCatalogo::puedeAceptarMayorista($actual), 409, 'El pedido ya fue procesado.');
                        $actual->update(['estado' => 'rechazado', 'observaciones' => trim(($actual->observaciones ?? '')."\n[Rechazado mayorista] ".($motivo ?: 'Sin motivo.'))]);
                    } elseif ($accion === 'reabrir-revision') {
                        if ($actual->estado === 'pendiente') {
                            return $actual;
                        }
                        abort_unless(PedidoDistribucionCatalogo::puedeReabrirRevision($actual), 409, 'El pedido no puede volver a revisión.');
                        $service->reabrirRevision($actual);
                    } else {
                        abort(422, 'Acción no disponible; los despachos y recepciones requieren el flujo operativo de transporte.');
                    }
                }
            }

            return $actual->fresh();
        }, 5);
    }
}
