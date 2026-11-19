<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\Almacen;
use App\Models\DetallePedidoDistribucion;
use App\Models\Insumo;
use App\Models\PedidoDistribucion;
use App\Models\PuntoVenta;
use App\Models\Usuario;
use App\Services\DisponibilidadMayoristaPdvService;
use App\Services\NotificacionUsuarioService;
use App\Services\PedidoDistribucionMayoristaService;
use App\Services\PuntoVentaAlmacenService;
use App\Services\RecepcionPuntoVentaService;
use App\Services\SimulacionRutaService;
use App\Services\TransporteCapacidadService;
use App\Support\AlmacenAmbito;
use App\Support\EnvioTrayectoCatalogo;
use App\Support\MayoristaAccess;
use App\Support\PedidoDistribucionCatalogo;
use App\Support\PedidoDistribucionVista;
use App\Support\PuntoVentaAccess;
use App\Support\SimulacionRutaCatalogo;
use App\Support\UbicacionGpsParser;
use App\Support\UsuarioRol;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use Illuminate\View\View;

class PedidoDistribucionController extends Controller
{
    public function index(Request $request): View
    {
        $request->validate(['q' => ['nullable', 'string', 'max:150'], 'desde' => ['nullable', 'date_format:Y-m-d'],
            'hasta' => ['nullable', 'date_format:Y-m-d', ...($request->filled('desde') ? ['after_or_equal:desde'] : [])], 'puntoventaid' => ['nullable', 'integer', 'min:1'], 'almacenid' => ['nullable', 'integer', 'min:1']]);
        $user = $request->user();
        $esBandejaMayorista = PedidoDistribucionVista::esBandejaMayorista($request, $user);

        $query = PuntoVentaAccess::scopePedidosDelUsuario(
            PedidoDistribucion::query()->with([
                'puntoVenta.minorista',
                'detalles.insumo.unidadMedida',
                'detalles.insumo.almacen',
                'detalles.presentacion',
                'almacenMayoristaOrigen',
                'creadoPor',
                'rutaDistribucion',
            ]),
            $user
        );

        if ($request->filled('estado_grupo')) {
            $query = PedidoDistribucionCatalogo::aplicarFiltroGrupoEstado(
                $query,
                $request->string('estado_grupo')->toString()
            );
        } elseif ($request->filled('estado')) {
            $query->where('estado', $request->string('estado')->toString());
        }

        if ($request->filled('puntoventaid')) {
            $query->where('puntoventaid', (int) $request->input('puntoventaid'));
        }

        if ($esBandejaMayorista && $request->filled('almacenid')) {
            $query->where('almacen_mayorista_origenid', (int) $request->input('almacenid'));
        }

        if ($request->filled('q')) {
            $term = $request->string('q')->trim()->toString();
            $query->where(function ($w) use ($term) {
                $w->where('numero_solicitud', 'like', "%{$term}%")
                    ->orWhere('observaciones', 'like', "%{$term}%")
                    ->orWhereHas('puntoVenta', fn ($p) => $p->where('nombre', 'like', "%{$term}%"))
                    ->orWhereHas('puntoVenta.minorista', function ($m) use ($term) {
                        $m->where('nombre', 'like', "%{$term}%")
                            ->orWhere('apellido', 'like', "%{$term}%");
                    })
                    ->orWhereHas('detalles', fn ($d) => $d->where('producto_nombre', 'like', "%{$term}%"));
            });
        }

        foreach (['desde' => '>=', 'hasta' => '<='] as $campo => $operador) {
            if ($request->filled($campo)) { $query->whereDate('fechapedido', $operador, $request->input($campo)); }
        }
        $pedidos = $query->orderByDesc('pedidodistribucionid')->get();

        $pendientes = $pedidos->filter(fn (PedidoDistribucion $p) => PedidoDistribucionCatalogo::pendienteAprobacionMayorista($p));
        $procesados = $pedidos->reject(fn (PedidoDistribucion $p) => PedidoDistribucionCatalogo::pendienteAprobacionMayorista($p));
        $enRutaTiempoReal = $pedidos->filter(fn (PedidoDistribucion $p) => PedidoDistribucionCatalogo::estaEnRutaTiempoReal($p));

        $puntosVenta = PuntoVentaAccess::scopePuntosDelUsuario(
            PuntoVenta::query()->where('activo', true)->orderBy('nombre'),
            $user
        )->get();

        if ($esBandejaMayorista) {
            $puntosVenta = PuntoVenta::where('activo', true)->whereHas('pedidosDistribucion',
                fn ($p) => PuntoVentaAccess::scopePedidosDelUsuario($p, $user))->orderBy('nombre')->get();
        }
        $filtroPdvId = $request->integer('puntoventaid') ?: null;
        $filtroPdvNombre = $filtroPdvId
            ? ($puntosVenta->firstWhere('puntoventaid', $filtroPdvId)?->nombre ?? '')
            : '';

        $puedeCrear = PedidoDistribucionVista::puedeCrearSolicitud($request, $user);
        $puedeGestionarMayorista = UsuarioRol::puedeGestionarDistribucionMayorista($user);
        $esMinorista = UsuarioRol::esMinorista($user);

        $almacenesMayorista = $esBandejaMayorista
            ? AlmacenAmbito::scope(Almacen::query()->where('activo', true)->whereIn('almacenid', MayoristaAccess::idsAlmacenesOperados($user)), AlmacenAmbito::MAYORISTA)->orderBy('nombre')->get()
            : collect();

        $viewData = compact(
            'pedidos',
            'pendientes',
            'procesados',
            'enRutaTiempoReal',
            'puntosVenta',
            'filtroPdvId',
            'filtroPdvNombre',
            'puedeCrear',
            'puedeGestionarMayorista',
            'esMinorista',
            'esBandejaMayorista',
            'almacenesMayorista'
        );

        return view(
            $esBandejaMayorista ? 'punto_venta.pedidos.index-mayorista' : 'punto_venta.pedidos.index',
            $viewData
        );
    }

