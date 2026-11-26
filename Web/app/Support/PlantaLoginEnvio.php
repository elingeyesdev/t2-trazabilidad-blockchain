<?php

namespace App\Support;

use App\Models\EnvioAsignacionMultiple;
use App\Models\RecepcionQrEnvio;
use App\Models\RutaDistribucion;
use App\Models\Usuario;
use App\Services\EnvioMovilConsultaService;
use App\Services\EnvioRecepcionQrService;
use App\Services\RecepcionPlantaEnvioService;

final class PlantaLoginEnvio
{
    /** @return array{codigo: string, url: string, producto: string, tipo: string, accion: string, puede_recibir: bool}|null */
    public static function envioPrioritario(?Usuario $user): ?array
    {
        return self::enviosPendientesPlanta($user, 1)[0] ?? null;
    }

    /** @return list<array{codigo: string, url: string, producto: string, tipo: string, accion: string, puede_recibir: bool}> */
    public static function enviosPendientesPlanta(?Usuario $user, int $limite = 5): array
    {
        if (! $user || ! self::aplicaRedirect($user)) {
            return [];
        }

        $consulta = app(EnvioMovilConsultaService::class);
        $recepcion = app(EnvioRecepcionQrService::class);
        $destinos = app(RecepcionPlantaEnvioService::class);
        $almacenesPropios = PlantaAccess::idsAlmacenesPlanta($user);

        $items = $consulta->consulta('agricola', $user)
            ->whereIn('estado', ['en_ruta', 'en_transporte_planta', 'en_transito'])
            ->whereNull('fecha_recepcion_planta')
            ->with(['pedido.detalles'])
            ->orderByDesc('fecha_asignacion')
            ->get()
            ->filter(function (EnvioAsignacionMultiple $envio) use ($destinos, $almacenesPropios) {
                if (! $envio->pedido) {
                    return false;
                }
                try {
                    return in_array((int) $destinos->resolverAlmacenPlantaDesdePedido($envio->pedido)->getKey(), $almacenesPropios, true);
                } catch (\InvalidArgumentException) {
                    return false;
                }
            })
            ->map(function (EnvioAsignacionMultiple $envio) use ($user, $recepcion) {
                $puedeRecibir = $recepcion->puedeConfirmar(new RecepcionQrEnvio, $user, $envio)
                    && $recepcion->listaParaRecepcion($envio);

                return [
                    'tipo' => 'agricola',
                    'codigo' => $envio->pedido?->numero_solicitud ?? $envio->externo_envio_id ?? '#'.$envio->getKey(),
                    'producto' => $envio->pedido?->detalles?->first()?->cultivo_personalizado ?? 'Envío agrícola hacia planta',
                    'url' => $puedeRecibir
                        ? route('recepcion.planta', $envio->getKey(), absolute: false)
                        : route('envios.operacion', ['tipo' => 'agricola', 'envio' => $envio->getKey()], absolute: false),
                    'accion' => $puedeRecibir ? 'Recibir envío' : 'Ver seguimiento',
                    'puede_recibir' => $puedeRecibir,
                ];
            });

        RutaDistribucion::query()
            ->where('tipo_ruta', RutaDistribucionCatalogo::TIPO_RUTA_PLANTA_MAYORISTA)
            ->whereIn('almacen_planta_origenid', $almacenesPropios)
            ->whereNotIn('estado', [
                RutaDistribucionCatalogo::ESTADO_COMPLETADA,
                RutaDistribucionCatalogo::ESTADO_CANCELADA,
                RutaDistribucionCatalogo::ESTADO_RECHAZADA,
            ])
            ->with(['detallesTraslado.insumo'])
            ->orderByDesc('updated_at')
            ->limit($limite)
            ->get()
            ->each(function (RutaDistribucion $ruta) use ($items) {
                $url = $ruta->estado === RutaDistribucionCatalogo::ESTADO_EN_RUTA
                    ? route('logistica.traslados-planta.cierre.panel', $ruta)
                    : route('logistica.traslados-planta.show', $ruta);
                $items->push([
                    'tipo' => 'planta_mayorista',
                    'codigo' => $ruta->codigo,
                    'producto' => $ruta->detallesTraslado?->first()?->insumo?->nombre ?? $ruta->nombre ?? 'Traslado planta → mayorista',
                    'url' => $url, 'accion' => 'Ir al envío', 'puede_recibir' => false,
                ]);
            });

        return $items->sortByDesc('puede_recibir')->unique('url')->take($limite)->values()->all();
    }

    private static function aplicaRedirect(Usuario $user): bool
    {
        return ! UsuarioRol::esAdminGlobal($user)
            && (UsuarioRol::esJefePlanta($user)
                || ($user->can('panel_planta.view') && $user->can('pedidos.view')));
    }
}
