<?php

namespace App\Services;

use App\Models\EnvioAsignacionMultiple;
use App\Models\IncidenteEnvio;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\RutaDistribucion;
use App\Models\Usuario;
use App\Support\PedidoMovilAcceso;
use App\Support\PlantaAccess;
use App\Support\PuntoVentaAccess;
use App\Support\UsuarioRol;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Validation\ValidationException;

/** Only explicit order/trip links; no class names or arbitrary client tables. */
final class IncidenteReferenciaService
{
    public const TIPOS = ['pedido_agricola', 'pedido_distribucion', 'envio_agricola', 'traslado', 'distribucion'];

    public const ETIQUETAS = ['pedido_agricola' => 'Pedido agrícola', 'pedido_distribucion' => 'Pedido de distribución',
        'envio_agricola' => 'Envío agrícola', 'traslado' => 'Traslado de planta', 'distribucion' => 'Ruta de distribución'];

    public function puedeAtenderTipo(string $tipo, Usuario $usuario): bool
    {
        if (! UsuarioRol::puedeOperar($usuario)) {
            return false;
        }

        return match ($tipo) {
            'pedido_agricola', 'envio_agricola' => UsuarioRol::esJefeAgricultor($usuario),
            'traslado' => UsuarioRol::esJefePlanta($usuario),
            'pedido_distribucion', 'distribucion' => UsuarioRol::esMayorista($usuario),
            default => false,
        };
    }

    public function consulta(string $tipo, Usuario $usuario): Builder
    {
        abort_unless(in_array($tipo, self::TIPOS, true), 404);
        $fueraDeAmbito = ! UsuarioRol::esAdminGlobal($usuario) && ! UsuarioRol::esTransportista($usuario)
            && (UsuarioRol::esJefeAgricultor($usuario) || UsuarioRol::esJefePlanta($usuario) || UsuarioRol::esMayorista($usuario))
            && ! $this->puedeAtenderTipo($tipo, $usuario);
        if ($fueraDeAmbito) {
            $modelo = match ($tipo) {
                'pedido_agricola' => Pedido::query(),
                'pedido_distribucion' => PedidoDistribucion::query(),
                'envio_agricola' => EnvioAsignacionMultiple::query(),
                default => RutaDistribucion::query(),
            };

            return $modelo->whereRaw('1=0');
        }
        if ($tipo === 'pedido_agricola') {
            $q = PedidoMovilAcceso::agricola(Pedido::query(), $usuario);

            return $usuario->can('pedidos.view') ? $q : $q->whereRaw('1=0');
        }
        if ($tipo === 'pedido_distribucion') {
            $q = PuntoVentaAccess::scopePedidosDelUsuario(PedidoDistribucion::query(), $usuario);

            return $usuario->can('pedidos_distribucion.view') ? $q : $q->whereRaw('1=0');
        }
        $envios = app(EnvioMovilConsultaService::class);
        $trayecto = $tipo === 'envio_agricola' ? 'agricola' : $tipo;
        $modelo = $tipo === 'envio_agricola' ? EnvioAsignacionMultiple::query() : RutaDistribucion::query();
        // An individual recipient must use their order, never an entire shared route.
        if (! $envios->permiso($trayecto, $usuario) || UsuarioRol::esMinorista($usuario)) {
            return $modelo->whereRaw('1=0');
        }

        $query = $envios->consulta($trayecto, $usuario);
        if ($tipo === 'traslado' && ! UsuarioRol::esAdminGlobal($usuario) && ! UsuarioRol::esTransportista($usuario)) {
            $query->whereIn('almacen_planta_origenid', PlantaAccess::idsAlmacenesPlanta($usuario));
        }

        return $query;
    }

    public function buscar(string $tipo, int $id, Usuario $usuario): Model
    {
        return $this->consulta($tipo, $usuario)->findOrFail($id);
    }