    public function create(Request $request): View
    {
        $user = $request->user();
        abort_unless(PedidoDistribucionVista::puedeCrearSolicitud($request, $user), 403);

        AlmacenAmbito::asegurarAmbitosEnRegistros();

        $esMinorista = UsuarioRol::esMinorista($user);
        $esAdmin = UsuarioRol::esAdminGlobal($user);

        $puntosMinorista = PuntoVentaAccess::scopePuntosDelUsuario(
            PuntoVenta::query()->where('activo', true)->with('minorista')->orderBy('nombre'),
            $user
        )->get();

        $oldPunto = old('puntoventaid') ? PuntoVenta::with('minorista')->find(old('puntoventaid')) : null;
        if ($oldPunto === null && $esMinorista && $puntosMinorista->count() === 1) {
            $oldPunto = $puntosMinorista->first();
        }
        $oldMinoristaId = old('minorista_usuarioid');
        $oldMinoristaLabel = '';
        if ($esAdmin) {
            if ($oldMinoristaId) {
                $minoristaUser = Usuario::find((int) $oldMinoristaId);
                $oldMinoristaLabel = $minoristaUser
                    ? trim($minoristaUser->nombre.' '.($minoristaUser->apellido ?? ''))
                    : '';
            } elseif ($oldPunto?->minorista) {
                $oldMinoristaId = (int) $oldPunto->usuarioid;
                $oldMinoristaLabel = trim($oldPunto->minorista->nombre.' '.($oldPunto->minorista->apellido ?? ''));
            }
        }
        $oldAlmacen = old('almacen_mayorista_origenid') ? Almacen::find(old('almacen_mayorista_origenid')) : null;
        $oldInsumo = old('insumoid') ? Insumo::with('unidadMedida', 'almacen')->find(old('insumoid')) : null;

        $puntosVentaMapa = $puntosMinorista->map(fn (PuntoVenta $pv) => [
            'id' => $pv->puntoventaid,
            'label' => $pv->nombre,
            'minorista_usuarioid' => (int) $pv->usuarioid,
            'lat' => $pv->latitud,
            'lng' => $pv->longitud,
            'resumen' => $pv->resumenUbicacion(),
            'direccion' => $pv->direccionParaMostrar(),
        ])->values()->all();

        return view('punto_venta.pedidos.create', [
            'numeroSolicitud' => PedidoDistribucionCatalogo::generarNumeroSolicitud(),
            'puntosMinorista' => $puntosMinorista,
            'puntosVentaMapa' => $puntosVentaMapa,
            'esMinorista' => $esMinorista,
            'esAdmin' => $esAdmin,
            'oldMinoristaId' => $oldMinoristaId,
            'oldMinoristaLabel' => $oldMinoristaLabel,
            'oldPuntoLabel' => $oldPunto?->nombre ?? '',
            'oldPuntoResumen' => $oldPunto?->resumenUbicacion() ?? '',
            'oldPuntoId' => $oldPunto?->puntoventaid,
            'oldAlmacenLabel' => $oldAlmacen?->nombre ?? '',
            'oldProductoLabel' => $oldInsumo
                ? $oldInsumo->nombre.' · Stock '.number_format((float) $oldInsumo->stock, 2).' '.($oldInsumo->unidadMedida?->abreviatura ?? '')
                : '',
            'oldProductoUnidad' => $oldInsumo?->unidadMedida?->abreviatura ?? $oldInsumo?->unidadMedida?->nombre ?? '',
            'oldProductoStock' => $oldInsumo ? (float) $oldInsumo->stock : null,
        ]);
    }

