<?php

namespace App\Services;

use App\Models\Almacen;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Pedido;
use App\Models\RecepcionQrEnvio;
use App\Models\RutaDistribucion;
use App\Models\Usuario;
use App\Support\CosechaDecimal;
use App\Support\MayoristaAccess;
use App\Support\PedidoMovilAcceso;
use App\Support\PlantaAccess;
use App\Support\PuntoVentaAccess;
use App\Support\UsuarioRol;
use Illuminate\Database\Eloquent\Builder;

class EnvioMovilConsultaService
{
    public function tipo(EnvioAsignacionMultiple|RutaDistribucion $envio): string
    {
        return $envio instanceof EnvioAsignacionMultiple ? 'agricola' : ($envio->esTrasladoPlantaMayorista() ? 'traslado' : 'distribucion');
    }

    public function permiso(string $tipo, Usuario $user, bool $confirmar = false): bool
    {
        return $tipo === 'agricola'
            ? ($confirmar ? $user->can('recepcion_planta.confirm') : ($user->can('recepcion_planta.view') || $user->can('pedidos.view') || $user->can('asignaciones.view')))
            : $user->can($confirmar ? 'pedidos_distribucion.update' : 'pedidos_distribucion.view');
    }

    public function consulta(string $tipo, Usuario $user): Builder
    {
        abort_unless(in_array($tipo, ['agricola', 'distribucion', 'traslado'], true), 404);
        abort_unless($this->permiso($tipo, $user), 403);
        if ($tipo === 'agricola') {
            $query = EnvioAsignacionMultiple::query();
            if (UsuarioRol::esAdminGlobal($user)) {
                return $query;
            }
            if (UsuarioRol::esTransportista($user)) {
                return $query->where('transportista_usuarioid', $user->getKey());
            }
            $pedidos = PedidoMovilAcceso::agricola(Pedido::query(), $user)->pluck('pedidoid');
            if (UsuarioRol::esPlantaOperativo($user)) {
                // Mismo resolvedor de destino que el pesaje; no deducir propiedad por conocer el QR.
                $almacenes = Almacen::where('ambito', 'planta')->where('activo', true)->get();
                $visibles = PlantaAccess::idsAlmacenesPlanta($user);
                $destinos = Pedido::get(['pedidoid', 'direccion_texto'])->filter(function ($p) use ($almacenes, $visibles) {
                    try {
                        return in_array((int) app(RecepcionPlantaEnvioService::class)->resolverAlmacenPlantaDesdePedido($p, $almacenes)->getKey(), $visibles, true);
                    } catch (\InvalidArgumentException) {
                        return false;
                    }
                })->pluck('pedidoid');
                $pedidos = $pedidos->merge($destinos);
            }

            return $query->whereIn('pedidoid', $pedidos);
        }
        $query = RutaDistribucion::query();
        if ($tipo === 'traslado') {
            $query->where('tipo_ruta', 'planta_mayorista');
        } else {
            // El catálogo interpreta las rutas anteriores sin tipo como distribución a PDV.
            $query->where(fn ($q) => $q->where('tipo_ruta', 'mayorista_pdv')->orWhereNull('tipo_ruta'));
        }
        if (UsuarioRol::esAdminGlobal($user)) {
            return $query;
        }
        if (UsuarioRol::esTransportista($user)) {
            return $query->where('transportista_usuarioid', $user->getKey());
        }
        if ($tipo === 'distribucion') {
            return $query->whereHas('pedidos', fn ($p) => PuntoVentaAccess::scopePedidosDelUsuario($p, $user));
        }

        return $query->where(fn ($q) => $q->whereIn('almacen_planta_origenid', PlantaAccess::idsAlmacenesPlanta($user))
            ->orWhereIn('almacen_mayorista_destinoid', MayoristaAccess::idsAlmacenesOperados($user)));
    }

    public function buscar(string $tipo, int $id, Usuario $user): EnvioAsignacionMultiple|RutaDistribucion
    {
        return $this->consulta($tipo, $user)->findOrFail($id);
    }

