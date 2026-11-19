<?php

namespace App\Services;

use App\Models\Almacen;
use App\Models\DetallePedidoDistribucion;
use App\Models\Insumo;
use App\Models\PedidoDistribucion;
use App\Models\PuntoVenta;
use App\Support\AlmacenAmbito;
use App\Support\EnvioTrayectoCatalogo;
use App\Support\MayoristaAccess;
use App\Support\PedidoDistribucionCatalogo;
use App\Support\PedidoDistribucionVista;
use App\Support\UsuarioRol;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

class PedidoDistribucionCreacionService
{
    public function crear(Request $request, DisponibilidadMayoristaPdvService $disponibilidadMayorista, PuntoVentaAlmacenService $almacenPdv, NotificacionUsuarioService $notificaciones): \App\Models\PedidoDistribucion
    {
        abort_unless(PedidoDistribucionVista::puedeCrearSolicitud($request, $request->user()), 403);
        app(PedidoEntradaService::class)->proteger($request);

        return app(PedidoSolicitudService::class)->ejecutar($request, \App\Models\PedidoDistribucion::class, fn () => $this->crearNuevo($request, $disponibilidadMayorista, $almacenPdv, $notificaciones));
    }

    private function crearNuevo(Request $request, DisponibilidadMayoristaPdvService $disponibilidadMayorista, PuntoVentaAlmacenService $almacenPdv, NotificacionUsuarioService $notificaciones): \App\Models\PedidoDistribucion
    {

        $user = $request->user();
        abort_unless(PedidoDistribucionVista::puedeCrearSolicitud($request, $user), 403);

        $esAdmin = UsuarioRol::esAdminGlobal($user);
        $esMayorista = UsuarioRol::esMayorista($user) && ! UsuarioRol::esMinorista($user);
        $esMinorista = UsuarioRol::esMinorista($user) && ! $esAdmin;

        if (! $esMinorista) {
            EnvioTrayectoCatalogo::autorizarTrayecto($user, EnvioTrayectoCatalogo::TRAYECTO_PDV);
        }

        $esIniciadorMayorista = $esMayorista || $esAdmin;
        $requiereAsignacion = $esIniciadorMayorista;

        $request->merge(['tipo_solicitud' => PedidoDistribucionCatalogo::TIPO_SOLICITUD_STOCK]);

        $reglas = [
            'puntoventaid' => 'required|integer|exists:punto_venta,puntoventaid',
            'minorista_usuarioid' => [
                $esAdmin ? 'required' : 'nullable',
                'integer',
                'exists:usuario,usuarioid',
            ],
            'almacen_mayorista_origenid' => [
                $esMinorista ? 'required' : 'nullable',
                'integer',
                'exists:almacen,almacenid',
            ],
            'tipo_solicitud' => 'required|in:stock',
            'fecha_entrega_deseada' => 'required|date|after_or_equal:today',
            'hora_entrega_deseada' => 'nullable|date_format:H:i',
            'observaciones' => 'nullable|string|max:2000',
            'detalles' => 'nullable|array|min:1',
            'detalles.*.insumoid' => 'required|integer|exists:insumo,insumoid',
            'detalles.*.insumo_presentacionid' => 'required|integer|exists:insumo_presentacion,insumo_presentacionid',
            'detalles.*.inventario_presentacion_loteid' => 'nullable|integer|exists:inventario_presentacion_lote,inventario_presentacion_loteid',
            'detalles.*.almacen_mayorista_origenid' => 'nullable|integer|exists:almacen,almacenid',
            'detalles.*.cantidad' => 'required|numeric|gt:0',
            'almacenes_recogida_orden' => 'nullable|array',
            'almacenes_recogida_orden.*' => 'integer|exists:almacen,almacenid',
            'canal_origen' => [
                $esIniciadorMayorista ? 'required' : 'nullable',
                'in:'.implode(',', array_keys(PedidoDistribucionCatalogo::CANALES_EXTERNOS)),
            ],
            'insumoid' => 'nullable|integer|exists:insumo,insumoid',
            'insumo_presentacionid' => 'nullable|integer|exists:insumo_presentacion,insumo_presentacionid',
            'cantidad' => 'nullable|numeric|gt:0',
            'transportista_usuarioid' => [
                $requiereAsignacion ? 'required' : 'nullable',
                'integer',
                'exists:usuario,usuarioid',
            ],
            'vehiculoid' => [
                $requiereAsignacion ? 'required' : 'nullable',
                'integer',
                'exists:vehiculo,vehiculoid',
            ],
        ];

        $data = $request->validate($reglas, [
            'puntoventaid.required' => 'Seleccione un punto de venta destino.',
            'minorista_usuarioid.required' => 'Seleccione el minorista destino.',
            'fecha_entrega_deseada.required' => 'Indique la fecha de entrega deseada.',
            'almacen_mayorista_origenid.required' => 'Seleccione el mayorista desde el catálogo de productos.',
            'detalles.min' => 'Agregue al menos un producto al envío.',
            'detalles.*.insumoid.required' => 'Seleccione un producto disponible en almacén mayorista.',
            'detalles.*.insumo_presentacionid.required' => 'Seleccione la presentación del producto.',
            'detalles.*.cantidad.required' => 'Indique la cantidad solicitada.',
            'detalles.*.cantidad.gt' => 'La cantidad debe ser mayor que cero.',
            'transportista_usuarioid.required' => 'Seleccione el transportista para el envío.',
            'vehiculoid.required' => 'Seleccione el vehículo para el envío.',
            'canal_origen.required' => 'Indique por qué canal recibió el pedido (WhatsApp, teléfono, presencial u otro).',
        ]);

        $lineasEntrada = $data['detalles'] ?? [];
        if ($lineasEntrada === [] && ! empty($data['insumoid'])) {
            $lineasEntrada = [[
                'insumoid' => (int) $data['insumoid'],
                'insumo_presentacionid' => (int) ($data['insumo_presentacionid'] ?? 0),
                'cantidad' => (float) ($data['cantidad'] ?? 0),
            ]];
        }

        if ($lineasEntrada === []) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'Agregue al menos un producto al envío.']);
        }

        $punto = PuntoVenta::query()->findOrFail($data['puntoventaid']);
        if (UsuarioRol::esMinorista($user) && (int) $punto->usuarioid !== (int) $user->usuarioid) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'Solo puede solicitar productos para sus propios puntos de venta.']);
        }

        if (UsuarioRol::esAdminGlobal($user)) {
            if ((int) $punto->usuarioid !== (int) $data['minorista_usuarioid']) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'El punto de venta no pertenece al minorista seleccionado.']);
            }
        }

        if (! $punto->activo) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'El punto de venta seleccionado está inactivo.']);
        }

        $tipoSolicitud = PedidoDistribucionCatalogo::TIPO_SOLICITUD_STOCK;

        $almacenOrigenId = null;
        if ($esIniciadorMayorista) {
            try {
                $almacenOrigenId = EnvioTrayectoCatalogo::resolverAlmacenMayoristaOrigen(
                    $user,
                    isset($data['almacen_mayorista_origenid']) ? (int) $data['almacen_mayorista_origenid'] : null
                );
            } catch (InvalidArgumentException $e) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
            }
        } elseif ($esMinorista && ! empty($data['almacen_mayorista_origenid'])) {
            $almacenOrigenId = (int) $data['almacen_mayorista_origenid'];
        }

        app(PedidoEntradaService::class)->distribucion($request, $lineasEntrada);
        $detallesPayload = [];
        $kgTotalPedido = \Brick\Math\BigDecimal::zero();
        $almacenesEnPedido = [];
        // Ownership (MAY-04, MAY-12): el mayorista solo despacha desde sus almacenes, línea por línea.
        $almacenesPropios = $esIniciadorMayorista ? MayoristaAccess::idsAlmacenesMayorista($user) : [];

        foreach ($lineasEntrada as $i => $linea) {
            $cantidad = \App\Support\CosechaDecimal::cantidad($linea['cantidad'] ?? null, 'detalles.'.$i.'.cantidad');
            if ($cantidad <= 0) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'La cantidad debe ser mayor que cero.']);
            }

            $insumoRef = Insumo::query()->with('almacen')->findOrFail((int) $linea['insumoid']);
            if ($insumoRef->almacen?->ambito !== AlmacenAmbito::MAYORISTA) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'El producto debe estar en almacén mayorista.']);
            }

            $lineaAlmacenId = isset($linea['almacen_mayorista_origenid'])
                ? (int) $linea['almacen_mayorista_origenid']
                : $almacenOrigenId;

            if ($lineaAlmacenId !== null && $lineaAlmacenId > 0 && (int) $insumoRef->almacenid !== $lineaAlmacenId) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'El producto «'.$insumoRef->nombre.'» no corresponde al almacén mayorista seleccionado.']);
            }

            $lineaAlmacenId = (int) $insumoRef->almacenid;
            if ($esIniciadorMayorista && ! in_array($lineaAlmacenId, $almacenesPropios, true)) {
                abort(403, 'El producto «'.$insumoRef->nombre.'» pertenece a un almacén mayorista que no es suyo.');
            }
            if (! in_array($lineaAlmacenId, $almacenesEnPedido, true)) {
                $almacenesEnPedido[] = $lineaAlmacenId;
            }

            if ($almacenOrigenId === null) {
                $almacenOrigenId = $lineaAlmacenId;
            }

            $presentacionId = (int) $linea['insumo_presentacionid'];
            $presentacion = \App\Models\InsumoPresentacion::query()
                ->where('insumo_presentacionid', $presentacionId)
                ->where('activo', true)
                ->first();

            if ($presentacion === null) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'La presentación seleccionada no es válida.']);
            }

            if (! $disponibilidadMayorista->presentacionValidaParaProducto((int) $linea['insumoid'], $presentacionId)) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'La presentación no corresponde al producto «'.$insumoRef->nombre.'».']);
            }

            if (! $disponibilidadMayorista->productoEnCatalogoMayorista((int) $linea['insumoid'])) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'El producto «'.$insumoRef->nombre.'» no está disponible en la red mayorista.']);
            }

            if ($disponibilidadMayorista->necesitaEsperaStock((int) $linea['insumoid'], $presentacionId, $cantidad)) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'La cantidad de «'.$insumoRef->nombre.'» supera el stock disponible. Reduzca la cantidad o elija otra presentación.',
                ]);
            }

            try {
                $disponibilidadMayorista->resolverOrigenStock((int) $linea['insumoid'], $presentacionId, $cantidad);
            } catch (InvalidArgumentException $e) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
            }

            $invLoteId = isset($linea['inventario_presentacion_loteid'])
                ? (int) $linea['inventario_presentacion_loteid']
                : null;
            $referenciaLote = null;
            if ($invLoteId) {
                $invLote = \App\Models\InventarioPresentacionLote::query()->find($invLoteId);
                if ($invLote === null) {
                    throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'El lote seleccionado no es válido.']);
                }
                if ((int) $invLote->almacenid !== $lineaAlmacenId) {
                    throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'El lote no corresponde al almacén mayorista del producto.']);
                }
                if ((float) $invLote->cantidad_unidades + 0.0001 < $cantidad) {
                    throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'La cantidad supera el stock del lote seleccionado.']);
                }
                $referenciaLote = trim((string) ($invLote->referencia_lote ?: $invLote->etiquetaLote()));
            }

            $kgLinea = \App\Support\CosechaDecimal::kg($cantidad, (string) $presentacion->getRawOriginal('peso_neto_kg'));
            $kgTotalPedido = $kgTotalPedido->plus($kgLinea);

            $detallesPayload[] = [
                'cantidad' => $cantidad,
                'datos_solicitud' => ['almacen_id' => $lineaAlmacenId, 'cantidad_kg' => $kgLinea, 'unidad' => $presentacion->etiquetaUnidad(), 'presentacion' => $presentacion->nombre, 'peso_neto_kg' => (string) $presentacion->getRawOriginal('peso_neto_kg')],
                'es_solicitud_custom' => false,
                'insumoid' => $insumoRef->insumoid,
                'almacen_mayorista_origenid' => $lineaAlmacenId,
                'insumo_presentacionid' => $presentacion->insumo_presentacionid,
                'inventario_presentacion_loteid' => $invLoteId,
                'referencia_lote' => $referenciaLote,
                'tipo_envase' => $presentacion->tipo_envase,
                'producto_nombre' => $insumoRef->nombre.' · '.$presentacion->nombre,
            ];
        }

        $ordenRecogida = array_values(array_filter(array_map('intval', $data['almacenes_recogida_orden'] ?? [])));
        // El orden de recogida solo puede nombrar almacenes de las líneas del pedido (MAY-04).
        if (array_diff($ordenRecogida, $almacenesEnPedido) !== []) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'El orden de recogida incluye un almacén que no corresponde a los productos del pedido.']);
        }

        // Todas las líneas se abastecen de almacenes de UN mismo mayorista con dueño: ninguna línea
        // descuenta stock de otro mayorista ni queda un pedido «de cualquiera» (MAY-11, MAY-12).
        $duenos = Almacen::query()
            ->whereIn('almacenid', $almacenesEnPedido ?: [-1])
            ->pluck('responsable_usuarioid')
            ->map(fn ($id) => (int) $id);
        if ($duenos->contains(0) || $duenos->unique()->count() > 1) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => 'Un pedido solo puede abastecerse de almacenes de un mismo mayorista responsable.']);
        }

        if ($ordenRecogida !== []) {
            $almacenOrigenId = $ordenRecogida[0];
        } elseif ($almacenesEnPedido !== []) {
            $almacenOrigenId = $almacenesEnPedido[0];
        }

        try {
            $almacenPdv->validarIngresoPedido($punto, (float) (string) $kgTotalPedido);
        } catch (InvalidArgumentException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
        } catch (\Illuminate\Validation\ValidationException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->validator->errors()->first() ?? 'El pedido supera la capacidad del almacén del punto de venta.']);
        }

        $estadoInicial = $esIniciadorMayorista
            ? PedidoDistribucionCatalogo::ESTADO_CONFIRMADO
            : PedidoDistribucionCatalogo::ESTADO_PENDIENTE;

        try {
            $pedido = DB::transaction(function () use (
                $data,
                $tipoSolicitud,
                $detallesPayload,
                $almacenOrigenId,
                $estadoInicial,
                $esIniciadorMayorista,
                $user
            ) {
                $pedido = PedidoDistribucion::create([
                    'numero_solicitud' => PedidoDistribucionCatalogo::generarNumeroSolicitud(),
                    'puntoventaid' => (int) $data['puntoventaid'],
                    'almacen_mayorista_origenid' => $almacenOrigenId,
                    'estado' => $estadoInicial,
                    'tipo_solicitud' => $tipoSolicitud,
                    'espera_stock' => false,
                    'requiere_coordinacion_planta' => false,
                    'coordinacion_planta_resuelta' => false,
                    'fechapedido' => now(),
                    'fecha_entrega_deseada' => $data['fecha_entrega_deseada'],
                    'hora_entrega_deseada' => $data['hora_entrega_deseada'] ?? null,
                    'observaciones' => $data['observaciones'] ?? null,
                    'creado_por_usuarioid' => $user->usuarioid,
                    'envio_iniciado_mayorista' => $esIniciadorMayorista,
                    'fecha_confirmacion_minorista' => null,
                    'fecha_aceptacion' => $esIniciadorMayorista ? now() : null,
                    'aceptado_por_usuarioid' => $esIniciadorMayorista ? $user->usuarioid : null,
                    // Pedido externo explícito (MAY-13): canal y quién lo registró; no aparenta ser del minorista.
                    'canal_origen' => $esIniciadorMayorista
                        ? $data['canal_origen']
                        : PedidoDistribucionCatalogo::CANAL_SISTEMA,
                    'registrado_manual_por_usuarioid' => $esIniciadorMayorista ? $user->usuarioid : null,
                ]);

                foreach ($detallesPayload as $detallePayload) {
                    DetallePedidoDistribucion::create(array_merge([
                        'pedidodistribucionid' => $pedido->pedidodistribucionid,
                    ], $detallePayload));
                }

                // El envío iniciado por el mayorista nace confirmado: reserva el stock ya (MAY-10).
                if ($estadoInicial === PedidoDistribucionCatalogo::ESTADO_CONFIRMADO) {
                    app(\App\Services\PedidoDistribucionReservaService::class)->reservar($pedido->fresh(['detalles.presentacion', 'detalles.insumo']));
                }

                return $pedido;
            });
        } catch (InvalidArgumentException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
        }

        if ($esIniciadorMayorista) {
            try {
                app(PedidoDistribucionMayoristaService::class)->designarTransportista(
                    $pedido,
                    (int) $data['transportista_usuarioid'],
                    (int) $data['vehiculoid'],
                    (int) $user->usuarioid,
                    $ordenRecogida !== [] ? $ordenRecogida : null
                );
            } catch (\Throwable $e) {
                throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
            }

            $pedido->load(['detalles.insumo', 'puntoVenta.minorista', 'almacenMayoristaOrigen', 'transportista', 'vehiculo']);
            $notificaciones->envioMayoristaPendienteConfirmacionMinorista($pedido);
        } elseif ($esMinorista) {
            $pedido->load(['detalles.insumo', 'puntoVenta.minorista', 'almacenMayoristaOrigen']);
            $notificaciones->solicitudPedidoMinoristaMayorista($pedido);
        }

        return $pedido;
    }
}