    public function store(Request $request, DisponibilidadMayoristaPdvService $disponibilidadMayorista, PuntoVentaAlmacenService $almacenPdv, NotificacionUsuarioService $notificaciones): RedirectResponse
    {
        try {
            $pedido = app(\App\Services\PedidoDistribucionCreacionService::class)->crear($request, $disponibilidadMayorista, $almacenPdv, $notificaciones);
        } catch (\Illuminate\Validation\ValidationException $e) {
            if ($request->expectsJson()) { throw $e; }
            return back()->withInput()->withErrors($e->errors())->with('error', $e->validator->errors()->first());
        }
        return redirect()->route('punto-venta.pedidos.show', ['pedido' => $pedido, 'ctx' => \App\Support\UsuarioRol::esMayorista($request->user()) ? 'mayorista' : 'pdv'])->with('success', 'Pedido registrado correctamente.');
    }

    public function show(Request $request, PedidoDistribucion $pedido): View
    {
        abort_unless(PuntoVentaAccess::puedeVerPedido(auth()->user(), $pedido), 403);

        $pedido->load([
            'puntoVenta.minorista',
            'detalles.insumo.unidadMedida',
            'detalles.insumo.almacen',
            'detalles.insumoPlantaReferencia.unidadMedida',
            'detalles.presentacion.tipoEmpaque',
            'almacenMayoristaOrigen',
            'aceptadoPor',
            'creadoPor',
            'transportista',
            'vehiculo.tipoVehiculo',
            'rutaDistribucion.transportista',
            'rutaDistribucion.vehiculo',
            'solicitudesProduccionPlanta.creadoPor',
        ]);

        $user = auth()->user();
        $ruta = $pedido->rutaDistribucion;
        $puedeGestionarMayorista = UsuarioRol::puedeGestionarDistribucionMayorista($user);
        $esMinoristaDueño = UsuarioRol::esMinorista($user)
            && (int) $pedido->puntoVenta?->usuarioid === (int) auth()->id();
        $puedeAnunciarLlegada = false;
        $estadoRecepcionPdv = [];
        $resumenCierrePdv = null;
        if ($ruta !== null && ! $ruta->esTrasladoPlantaMayorista()) {
            $resumenCierrePdv = app(\App\Services\CierreEnvioDistribucionPdvService::class)->resumenPasos($ruta);
            $estadoRecepcionPdv = app(\App\Services\RecepcionPdvMinoristaService::class)->estadoRecepcion($ruta, $pedido);
            $puedeAnunciarLlegada = $esMinoristaDueño && ($estadoRecepcionPdv['puede_firmar'] ?? false);
        } elseif ($esMinoristaDueño && PedidoDistribucionCatalogo::puedeConfirmarRecepcion($pedido)) {
            $puedeAnunciarLlegada = true;
        }

        $pendienteMayorista = PedidoDistribucionCatalogo::pendienteAprobacionMayorista($pedido);
        $pendienteConfirmacionMinorista = PedidoDistribucionCatalogo::pendienteConfirmacionMinorista($pedido);
        $puedeConfirmarEnvioMayorista = $esMinoristaDueño && $pendienteConfirmacionMinorista;
        $puedeDesignarTransportista = $puedeGestionarMayorista
            && PedidoDistribucionCatalogo::puedeDesignarTransportista($pedido);
        $transportistaDesignado = PedidoDistribucionCatalogo::tieneTransportistaDesignado($pedido);
        $puedeEmpezarRuta = $ruta !== null
            && SimulacionRutaCatalogo::usuarioPuedeEmpezarDistribucion($user, $ruta);
        $simulacionActiva = $ruta !== null
            && SimulacionRutaCatalogo::simulacionActivaDistribucion($ruta);
        $esTransportistaAsignado = UsuarioRol::esTransportista($user)
            && (
                (int) $pedido->transportista_usuarioid === (int) $user->usuarioid
                || (int) $ruta?->transportista_usuarioid === (int) $user->usuarioid
            );
        $puedeEditarFlujo = PedidoDistribucionCatalogo::puedeEditarFlujoAntesDeRuta($pedido);
        // Solo el minorista dueño edita su solicitud y solo mientras está pendiente (MIN-04).
        $puedeEditarSolicitud = $esMinoristaDueño && PedidoDistribucionCatalogo::puedeEditarSolicitudMinorista($pedido);
        $puedeReabrirRevision = ($puedeGestionarMayorista ?? false)
            && PedidoDistribucionCatalogo::puedeReabrirRevision($pedido);
        $pasoActualFlujo = PedidoDistribucionCatalogo::pasoActualFlujo($pedido);
        $pasosFlujo = PedidoDistribucionCatalogo::pasosFlujoUi(
            $pedido,
            $esMinoristaDueño,
            $puedeEditarFlujo,
            $transportistaDesignado,
        );
        $mostrarPanelCapacidadVehiculo = PedidoDistribucionCatalogo::mostrarPanelCapacidadVehiculo(
            $pedido,
            $puedeGestionarMayorista,
            $puedeDesignarTransportista,
            $transportistaDesignado,
        );
        $pasoInicial = max(1, min(5, (int) request()->query('paso', 0) ?: $pasoActualFlujo));
        if (! $puedeEditarFlujo && $pasoInicial < $pasoActualFlujo) {
            $pasoInicial = $pasoActualFlujo;
        }

        $erroresStock = ($puedeGestionarMayorista || UsuarioRol::esMinorista($user))
            ? app(PedidoDistribucionMayoristaService::class)->verificarDisponibilidad($pedido)
            : [];

        $esAdmin = UsuarioRol::esAdminGlobal($user);
        $puedeVerRutaTiempoReal = $esAdmin
            || UsuarioRol::esJefeMayorista($user)
            || UsuarioRol::esJefePlanta($user);
        $urlTiempoRealPedido = $simulacionActiva && $ruta
            ? route('logistica.rutas-tiempo-real.show', ['tipo' => 'distribucion', 'id' => $ruta->rutadistribucionid])
            : null;

        $puedeSolicitarProduccionPlanta = false;
        $solicitudActivaPlanta = $pedido->solicitudesProduccionPlanta
            ->sortByDesc('solicitudproduccionplantaid')
            ->first();

        $puedeEliminarSolicitud = $pedido->estado === PedidoDistribucionCatalogo::ESTADO_PENDIENTE
            && $esMinoristaDueño;

        $esBandejaMayorista = PedidoDistribucionVista::esBandejaMayorista($request, $user);
        $ctxVolver = $esBandejaMayorista ? 'mayorista' : 'pdv';

        $capacidadSvc = app(TransporteCapacidadService::class);
        $resumenCargaPedido = [
            'peso_kg' => $capacidadSvc->pesoPedidosDistribucion([$pedido]),
            'volumen_m3' => $capacidadSvc->volumenPedidosDistribucion([$pedido]),
        ];

        return view('punto_venta.pedidos.show', compact(
            'pedido',
            'puedeGestionarMayorista',
            'esMinoristaDueño',
            'puedeAnunciarLlegada',
            'erroresStock',
            'ruta',
            'puedeDesignarTransportista',
            'transportistaDesignado',
            'puedeEmpezarRuta',
            'simulacionActiva',
            'esTransportistaAsignado',
            'puedeEditarFlujo',
            'puedeEditarSolicitud',
            'puedeReabrirRevision',
            'pasoInicial',
            'pasoActualFlujo',
            'esAdmin',
            'puedeVerRutaTiempoReal',
            'urlTiempoRealPedido',
            'puedeSolicitarProduccionPlanta',
            'solicitudActivaPlanta',
            'puedeEliminarSolicitud',
            'esBandejaMayorista',
            'ctxVolver',
            'estadoRecepcionPdv',
            'resumenCierrePdv',
            'resumenCargaPedido',
            'pendienteConfirmacionMinorista',
            'puedeConfirmarEnvioMayorista',
            'pasosFlujo',
            'mostrarPanelCapacidadVehiculo',
        ));
    }

