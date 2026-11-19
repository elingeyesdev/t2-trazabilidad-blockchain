<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\Almacen;
use App\Models\EnvioAsignacionMultiple;
use App\Models\Pedido;
use App\Models\Insumo;
use App\Models\PuntoVenta;
use App\Models\Usuario;
use App\Models\Vehiculo;
use App\Services\TransporteCapacidadService;
use App\Support\LocalOrgTrackFallback;
use App\Support\MayoristaAccess;
use App\Support\PedidoDistribucionCatalogo;
use App\Support\PuntoVentaAccess;
use App\Services\CostoEnvioRutaService;
use App\Services\NotificacionUsuarioService;
use App\Services\RecepcionPlantaEnvioService;
use App\Support\AlmacenAmbito;
use App\Support\CampoAccess;
use App\Support\EnvioAsignacionEstadoCatalogo;
use App\Support\EnvioListadoService;
use App\Support\EnvioPedidoService;
use App\Support\EnvioTrayectoCatalogo;
use App\Support\PedidoCatalogo;
use App\Support\RutaDistribucionCatalogo;
use App\Support\RutaPorCallesService;
use App\Support\RutaTiempoRealAcceso;
use App\Support\SimulacionRutaCatalogo;
use App\Support\UbicacionGpsParser;
use App\Support\UsuarioRol;
use Illuminate\View\View;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PedidoController extends Controller
{
    public function index(Request $request): View|RedirectResponse
    {
        if ($request->user()?->can('asignaciones.view')) {
            return redirect()->route('logistica.asignaciones.listado', $request->query());
        }

        return view('logistica.envios.index', EnvioListadoService::prepararListado($request));
    }

    public function create()
    {
        $user = request()->user();
        abort_unless(EnvioTrayectoCatalogo::puedeCrearAlguno($user), 403);

        AlmacenAmbito::asegurarAmbitosEnRegistros();

        $trayectosPermitidos = EnvioTrayectoCatalogo::trayectosPermitidos($user);
        $queryDestino = request()->string('destino')->toString() ?: null;
        if ($queryDestino !== null && $queryDestino !== '' && ! EnvioTrayectoCatalogo::puedeUsarTrayecto($user, $queryDestino)) {
            abort(403, 'Su rol no puede registrar envíos de este tipo de trayecto.');
        }
        $destinoInicial = EnvioTrayectoCatalogo::destinoInicialPermitido($user, $queryDestino);

        $numeroSolicitud = PedidoCatalogo::generarNumeroSolicitud();

        $filtroAlmacenesAgricola = CampoAccess::scopeAlmacenesAgricolas(
            Almacen::query()->where('activo', true),
            $user
        )->orderBy('nombre')->get()->map(fn (Almacen $a) => [
            'value' => (string) $a->almacenid,
            'label' => $a->nombre,
        ])->values()->all();

        $filtroAlmacenesPlanta = AlmacenAmbito::scope(
            Almacen::query()->where('activo', true),
            AlmacenAmbito::PLANTA
        )->orderBy('nombre')->get()->map(fn (Almacen $a) => [
            'value' => (string) $a->almacenid,
            'label' => $a->nombre,
        ])->values()->all();

        $partidasAgricolas = [];
        if (UsuarioRol::esJefeAgricultor($user)) {
            $partidasAgricolas = \App\Models\MateriaPrimaLote::whereIn('almacenid', array_column($filtroAlmacenesAgricola, 'value'))
                ->orderBy('materiaprimaloteid')->get()->groupBy('insumoid')->map(function ($filas) {
                    return $filas->filter(fn ($p) => app(\App\Services\InventarioExistenciaService::class)->utilizable($p))
                        ->map(fn ($p) => ['id' => (int)$p->getKey(), 'label' => $p->lote_proveedor ?: 'Partida #'.$p->getKey()])->values()->all();
                })->all();
        }
        return view('pedidos.create', array_merge([
            'partidasAgricolas' => $partidasAgricolas,
            'numeroSolicitud' => $numeroSolicitud,
            'codigoTrasladoPreview' => RutaDistribucionCatalogo::generarCodigoTraslado(),
            'hubLat' => RutaPorCallesService::HUB_LAT,
            'hubLng' => RutaPorCallesService::HUB_LNG,
            'filtroAlmacenesAgricola' => $filtroAlmacenesAgricola,
            'filtroAlmacenesPlanta' => $filtroAlmacenesPlanta,
            'almacenesMapa' => $this->almacenesParaMapaEnvio(),
            'almacenesMapaTraslado' => $this->almacenesParaMapaTraslado(),
            'puntosMapaPdv' => $this->puntosMapaDistribucionPdv(request()->user()),
            'destinoInicial' => $destinoInicial,
            'trayectosPermitidos' => $trayectosPermitidos,
            'mostrarSelectorTrayecto' => count($trayectosPermitidos) > 1,
            'catalogosEmpaque' => [
                'tiposEmpaque' => LocalOrgTrackFallback::tiposEmpaqueCatalogList(),
                'tamanoConteo' => LocalOrgTrackFallback::tamanoConteoCatalogList(),
            ],
        ], $this->datosVistaDistribucionPdv(request()->user())));
    }

    /** @return array<string, mixed> */
    private function datosVistaDistribucionPdv(?Usuario $user): array
    {
        $user = $user ?? auth()->user();
        $esMinorista = $user && UsuarioRol::esMinorista($user);
        $esAdmin = $user && UsuarioRol::esAdminGlobal($user);
        $esMayorista = $user && UsuarioRol::esMayorista($user) && ! $esMinorista && ! $esAdmin;
        $esOrigenMayoristaPdv = $esAdmin || $esMayorista;

        $puntosMinorista = $user
            ? PuntoVentaAccess::scopePuntosDelUsuario(
                PuntoVenta::query()->where('activo', true)->with('minorista')->orderBy('nombre'),
                $user
            )->get()
            : collect();

        return [
            'numeroSolicitudDist' => PedidoDistribucionCatalogo::generarNumeroSolicitud(),
            'puntosMinorista' => $puntosMinorista,
            'esMinoristaPdv' => $esMinorista,
            'esAdminPdv' => $esAdmin,
            'esMayoristaPdv' => $esMayorista,
            'esOrigenMayoristaPdv' => $esOrigenMayoristaPdv,
            'pdvConAsignacion' => $esOrigenMayoristaPdv,
            'oldMinoristaId' => old('minorista_usuarioid'),
            'oldMinoristaLabel' => '',
            'oldPuntoLabel' => '',
            'oldPuntoId' => old('puntoventaid'),
            'oldAlmacenLabel' => '',
            'oldProductoLabel' => '',
            'oldProductoUnidad' => '',
        ];
    }

    /** @return array<int, array<string, mixed>> */
    private function almacenesParaMapaEnvio(): array
    {
        $items = [];
        $user = request()->user();

        $agricolas = CampoAccess::scopeAlmacenesAgricolas(
            Almacen::query()->where('activo', true),
            $user
        )->orderBy('nombre')->get();

        foreach ($agricolas as $almacen) {
            $resuelto = UbicacionGpsParser::resolverAlmacen(
                (int) $almacen->almacenid,
                $almacen->nombre,
                $almacen->ubicacion
            );

            $items[] = [
                'id' => $almacen->almacenid,
                'label' => $almacen->nombre,
                'extra' => [
                    'lat' => $resuelto['lat'],
                    'lng' => $resuelto['lng'],
                    'direccion' => $resuelto['direccion'],
                    'ambito' => $almacen->ambito ?? AlmacenAmbito::AGRICOLA,
                ],
            ];
        }

        $plantas = AlmacenAmbito::scope(
            Almacen::query()->where('activo', true),
            AlmacenAmbito::PLANTA
        )->orderBy('nombre')->get();

        foreach ($plantas as $almacen) {
            $resuelto = UbicacionGpsParser::resolverAlmacen(
                (int) $almacen->almacenid,
                $almacen->nombre,
                $almacen->ubicacion
            );

            $items[] = [
                'id' => $almacen->almacenid,
                'label' => $almacen->nombre,
                'extra' => [
                    'lat' => $resuelto['lat'],
                    'lng' => $resuelto['lng'],
                    'direccion' => $resuelto['direccion'],
                    'ambito' => $almacen->ambito ?? AlmacenAmbito::PLANTA,
                ],
            ];
        }

        return $items;
    }

    /** @return array<int, array<string, mixed>> */
    private function almacenesParaMapaTraslado(): array
    {
        $items = [];

        foreach ([AlmacenAmbito::PLANTA, AlmacenAmbito::MAYORISTA] as $ambito) {
            $almacenes = AlmacenAmbito::scope(
                Almacen::query()->where('activo', true),
                $ambito
            )
                // Destino mayorista solo con dueño que pueda recibirlo (MAY-BUG-01).
                ->when($ambito === AlmacenAmbito::MAYORISTA, fn ($q) => $q->whereHas(
                    'responsable',
                    fn ($r) => $r->where('activo', true)
                        ->whereHas('roles', fn ($rol) => $rol->whereIn('name', ['mayorista', 'jefe_mayorista']))
                ))
                ->orderBy('nombre')
                ->get();

            foreach ($almacenes as $almacen) {
                $resuelto = UbicacionGpsParser::resolverAlmacen(
                    (int) $almacen->almacenid,
                    $almacen->nombre,
                    $almacen->ubicacion
                );
                $items[] = [
                    'id' => $almacen->almacenid,
                    'label' => $almacen->nombre,
                    'extra' => [
                        'lat' => $resuelto['lat'],
                        'lng' => $resuelto['lng'],
                        'direccion' => $resuelto['direccion'],
                        'ambito' => $almacen->ambito ?? $ambito,
                    ],
                ];
            }
        }

        return $items;
    }

    /** @return array<int, array<string, mixed>> */
    private function puntosMapaDistribucionPdv(?Usuario $user): array
    {
        $items = [];

        $mayoristas = AlmacenAmbito::scope(
            Almacen::query()->where('activo', true),
            AlmacenAmbito::MAYORISTA
        )->orderBy('nombre');

        if ($user && UsuarioRol::esMayorista($user) && ! UsuarioRol::esAdminGlobal($user)) {
            $mayoristas = MayoristaAccess::scopeAlmacenesMayorista($mayoristas, $user);
        }

        foreach ($mayoristas->get() as $almacen) {
            $resuelto = UbicacionGpsParser::resolverAlmacen(
                (int) $almacen->almacenid,
                $almacen->nombre,
                $almacen->ubicacion
            );
            $items[] = [
                'id' => $almacen->almacenid,
                'label' => $almacen->nombre,
                'tipo' => 'mayorista',
                'extra' => [
                    'lat' => $resuelto['lat'],
                    'lng' => $resuelto['lng'],
                    'direccion' => $resuelto['direccion'],
                    'ambito' => 'mayorista',
                ],
            ];
        }

        $puntosQuery = PuntoVenta::query()->where('activo', true)->with('minorista')->orderBy('nombre');
        if ($user && UsuarioRol::esMinorista($user) && ! UsuarioRol::esAdminGlobal($user)) {
            $puntosQuery = PuntoVentaAccess::scopePuntosDelUsuario($puntosQuery, $user);
        }

        foreach ($puntosQuery->get() as $pdv) {
            $lat = $pdv->latitud;
            $lng = $pdv->longitud;
            if ($lat === null || $lng === null) {
                $coords = UbicacionGpsParser::fromTexto($pdv->direccion);
                if ($coords === null) {
                    continue;
                }
                $lat = $coords['lat'];
                $lng = $coords['lng'];
            }

            $items[] = [
                'id' => $pdv->puntoventaid,
                'label' => $pdv->nombre,
                'tipo' => 'pdv',
                'extra' => [
                    'lat' => (float) $lat,
                    'lng' => (float) $lng,
                    'direccion' => $pdv->direccion,
                    'minorista_usuarioid' => $pdv->usuarioid,
                    'minorista_nombre' => $pdv->nombreMinorista(),
                ],
            ];
        }

        return $items;
    }

    public function store(Request $request)
    {
        $pedido = app(\App\Services\PedidoAgricolaCreacionService::class)->crear($request);
        return redirect()->route('logistica.asignaciones.listado')->with('success', 'Envío registrado con transportista asignado. Producción agrícola debe aceptarlo para activar la salida.');
    }

    public function show($id)
    {
        \App\Support\PedidoMovilAcceso::asegurar(auth()->user(), Pedido::findOrFail($id));
        $pedido = Pedido::with([
            'detalles',
            'envioAsignacion.transportista.perfilTransportista.vehiculo.tipoVehiculo',
            'envioAsignacion.asignadoPor',
            'envioAsignacion.ruta.paradas',
            'aceptadoPor',
        ])->findOrFail($id);

        $envio = $pedido->envioAsignacion
            ?? EnvioAsignacionMultiple::query()
                ->with([
                    'transportista.perfilTransportista.vehiculo.tipoVehiculo',
                    'asignadoPor',
                    'ruta.paradas',
                ])
                ->where('externo_envio_id', $pedido->numero_solicitud)
                ->first();

        if ($envio !== null) {
            $pedido->setRelation('envioAsignacion', $envio);
        }

        $trayectoPartes = EnvioPedidoService::trayectoPartesPedido($pedido);
        if ($envio !== null) {
            $envio->setRelation('pedido', $pedido);
            $paradasMapa = EnvioPedidoService::paradasMapaEnvio($envio);
            $simulacionActiva = SimulacionRutaCatalogo::simulacionActivaAgricola($envio);
            $urlTiempoReal = ($simulacionActiva && auth()->user() !== null
                && ! UsuarioRol::esTransportista(auth()->user())
                && RutaTiempoRealAcceso::puedeVerEnvioAgricola(auth()->user(), (int) $envio->envioasignacionmultipleid))
                ? route('logistica.rutas-tiempo-real.show', ['tipo' => 'agricola', 'id' => $envio->envioasignacionmultipleid])
                : null;
        } else {
            $paradasMapa = [];
            $simulacionActiva = false;
            $urlTiempoReal = null;
        }

        return view('pedidos.show', compact(
            'pedido',
            'trayectoPartes',
            'paradasMapa',
            'simulacionActiva',
            'urlTiempoReal',
        ));
    }

    public function edit(Pedido $pedido)
    {
        \App\Support\PedidoMovilAcceso::asegurar(auth()->user(), $pedido);
        $pedido->load([
            'detalles',
            'envioAsignacion.transportista.perfilTransportista.vehiculo.tipoVehiculo',
            'envioAsignacion.asignadoPor',
        ]);

        $logistica = EnvioPedidoService::datosLogistica($pedido->envioAsignacion);
        $puedeAsignarLogistica = PedidoCatalogo::puedeAsignarTransportista($pedido);

        return view('pedidos.edit', compact('pedido', 'logistica', 'puedeAsignarLogistica'));
    }

    public function update(Request $request, Pedido $pedido)
    {
        \App\Support\PedidoMovilAcceso::asegurar($request->user(), $pedido);
        if ($request->has('estado') && $request->input('estado') !== $pedido->estado) {
            throw \Illuminate\Validation\ValidationException::withMessages(['estado' => 'Use las acciones de aceptación o rechazo autorizadas para cambiar el estado.']);
        }
        if ($request->has('estado') && ! $request->has('fechaEntregaDeseada') && ! $request->has('observaciones')) {
            $data = $request->validate([
                'estado' => 'required|in:sin asignacion,pendiente,confirmado,en produccion,rechazado',
            ]);

            if (in_array($data['estado'], PedidoCatalogo::estadosListosParaLogistica(), true)
                && PedidoCatalogo::pendienteAprobacionAgricola($pedido)) {
                return back()->with('error', 'Solo producción agrícola puede aceptar el pedido y reservar stock del almacén.');
            }

            // El estado se modifica únicamente mediante las acciones autorizadas.


            return back()->with('success', 'Estado actualizado.');
        }

        $data = $request->validate([
            'nombre_planta' => 'nullable|string|max:255',
            'fechaEntregaDeseada' => 'nullable|date',
            'direccion_texto' => 'nullable|string|max:255',
            'observaciones' => 'nullable|string|max:3000',
            'estado' => 'required|in:sin asignacion,pendiente,confirmado,en produccion,rechazado',
            'transportista_usuarioid' => 'nullable|integer|exists:usuario,usuarioid',
            'vehiculoid' => 'nullable|integer|exists:vehiculo,vehiculoid',
        ]);

        if (in_array($data['estado'], PedidoCatalogo::estadosListosParaLogistica(), true)
            && PedidoCatalogo::pendienteAprobacionAgricola($pedido)) {
            return back()->with('error', 'Solo producción agrícola puede aceptar el pedido y reservar stock del almacén.');
        }

        $transportistaId = isset($data['transportista_usuarioid']) ? (int) $data['transportista_usuarioid'] : 0;
        $vehiculoId = isset($data['vehiculoid']) ? (int) $data['vehiculoid'] : 0;
        unset($data['transportista_usuarioid'], $data['vehiculoid']);

        $pedido->update($data);

        if ($transportistaId > 0 && $vehiculoId > 0 && PedidoCatalogo::puedeAsignarTransportista($pedido)) {
            try {
                EnvioPedidoService::asignarTransportistaYVehiculo(
                    $pedido,
                    $transportistaId,
                    $vehiculoId,
                    (int) auth()->id(),
                    true
                );
            } catch (\InvalidArgumentException $e) {
                return back()->withInput()->with('error', $e->getMessage());
            }
        } elseif ($transportistaId > 0 xor $vehiculoId > 0) {
            return back()->withInput()->with('error', 'Debe seleccionar transportista y vehículo juntos.');
        }

        return redirect()->route('pedidos.show', $pedido)->with('success', 'Pedido actualizado correctamente.');
    }

    public function destroy($id)
    {
        $pedido = Pedido::findOrFail($id);
        \App\Support\PedidoMovilAcceso::asegurar(auth()->user(), $pedido);
        abort_unless(PedidoCatalogo::pendienteAprobacionAgricola($pedido), 409, 'No se puede eliminar un pedido agrícola ya procesado.');
        $pedido->delete();

        return redirect()->route('logistica.asignaciones.listado');
    }

    public function asignarTransportista(Request $request, Pedido $pedido): RedirectResponse
    {
        $data = $request->validate([
            'transportista_usuarioid' => ['required', 'integer', 'exists:usuario,usuarioid'],
            'vehiculoid' => ['required', 'integer', 'exists:vehiculo,vehiculoid'],
            'costo_bs' => ['required', 'integer', 'min:1', 'max:99999999'],
        ]);

        $envio = null;

        try {
            $envio = EnvioPedidoService::asignarTransportistaYVehiculo(
                $pedido,
                (int) $data['transportista_usuarioid'],
                (int) $data['vehiculoid'],
                (int) auth()->id(),
                false,
                (float) $data['costo_bs']
            );
        } catch (\InvalidArgumentException $e) {
            return back()->with('error', $e->getMessage());
        }

        if ($envio) {
            app(NotificacionUsuarioService::class)->envioListoParaRecoger($envio->fresh(['pedido.detalles']));
        }

        $transportista = Usuario::find($data['transportista_usuarioid']);
        $vehiculo = \App\Models\Vehiculo::find($data['vehiculoid']);
        $nombre = trim(($transportista->nombre ?? '').' '.($transportista->apellido ?? ''));

        return back()->with('success', "Transportista {$nombre} asignado con vehículo {$vehiculo->placa} al pedido {$pedido->numero_solicitud}.");
    }

    public function confirmarCargaEnvio(Pedido $pedido): RedirectResponse
    {
        $envio = EnvioAsignacionMultiple::query()
            ->with('pedido')
            ->where(function ($q) use ($pedido) {
                $q->where('pedidoid', $pedido->pedidoid)
                    ->orWhere('externo_envio_id', $pedido->numero_solicitud);
            })
            ->first();

        if (! $envio) {
            return back()->with('error', 'Este pedido no tiene envío registrado.');
        }

        try {
            EnvioPedidoService::confirmarCargaHaciaPlanta($envio);
        } catch (\InvalidArgumentException $e) {
            return back()->with('error', $e->getMessage());
        }

        return back()->with('success', 'Carga confirmada. El envío está en camino hacia planta.');
    }

    public function confirmarLlegadaPlanta(Request $request, Pedido $pedido, RecepcionPlantaEnvioService $recepcionService): RedirectResponse
    {
        abort_unless(
            UsuarioRol::puedeConfirmarRecepcionPlanta($request->user()),
            403,
            'Solo el jefe de planta puede confirmar la recepción.'
        );

        $pedido->loadMissing('detalles');
        $rules = [
            'cantidades' => ['required', 'array', 'min:1'],
        ];
        foreach ($pedido->detalles as $det) {
            $rules['cantidades.'.$det->detallepedidoid] = ['required', 'numeric', 'gt:0'];
        }

        $data = $request->validate($rules, [
            'cantidades.required' => 'Indique la cantidad recibida (pesaje) de cada producto.',
            'cantidades.*.gt' => 'La cantidad recibida debe ser mayor que 0.',
        ]);

        $cantidades = [];
        foreach ($data['cantidades'] as $detalleId => $kg) {
            $cantidades[(int) $detalleId] = $kg;
        }

        try {
            $recepcionService->confirmarDesdePedido($pedido, $request->user(), $cantidades);
        } catch (\InvalidArgumentException $e) {
            return back()->with('error', $e->getMessage())->withInput();
        }

        return back()->with('success', "Pedido {$pedido->numero_solicitud} recibido en planta con pesaje registrado.");
    }

    /**
     * AGR-07 — envío agrícola→planta solo desde almacén propio (CampoAccess).
     * Solo se invoca desde store(), que autoriza exclusivamente TRAYECTO_PLANTA.
     * Pedidos minorista/mayorista/PDV usan PedidoDistribucionController (sin este check).
     *
     * @param  array<string, mixed>  $data
     */
    private function assertAlmacenesAgricolasPropios(?Usuario $user, array $data): void
    {
        if (! $user || UsuarioRol::esAdminGlobal($user)) {
            return;
        }

        $errores = [];
        $ids = [];

        if (! empty($data['origen_almacenid'])) {
            $ids['origen_almacenid'] = (int) $data['origen_almacenid'];
        }

        foreach ($data['recogidas'] ?? [] as $i => $recogida) {
            if (! empty($recogida['almacenid'])) {
                $ids['recogidas.'.$i.'.almacenid'] = (int) $recogida['almacenid'];
            }
        }

        if ($ids === [] && UsuarioRol::gestionaCampo($user)) {
            throw ValidationException::withMessages([
                'origen_almacenid' => 'Debe indicar el almacén agrícola de origen de su equipo.',
            ]);
        }

        foreach ($ids as $campo => $almacenId) {
            $almacen = Almacen::query()->find($almacenId);
            if ($almacen === null || ! CampoAccess::puedeVerAlmacen($user, $almacen)) {
                $errores[$campo] = 'No puede usar un almacén agrícola que no pertenece a su equipo.';
            } elseif (UsuarioRol::esJefeAgricultor($user)
                && ! CampoAccess::puedeGestionarAlmacen($user, $almacen)) {
                $errores[$campo] = 'Solo puede enviar desde un almacén agrícola del que es responsable.';
            }
        }

        if ($errores !== []) {
            throw ValidationException::withMessages($errores);
        }
    }

    public function calcularCostoEnvio(Request $request, CostoEnvioRutaService $costoEnvio): JsonResponse
    {
        $data = $request->validate([
            'paradas' => ['required', 'array', 'min:2'],
            'paradas.*.lat' => ['required', 'numeric', 'between:-90,90'],
            'paradas.*.lng' => ['required', 'numeric', 'between:-180,180'],
            'distancia_m' => ['nullable', 'numeric', 'min:0'],
        ]);

        return response()->json($costoEnvio->calcular(
            $data['paradas'],
            isset($data['distancia_m']) ? (float) $data['distancia_m'] : null
        ));
    }
}
