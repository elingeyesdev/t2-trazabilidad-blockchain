<?php

namespace App\Services;

use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\RecepcionQrEnvio;
use App\Models\Usuario;
use App\Support\CampoAccess;
use App\Support\EnvioAsignacionEstadoCatalogo;
use App\Support\EnvioPedidoService;
use App\Support\MayoristaAccess;
use App\Support\PedidoCatalogo;
use App\Support\PedidoDistribucionCatalogo;
use App\Support\PedidoMovilAcceso;
use App\Support\PedidoReservaService;
use App\Support\PuntoVentaAccess;
use App\Support\UsuarioRol;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class PedidoTransicionService
{
    public function ejecutar(Pedido|PedidoDistribucion $pedido, Usuario $user, string $accion, ?string $motivo = null)
    {
        $agricola = $pedido instanceof Pedido;
        abort_unless($user->can($agricola ? 'pedidos.update' : 'pedidos_distribucion.update') && UsuarioRol::puedeOperar($user), 403);
        PedidoMovilAcceso::asegurar($user, $pedido);

        $motivo = $motivo === null ? null : trim($motivo);
        if ($accion === 'rechazar') {
            Validator::make(['motivo_rechazo' => $motivo], ['motivo_rechazo' => ['required', 'string', 'max:500']],
                ['motivo_rechazo.required' => 'Indique el motivo del rechazo.'])->validate();
        }

        return DB::transaction(function () use ($pedido, $user, $accion, $motivo, $agricola) {
            if (DB::getDriverName() === 'sqlite') {
                DB::table($pedido->getTable())->where($pedido->getKeyName(), $pedido->getKey())->update(['estado' => DB::raw('estado')]);
            }
            $actual = $pedido->newQuery()->whereKey($pedido->getKey())->lockForUpdate()->firstOrFail();
            PedidoMovilAcceso::asegurar($user, $actual);
            if ($agricola) {
                $actual->setRelation('envioAsignacion', $actual->envioAsignacion()->lockForUpdate()->first());
            }
            $estadoAnterior = $actual->estado;
            if (in_array($accion, ['aceptar', 'rechazar'], true)) {
                abort_unless($this->autorizado($actual, $user), 403, 'No puede decidir sobre este pedido y sus orígenes.');
                $destino = $accion === 'aceptar' ? 'confirmado' : 'rechazado';
                if ($actual->estado === $destino) {
                    if ($accion === 'rechazar') {
                        $decision = $actual->ultimaDecision;
                        abort_unless($decision && $decision->accion === 'rechazar' && $decision->motivo === $motivo,
                            409, 'El pedido ya fue rechazado con una decisión diferente o sin motivo verificable.');
                    }

                    return $actual;
                }
                abort_unless($this->pendiente($actual) && $this->logisticaCompatible($actual),
                    409, 'El pedido ya fue procesado o tiene un despacho o una recepción incompatible.');
            }
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
                    $actual->update(['estado' => $estado]);
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
                        $actual->update(['estado' => 'rechazado']);
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

            if (in_array($accion, ['aceptar', 'rechazar'], true)) {
                $actual->decisiones()->create([
                    'secuencia' => ((int) $actual->decisiones()->max('secuencia')) + 1,
                    'accion' => $accion, 'estado_anterior' => $estadoAnterior, 'estado_resultante' => $actual->fresh()->estado,
                    'motivo' => $accion === 'rechazar' ? $motivo : null, 'usuarioid' => $user->getKey(), 'fecha' => now(),
                ]);
            }

            return $actual->fresh();
        }, 5);
    }

    /** Orientativas: ejecutar vuelve a comprobar el pedido bloqueado. */
    public function accionesDisponibles(Pedido|PedidoDistribucion $pedido, ?Usuario $user): array
    {
        if (! $user || ! $this->autorizado($pedido, $user) || ! $this->pendiente($pedido) || ! $this->logisticaCompatible($pedido)) {
            return [];
        }

        return ['aceptar', 'rechazar'];
    }

    private function pendiente(Pedido|PedidoDistribucion $pedido): bool
    {
        return $pedido instanceof Pedido ? PedidoCatalogo::pendienteAprobacionAgricola($pedido)
            : PedidoDistribucionCatalogo::pendienteAprobacionMayorista($pedido);
    }

    private function autorizado(Pedido|PedidoDistribucion $pedido, Usuario $user): bool
    {
        $agricola = $pedido instanceof Pedido;
        if (! UsuarioRol::puedeOperar($user) || ! $user->can($agricola ? 'pedidos.update' : 'pedidos_distribucion.update')) {
            return false;
        }
        if (! $agricola) {
            $almacenIds = MayoristaAccess::idsAlmacenesOperados($user);

            return UsuarioRol::puedeGestionarDistribucionMayorista($user)
                && PuntoVentaAccess::scopePedidosDelUsuario($pedido->newQuery()->whereKey($pedido->getKey()), $user)->exists()
                && $pedido->detalles->isNotEmpty()
                && $pedido->detalles->every(function ($detalle) use ($pedido, $user, $almacenIds) {
                    $id = $detalle->almacen_mayorista_origenid ?: $pedido->almacen_mayorista_origenid;

                    return (! $id || in_array((int) $id, $almacenIds, true))
                        && (! $detalle->insumo || ($detalle->insumo->almacen && MayoristaAccess::puedeVerAlmacen($user, $detalle->insumo->almacen)));
                });
        }
        if (! UsuarioRol::esJefeAgricultor($user) || $pedido->detalles->isEmpty()) {
            return false;
        }

        return $pedido->detalles->every(function ($detalle) use ($user) {
            $cosecha = $detalle->produccionalmacenamientoid || str_starts_with($detalle->producto_ref ?? '', 'cosecha:');
            $id = $cosecha ? ($detalle->produccionalmacenamientoid ?: (int) substr($detalle->producto_ref, 8))
                : ($detalle->insumoid ?: (int) substr($detalle->producto_ref ?? '', 7));
            $origen = $cosecha ? ($detalle->cosechaAlmacen ?? \App\Models\ProduccionAlmacenamiento::with('almacen')->find($id))
                : ($detalle->insumo ?? \App\Models\Insumo::with('almacen')->find($id));

            return $origen?->almacen && CampoAccess::puedeGestionarAlmacen($user, $origen->almacen);
        });
    }

    private function logisticaCompatible(Pedido|PedidoDistribucion $pedido): bool
    {
        if ($pedido instanceof PedidoDistribucion) {
            return ! $pedido->fecha_aceptacion && ! $pedido->aceptado_por_usuarioid && ! $pedido->rutadistribucionid && ! $pedido->transportista_usuarioid
                && ! $pedido->fecha_envio && ! $pedido->fecha_recepcion && ! $pedido->fecha_confirmacion_minorista
                && ! $pedido->envio_iniciado_mayorista;
        }
        $envio = $pedido->envioAsignacion;

        return ! $pedido->fecha_aceptacion_agricola && ! $pedido->aceptado_por_usuarioid && $envio && in_array(mb_strtolower(trim($envio->estado)), ['pendiente', 'creada', 'asignado', 'asignada'], true)
            && ! $envio->simulacion_inicio_at && ! $envio->llegada_confirmada_at && ! $envio->fecha_recepcion_planta
            && ! $envio->firmaTransportista && ! $envio->firmaRecepcion
            && ! RecepcionQrEnvio::where('envioasignacionmultipleid', $envio->getKey())->whereNotNull('utilizado_en')->exists();
    }
}