    public function validarCapacidadVehiculo(Request $request, PedidoDistribucion $pedido, TransporteCapacidadService $capacidadSvc): JsonResponse
    {
        abort_unless(PuntoVentaAccess::puedeVerPedido(auth()->user(), $pedido), 403);

        $data = $request->validate([
            'vehiculoid' => 'required|integer|exists:vehiculo,vehiculoid',
        ]);

        $vehiculo = \App\Models\Vehiculo::query()->with('tipoVehiculo')->findOrFail((int) $data['vehiculoid']);
        $pesoKg = $capacidadSvc->pesoPedidosDistribucion([$pedido]);
        $volumenM3 = $capacidadSvc->volumenPedidosDistribucion([$pedido]);
        $cap = $capacidadSvc->capacidadEfectiva($vehiculo);
        $ok = true;
        $mensaje = '';

        try {
            $capacidadSvc->validarCarga($vehiculo, $pesoKg, $volumenM3);
        } catch (InvalidArgumentException $e) {
            $ok = false;
            $mensaje = $e->getMessage();
        }

        $pctKg = $cap['kg'] > 0 ? round(($pesoKg / $cap['kg']) * 100, 1) : null;
        $pctM3 = ($cap['m3'] > 0 && $volumenM3 !== null && $volumenM3 > 0)
            ? round(($volumenM3 / $cap['m3']) * 100, 1)
            : null;
        $pctUso = max($pctKg ?? 0, $pctM3 ?? 0);

        return response()->json([
            'ok' => $ok,
            'mensaje' => $mensaje,
            'capacidad_kg' => $cap['kg'],
            'capacidad_m3' => $cap['m3'],
            'peso_kg' => round($pesoKg, 2),
            'volumen_m3' => $volumenM3 !== null ? round($volumenM3, 3) : null,
            'porcentaje_uso' => $pctUso > 0 ? $pctUso : $pctKg,
            'porcentaje_peso' => $pctKg,
            'porcentaje_volumen' => $pctM3,
            'vehiculo' => $vehiculo->placa,
            'recomendacion' => $ok
                ? 'El vehículo seleccionado cubre peso y volumen de este pedido.'
                : 'Elija otro vehículo o reduzca la cantidad solicitada.',
        ]);
    }