    public function lineas(EnvioAsignacionMultiple|RutaDistribucion $envio, ?Usuario $destinatario = null): array
    {
        $tipo = $this->tipo($envio);
        if ($tipo === 'agricola') {
            return $envio->pedido?->detalles()->get()->map(fn ($d) => [
                'id' => (int) $d->getKey(), 'pedido_id' => (int) $d->pedidoid,
                'pedido' => $envio->pedido->numero_solicitud, 'producto' => $d->cultivo_personalizado ?: $d->insumo?->nombre,
                'presentacion' => $d->datos_solicitud['presentacion'] ?? null,
                'cantidad_enviada' => CosechaDecimal::cantidad($d->getRawOriginal('cantidad')), 'unidad' => 'kg',
            ])->all() ?? [];
        }
        if ($tipo === 'traslado') {
            return $envio->detallesTraslado()->with('presentacion')->get()->map(fn ($d) => [
                'id' => (int) $d->getKey(), 'pedido_id' => null, 'pedido' => null,
                'producto' => $d->producto_nombre, 'presentacion' => $d->presentacion_nombre,
                'cantidad_enviada' => number_format($d->cantidadDespachada(), 4, '.', ''),
                'unidad' => $d->cantidad_unidades > 0 ? ($d->presentacion?->etiquetaUnidad() ?? 'unidades') : 'kg',
            ])->all();
        }
        $pedidos = $envio->pedidos()->with(['detalles.presentacion', 'puntoVenta'])->get();
        if ($destinatario && UsuarioRol::esMinorista($destinatario)) {
            $pedidos = $pedidos->filter(fn ($p) => (int) $p->puntoVenta?->usuarioid === (int) $destinatario->getKey());
        }

        return $pedidos->flatMap(fn ($p) => $p->detalles->map(fn ($d) => [
            'id' => (int) $d->getKey(), 'pedido_id' => (int) $p->getKey(), 'pedido' => $p->numero_solicitud,
            'producto' => $d->producto_nombre, 'presentacion' => $d->datos_solicitud['presentacion'] ?? $d->presentacion?->nombre,
            'cantidad_enviada' => CosechaDecimal::cantidad($d->getRawOriginal('cantidad')),
            'unidad' => $d->datos_solicitud['unidad'] ?? $d->presentacion?->etiquetaUnidad() ?? 'unidades',
        ]))->values()->all();
    }

    public function datos(EnvioAsignacionMultiple|RutaDistribucion $envio, Usuario $user): array
    {
        $tipo = $this->tipo($envio);
        $destinos = [];
        if ($tipo === 'agricola') {
            $destinos[] = ['nombre' => $envio->pedido?->nombre_planta, 'direccion' => $envio->pedido?->direccion_texto];
        } elseif ($tipo === 'traslado') {
            $destinos[] = ['id' => $envio->almacen_mayorista_destinoid, 'nombre' => $envio->almacenMayoristaDestino?->nombre];
        } else {
            $pedidos = $envio->pedidos()->whereHas('puntoVenta')->with('puntoVenta')->get();
            if (UsuarioRol::esMinorista($user)) {
                $pedidos = $pedidos->filter(fn ($p) => (int) $p->puntoVenta->usuarioid === (int) $user->getKey());
            }
            $destinos = $pedidos->pluck('puntoVenta')->unique('puntoventaid')->map(fn ($p) => ['id' => $p->getKey(), 'nombre' => $p->nombre, 'direccion' => $p->direccion])->values()->all();
        }
        $qrs = RecepcionQrEnvio::whereNotNull('clave_operacion')
            ->where($tipo === 'agricola' ? 'envioasignacionmultipleid' : 'rutadistribucionid', $envio->getKey())
            ->when(UsuarioRol::esMinorista($user), fn ($q) => $q->where('destinatario_usuarioid', $user->getKey()))->get();

        return ['id' => (int) $envio->getKey(), 'tipo' => $tipo,
            'referencia' => $tipo === 'agricola' ? $envio->externo_envio_id : $envio->codigo,
            'estado' => $envio->estado, 'destinos' => $destinos, 'lineas' => $this->lineas($envio, $user),
            'fechas' => ['salida' => $envio->fecha_salida?->toIso8601String(), 'llegada_confirmada' => $envio->llegada_confirmada_at?->toIso8601String()],
            'recepciones' => $qrs->whereNotNull('utilizado_en')->map(fn ($qr) => ['id' => $qr->getKey(), 'fecha' => $qr->utilizado_en->toIso8601String(),
                'url' => url('/api/recepciones-envio/'.$qr->getKey())])->values()->all()];
    }
}