    /** Legacy exact codes remain accepted only when they unambiguously identify a permitted trip. */
    public function desdeEntrada(array $datos, Usuario $usuario): array
    {
        $tipo = $datos['afectado_tipo'] ?? null;
        $id = $datos['afectado_id'] ?? null;
        if (! $tipo && ! empty($datos['externo_envio_id'])) {
            $coincidencias = [];
            foreach (['envio_agricola', 'traslado', 'distribucion'] as $opcion) {
                foreach ($this->consulta($opcion, $usuario)->where($opcion === 'envio_agricola' ? 'externo_envio_id' : 'codigo', $datos['externo_envio_id'])->get() as $fila) {
                    $coincidencias[] = [$opcion, (int) $fila->getKey()];
                }
            }
            if (count($coincidencias) !== 1) {
                throw ValidationException::withMessages(['externo_envio_id' => 'Seleccione un pedido o viaje autorizado e inequívoco.']);
            }
            [$tipo, $id] = $coincidencias[0];
        }
        if (! $tipo && ! empty($datos['pedidoid'])) {
            $tipo = 'pedido_agricola';
            $id = $datos['pedidoid'];
        }
        if (! $tipo || ! $id) {
            throw ValidationException::withMessages(['afectado_id' => 'Seleccione el pedido o envío afectado.']);
        }
        $modelo = $this->buscar($tipo, (int) $id, $usuario);
        $pedidoId = $modelo instanceof Pedido ? (int) $modelo->getKey() : ($modelo instanceof EnvioAsignacionMultiple ? $modelo->pedidoid : null);
        $codigo = $modelo instanceof EnvioAsignacionMultiple ? $modelo->externo_envio_id : ($modelo instanceof RutaDistribucion ? $modelo->codigo : null);
        if (! empty($datos['pedidoid']) && (int) $datos['pedidoid'] !== (int) $pedidoId) {
            throw ValidationException::withMessages(['pedidoid' => 'El pedido no corresponde al envío seleccionado.']);
        }
        if (! empty($datos['externo_envio_id']) && $datos['externo_envio_id'] !== $codigo) {
            throw ValidationException::withMessages(['externo_envio_id' => 'El código no corresponde al envío seleccionado.']);
        }

        return [$tipo, $modelo, [
            'afectado_tipo' => $tipo, 'pedidoid' => $pedidoId, 'externo_envio_id' => $codigo,
            'pedidodistribucionid' => $modelo instanceof PedidoDistribucion ? (int) $modelo->getKey() : null,
            'envioasignacionmultipleid' => $modelo instanceof EnvioAsignacionMultiple ? (int) $modelo->getKey() : null,
            'rutadistribucionid' => $modelo instanceof RutaDistribucion ? (int) $modelo->getKey() : null,
        ]];
    }

    public function scope(Builder $query, Usuario $usuario): Builder
    {
        if (! $usuario->can('incidentes.view')) {
            return $query->whereRaw('1=0');
        }
        if (UsuarioRol::esAdminGlobal($usuario)) {
            return $query;
        }

        return $query->where(function ($q) use ($usuario) {
            foreach (self::TIPOS as $tipo) {
                $columna = $this->columna($tipo);
                $fuente = $this->consulta($tipo, $usuario);
                $q->orWhere(function ($w) use ($tipo, $columna, $fuente) {
                    $w->where('afectado_tipo', $tipo)->whereIn($columna, $fuente->select($fuente->getModel()->getKeyName()));
                });
            }
            // Retain old reports without backfilling or changing their provenance.
            $q->orWhere(function ($legacy) use ($usuario) {
                $legacy->whereNull('afectado_tipo')->where(function ($w) use ($usuario) {
                    $w->where('reportadopor_usuarioid', $usuario->getKey());
                    $w->orWhere(fn ($pedido) => $pedido->whereNull('externo_envio_id')
                        ->whereIn('pedidoid', $this->consulta('pedido_agricola', $usuario)->select('pedidoid')));
                });
            });
        });
    }

    public function columna(string $tipo): string
    {
        return match ($tipo) {
            'pedido_agricola' => 'pedidoid', 'pedido_distribucion' => 'pedidodistribucionid',
            'envio_agricola' => 'envioasignacionmultipleid', 'traslado', 'distribucion' => 'rutadistribucionid',
        };
    }

    public function referencia(IncidenteEnvio $incidente, Usuario $usuario): ?array
    {
        if (! $incidente->afectado_tipo) {
            // Historical free-text codes have no guaranteed, typed FK.
            return null;
        }
        $tipo = $incidente->afectado_tipo;
        $id = $incidente->{$this->columna($tipo)};
        if (! $id || ! $this->consulta($tipo, $usuario)->whereKey($id)->exists()) {
            return null;
        }

        return ['tipo' => $tipo, 'id' => (int) $id];
    }
}