    public function ubicacionPuntoVenta(Request $request, PedidoDistribucion $pedido): View
    {
        return $this->vistaUbicacionContexto($request, $pedido, 'punto-venta');
    }

    public function ubicacionAlmacen(Request $request, PedidoDistribucion $pedido): View
    {
        return $this->vistaUbicacionContexto($request, $pedido, 'almacen');
    }

    private function vistaUbicacionContexto(Request $request, PedidoDistribucion $pedido, string $tipo): View
    {
        abort_unless(PuntoVentaAccess::puedeVerPedido(auth()->user(), $pedido), 403);

        $pedido->load(['puntoVenta', 'almacenMayoristaOrigen', 'detalles.insumo.almacen']);

        $pasoRetorno = max(1, min(5, (int) $request->query('paso', 0) ?: 3));
        $volverUrl = route('punto-venta.pedidos.show', ['pedido' => $pedido, 'paso' => $pasoRetorno]);

        if ($tipo === 'punto-venta') {
            $punto = $pedido->puntoVenta;
            abort_unless($punto, 404);

            $ubicacion = $punto->ubicacionVisible();

            $contexto = [
                'titulo' => 'Punto de venta',
                'nombre' => $punto->nombre,
                'direccion' => $ubicacion['direccion'],
                'estimada' => $ubicacion['estimada'],
                'lat' => $punto->latitud,
                'lng' => $punto->longitud,
                'icono' => 'fa-store',
            ];
        } else {
            $almacen = $pedido->almacenMayoristaOrigen ?? $pedido->detalles->first()?->insumo?->almacen;
            abort_unless($almacen, 404);

            $resuelto = UbicacionGpsParser::resolverAlmacen(
                (int) $almacen->almacenid,
                $almacen->nombre,
                $almacen->ubicacion
            );

            $contexto = [
                'titulo' => 'Origen mayorista',
                'nombre' => $almacen->nombre,
                'direccion' => $resuelto['direccion'] ?: 'Sin ubicación registrada',
                'estimada' => $resuelto['estimada'] ?? false,
                'lat' => $resuelto['lat'],
                'lng' => $resuelto['lng'],
                'icono' => 'fa-warehouse',
            ];
        }

        return view('punto_venta.pedidos.contexto.ubicacion', compact('pedido', 'contexto', 'volverUrl', 'tipo'));
    }

    public function destroy(PedidoDistribucion $pedido): RedirectResponse
    {
        abort_unless(PuntoVentaAccess::puedeVerPedido(auth()->user(), $pedido), 403);

        $user = auth()->user();
        $esMinoristaDueño = UsuarioRol::esMinorista($user)
            && (int) $pedido->puntoVenta?->usuarioid === (int) $user->usuarioid;

        if ($pedido->estado !== PedidoDistribucionCatalogo::ESTADO_PENDIENTE) {
            return back()->with([
                'error' => 'Solo puede eliminar solicitudes que aún no fueron aceptadas por el mayorista.',
                'error_modal' => true,
                'error_modal_titulo' => 'No se puede eliminar',
            ]);
        }

        if (! $esMinoristaDueño) {
            abort(403);
        }

        $pedido->detalles()->delete();
        $pedido->delete();

        return redirect()
            ->route('punto-venta.pedidos.index', ['ctx' => 'pdv'])
            ->with('success', 'Solicitud eliminada.');
    }

    public function aceptar(PedidoDistribucion $pedido): RedirectResponse
    {
        MayoristaAccess::asegurarPuedeVerPedido(auth()->user(), $pedido);
        $data = request()->validate(['motivo_rechazo' => ['nullable', 'string', 'max:500']]);
        try {
            app(\App\Services\PedidoTransicionService::class)->ejecutar($pedido, auth()->user(), 'aceptar', $data['motivo_rechazo'] ?? null);
        } catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) {
            if ($e->getStatusCode() !== 409) { throw $e; }
            return back()->withInput()->with('error', $e->getMessage());
        } catch (InvalidArgumentException $e) {
            return back()->withInput()->with('error', $e->getMessage());
        } catch (ValidationException $e) {
            return back()->withInput()->withErrors($e->errors())->with('error', implode(' ', \Illuminate\Support\Arr::flatten($e->errors())));
        }
        return back()->with('success', 'Pedido actualizado correctamente.');
    }

    public function confirmarEnvioIniciadoMayorista(PedidoDistribucion $pedido, NotificacionUsuarioService $notificaciones): RedirectResponse
    {
        $data = request()->validate(['motivo_rechazo' => ['nullable', 'string', 'max:500']]);
        app(\App\Services\PedidoTransicionService::class)->ejecutar($pedido, auth()->user(), 'confirmar-envio-mayorista', $data['motivo_rechazo'] ?? null);
        return back()->with('success', 'Pedido actualizado correctamente.');
    }

    public function rechazar(Request $request, PedidoDistribucion $pedido): RedirectResponse
    {
        MayoristaAccess::asegurarPuedeVerPedido(auth()->user(), $pedido);
        $data = request()->validate(['motivo_rechazo' => ['nullable', 'string', 'max:500']]);
        try {
            app(\App\Services\PedidoTransicionService::class)->ejecutar($pedido, auth()->user(), 'rechazar', $data['motivo_rechazo'] ?? null);
        } catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) {
            if ($e->getStatusCode() !== 409) { throw $e; }
            return back()->withInput()->with('error', $e->getMessage());
        }
        return back()->with('success', 'Pedido actualizado correctamente.');
    }

    public function designarTransportista(Request $request, PedidoDistribucion $pedido): RedirectResponse
    {
        abort_unless(UsuarioRol::puedeGestionarDistribucionMayorista(auth()->user()), 403);
        MayoristaAccess::asegurarPuedeVerPedido(auth()->user(), $pedido);

        $redirectPedido = route('punto-venta.pedidos.show', [
            'pedido' => $pedido,
            'ctx' => 'mayorista',
            'paso' => 3,
        ]);

        try {
            $data = $request->validate([
                'transportista_usuarioid' => 'required|integer|exists:usuario,usuarioid',
                'vehiculoid' => 'required|integer|exists:vehiculo,vehiculoid',
            ]);
        } catch (ValidationException $e) {
            throw $e->redirectTo($redirectPedido);
        }

        try {
            app(PedidoDistribucionMayoristaService::class)->designarTransportista(
                $pedido,
                (int) $data['transportista_usuarioid'],
                (int) $data['vehiculoid'],
                (int) auth()->id()
            );
        } catch (\Throwable $e) {
            $pedido->refresh();
            if (PedidoDistribucionCatalogo::tieneTransportistaDesignado($pedido)) {
                return redirect()
                    ->route('punto-venta.pedidos.show', [
                        'pedido' => $pedido,
                        'ctx' => 'mayorista',
                        'paso' => 4,
                    ])
                    ->with('success', 'Transportista y vehículo ya estaban asignados.');
            }

            return redirect()
                ->route('punto-venta.pedidos.show', [
                    'pedido' => $pedido,
                    'ctx' => 'mayorista',
                    'paso' => 3,
                ])
                ->withInput()
                ->with([
                    'error' => $e->getMessage(),
                    'error_modal' => true,
                    'error_modal_titulo' => 'No se pudo designar transportista',
                ]);
        }

        return redirect()
            ->route('punto-venta.pedidos.show', [
                'pedido' => $pedido->fresh(),
                'ctx' => 'mayorista',
                'paso' => 4,
            ])
            ->with('success', 'Transportista y vehículo asignados. El chofer debe completar el cierre operativo (condiciones del vehículo, incidentes y firmas) antes de salir en ruta.');
    }

    /** @deprecated Alias de designarTransportista — conserva la ruta histórica. */
    public function marcarEnviado(Request $request, PedidoDistribucion $pedido): RedirectResponse
    {
        return $this->designarTransportista($request, $pedido);
    }

    public function empezarRuta(PedidoDistribucion $pedido, SimulacionRutaService $simulacion): RedirectResponse
    {
        $pedido->loadMissing('rutaDistribucion');
        $ruta = $pedido->rutaDistribucion;
        abort_unless($ruta !== null, 404);

        $user = auth()->user();
        if (! UsuarioRol::puedeMarcarEnRutaDistribucion($user, $ruta)) {
            abort(403);
        }

        try {
            $simulacion->empezarDistribucion($ruta);
        } catch (\InvalidArgumentException $e) {
            if (! app(\App\Services\CierreEnvioDistribucionPdvService::class)->tieneCondicionesVehiculo($ruta)) {
                return redirect()
                    ->route('punto-venta.rutas.cierre.panel', $ruta)
                    ->with('info', 'Registre las condiciones del vehículo en el cierre operativo antes de marcar en ruta.');
            }

            return back()->with('error', $e->getMessage());
        }

        $redirect = redirect()
            ->route('punto-venta.pedidos.show', ['pedido' => $pedido, 'paso' => 4])
            ->with('success', 'Pedido marcado en ruta. El recorrido simulado está en marcha hacia el punto de venta.');

        if (UsuarioRol::esAdminGlobal($user)) {
            $redirect->with(
                'info',
                'Puede seguir el vehículo en tiempo real desde Logística → Ruta en tiempo real.'
            );
        } elseif (UsuarioRol::esTransportista($user)) {
            $redirect->with(
                'info',
                'Recorrido iniciado. Puede seguir su ruta en el panel de transportista.'
            );
        }

        return $redirect;
    }

    public function update(Request $request, PedidoDistribucion $pedido): RedirectResponse
    {
        $request->validate(['estado' => ['missing'], 'decision' => ['missing'], 'motivo_rechazo' => ['missing'], 'aceptado_por_usuarioid' => ['missing'], 'fecha_aceptacion' => ['missing']]);
        abort_unless(PuntoVentaAccess::puedeVerPedido(auth()->user(), $pedido), 403);

        $user = $request->user();
        $esAdmin = UsuarioRol::esAdminGlobal($user);

        $data = $request->validate([
            'puntoventaid' => [$esAdmin ? 'required' : 'nullable', 'integer', 'exists:punto_venta,puntoventaid'],
            'minorista_usuarioid' => [$esAdmin ? 'required' : 'nullable', 'integer', 'exists:usuario,usuarioid'],
            'almacen_mayorista_origenid' => [$esAdmin ? 'required' : 'nullable', 'integer', 'exists:almacen,almacenid'],
            'insumoid' => 'required|integer|exists:insumo,insumoid',
            'cantidad' => 'required|numeric|gt:0',
            'fecha_entrega_deseada' => 'nullable|date',
            'observaciones' => 'nullable|string|max:2000',
        ]);

        try {
            app(PedidoDistribucionMayoristaService::class)->actualizarSolicitud($pedido, $data, $user);
        } catch (\Throwable $e) {
            return back()->withInput()->with('error', $e->getMessage());
        }

        return redirect()
            ->route('punto-venta.pedidos.show', ['pedido' => $pedido, 'paso' => 1])
            ->with('success', 'Solicitud actualizada correctamente.');
    }

    public function reabrirRevision(PedidoDistribucion $pedido): RedirectResponse
    {
        MayoristaAccess::asegurarPuedeVerPedido(auth()->user(), $pedido);
        $data = request()->validate(['motivo_rechazo' => ['nullable', 'string', 'max:500']]);
        app(\App\Services\PedidoTransicionService::class)->ejecutar($pedido, auth()->user(), 'reabrir-revision', $data['motivo_rechazo'] ?? null);
        return back()->with('success', 'Pedido actualizado correctamente.');
    }

    public function confirmarRecepcion(PedidoDistribucion $pedido): RedirectResponse
    {
        abort_unless(PuntoVentaAccess::puedeVerPedido(auth()->user(), $pedido), 403);
        abort_unless(
            UsuarioRol::esMinorista(auth()->user())
            && (int) $pedido->puntoVenta?->usuarioid === (int) auth()->id(),
            403
        );

        // Única vía canónica (MIN-01): la recepción contable ocurre en el cierre con llegada, incidentes
        // y firmas. Este endpoint histórico ya no acredita inventario; solo lleva al cierre.
        $pedido->loadMissing('rutaDistribucion');
        $ruta = $pedido->rutaDistribucion;
        if ($ruta !== null && ! $ruta->esTrasladoPlantaMayorista()) {
            return redirect()
                ->route('punto-venta.rutas.cierre.panel', $ruta)
                ->with('info', 'Use el cierre operativo con firmas para registrar la recepción en punto de venta.');
        }

        return back()->with('error', 'Este pedido no tiene una ruta de entrega: la recepción se registra en el cierre operativo de la ruta.');
    }
}
