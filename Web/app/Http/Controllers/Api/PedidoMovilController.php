<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\Api\PedidoMovilResource;
use App\Models\Almacen;
use App\Models\MateriaPrimaLote;
use App\Models\Pedido;
use App\Models\PedidoDistribucion;
use App\Models\PuntoVenta;
use App\Models\Usuario;
use App\Models\Vehiculo;
use App\Services\CargaCalculoService;
use App\Services\CostoEnvioRutaService;
use App\Services\DisponibilidadMayoristaPdvService;
use App\Services\InventarioExistenciaService;
use App\Services\NotificacionUsuarioService;
use App\Services\PedidoAgricolaCreacionService;
use App\Services\PedidoDistribucionCreacionService;
use App\Services\PedidoTransicionService;
use App\Services\PuntoVentaAlmacenService;
use App\Services\TransporteCapacidadService;
use App\Services\VehiculoFlotaEstadoService;
use App\Support\AlmacenAmbito;
use App\Support\CampoAccess;
use App\Support\EnvioTrayectoCatalogo;
use App\Support\EstadoVehiculoCatalogo;
use App\Support\LicenciaConduccionCatalogo;
use App\Support\LocalOrgTrackFallback;
use App\Support\MayoristaAccess;
use App\Support\PedidoCatalogo;
use App\Support\PedidoMovilAcceso;
use App\Support\PuntoVentaAccess;
use App\Support\TransportistaFlotaCatalogo;
use App\Support\TransportistaPool;
use App\Support\UbicacionGpsParser;
use App\Support\UsuarioRol;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;

class PedidoMovilController extends Controller
{
    private function modelo(Request $request): string
    {
        return $request->route('tipo_pedido') === 'distribucion' ? PedidoDistribucion::class : Pedido::class;
    }

    protected function consulta(Request $request)
    {
        $modelo = $this->modelo($request);
        $q = $modelo::query();

        return $modelo === Pedido::class ? PedidoMovilAcceso::agricola($q, $request->user()) : PuntoVentaAccess::scopePedidosDelUsuario($q, $request->user());
    }

    public function index(Request $request)
    {
        $filtros = $request->validate(['per_page' => ['sometimes', 'integer', 'between:1,50'], 'page' => ['sometimes', 'integer', 'min:1'],
            'estado' => ['sometimes', 'string', 'max:40'], 'usuarioid' => ['missing'], 'creado_por_usuarioid' => ['missing']]);
        $query = $this->consulta($request)->with($this->modelo($request) === Pedido::class
            ? ['detalles.cosechaAlmacen.almacen', 'detalles.insumo.almacen', 'envioAsignacion.transportista', 'envioAsignacion.firmaTransportista', 'envioAsignacion.firmaRecepcion', 'ultimaDecision']
            : ['detalles.insumo.almacen', 'puntoVenta', 'ultimaDecision']);
        if (isset($filtros['estado'])) {
            $query->where('estado', $filtros['estado']);
        }

        return PedidoMovilResource::collection($query->orderByDesc('fechapedido')->orderByDesc($query->getModel()->getKeyName())->paginate($filtros['per_page'] ?? 15));
    }

    public function formulario(
        Request $request,
        TransporteCapacidadService $capacidad,
        VehiculoFlotaEstadoService $flotaEstado,
        InventarioExistenciaService $existencias,
        DisponibilidadMayoristaPdvService $catalogoMayorista
    ): JsonResponse {
        $user = $request->user();
        AlmacenAmbito::asegurarAmbitosEnRegistros();

        if ($this->modelo($request) === PedidoDistribucion::class) {
            $puntosVenta = PuntoVentaAccess::scopePuntosDelUsuario(
                PuntoVenta::query()->where('activo', true)->orderBy('nombre'),
                $user
            )->get()->map(fn (PuntoVenta $pv) => [
                'id' => (int) $pv->puntoventaid,
                'nombre' => $pv->nombre,
                'direccion' => $pv->direccion,
            ])->values()->all();

            $mayoristasQuery = AlmacenAmbito::scope(Almacen::query()->where('activo', true), AlmacenAmbito::MAYORISTA)->orderBy('nombre');
            if ($user && UsuarioRol::esMayorista($user) && ! UsuarioRol::esAdminGlobal($user)) {
                $mayoristasQuery = MayoristaAccess::scopeAlmacenesMayorista($mayoristasQuery, $user);
            }
            $almacenesMayoristas = $mayoristasQuery->get()->map(fn (Almacen $a) => [
                'id' => (int) $a->almacenid,
                'nombre' => $a->nombre,
                'direccion' => $a->ubicacion,
            ])->values()->all();

            $productos = $catalogoMayorista->productosConStock()->map(function (array $row) use ($catalogoMayorista) {
                $presentaciones = $catalogoMayorista->presentacionesParaSolicitud(
                    (int) $row['insumoid'],
                    (int) ($row['almacen_mayorista_origenid'] ?? 0) ?: null
                )->map(fn (array $p) => [
                    'id' => (int) $p['insumo_presentacionid'],
                    'nombre' => $p['presentacion_nombre'],
                    'peso_neto_kg' => (float) $p['presentacion']->pesoNetoKg(),
                    'unidad_etiqueta' => $p['unidad'],
                    'stock_unidades' => (float) $p['stock_unidades'],
                    'stock_kg' => (float) $p['stock_kg'],
                ])->values()->all();

                return [
                    'insumoid' => (int) $row['insumoid'],
                    'label' => $row['label'],
                    'almacen_mayorista_origenid' => (int) ($row['almacen_mayorista_origenid'] ?? 0),
                    'almacen_nombre' => $row['almacen_nombre'] ?? '',
                    'stock_kg' => (float) ($row['stock_kg'] ?? 0),
                    'presentaciones' => $presentaciones,
                ];
            })->values()->all();

            return response()->json([
                'data' => [
                    'tipo' => 'distribucion',
                    'puntos_venta' => $puntosVenta,
                    'almacenes_mayoristas' => $almacenesMayoristas,
                    'productos' => $productos,
                ],
            ]);
        }

        EnvioTrayectoCatalogo::autorizarTrayecto($user, EnvioTrayectoCatalogo::TRAYECTO_PLANTA);

        $almacenesOrigenModels = CampoAccess::scopeAlmacenesAgricolas(
            Almacen::query()->where('activo', true),
            $user
        )->orderBy('nombre')->get();

        $almacenesOrigenIds = $almacenesOrigenModels
            ->pluck('almacenid')
            ->map(fn ($id) => (int) $id)
            ->all();

        $mapAlmacen = function (Almacen $a): array {
            $gps = UbicacionGpsParser::resolverAlmacen((int) $a->almacenid, $a->nombre, $a->ubicacion);

            return [
                'id' => (int) $a->almacenid,
                'nombre' => $a->nombre,
                'ubicacion' => $a->ubicacion,
                'direccion' => $gps['direccion'],
                'lat' => (float) $gps['lat'],
                'lng' => (float) $gps['lng'],
            ];
        };

        $almacenesOrigen = $almacenesOrigenModels->map($mapAlmacen)->values()->all();
        $almacenesDestino = AlmacenAmbito::scope(
            Almacen::query()->where('activo', true),
            AlmacenAmbito::PLANTA
        )->orderBy('nombre')->get()->map($mapAlmacen)->values()->all();

        $partidasPorInsumo = $almacenesOrigenIds === []
            ? collect()
            : MateriaPrimaLote::query()
                ->whereIn('almacenid', $almacenesOrigenIds)
                ->orderBy('materiaprimaloteid')
                ->get()
                ->groupBy('insumoid')
                ->map(fn ($filas) => $filas
                    ->filter(fn ($p) => $existencias->utilizable($p))
                    ->map(fn ($p) => [
                        'id' => (int) $p->getKey(),
                        'label' => $p->lote_proveedor ?: 'Partida #'.$p->getKey(),
                        'cantidad_disponible' => (float) $p->cantidad_disponible,
                    ])
                    ->values()
                    ->all());

        $productos = [];
        foreach (PedidoCatalogo::cosechasAgricolasDisponibles() as $cosecha) {
            if (! in_array((int) $cosecha->almacenid, $almacenesOrigenIds, true)) {
                continue;
            }
            $ref = 'cosecha:'.$cosecha->produccionalmacenamientoid;
            $stockKg = (float) (PedidoCatalogo::stockDisponibleProductoPedido($ref, (int) $cosecha->almacenid) ?? 0.0);
            if ($stockKg <= 0) {
                continue;
            }
            $cultivo = $cosecha->produccion?->lote?->cultivo?->nombre ?? 'Cultivo';
            $lote = $cosecha->produccion?->lote?->nombre ?? 'Lote';
            $productos[] = [
                'producto_ref' => $ref,
                'tipo' => 'cosecha',
                'label' => PedidoCatalogo::etiquetaCosechaSelector($cultivo, $lote),
                'almacenid' => (int) $cosecha->almacenid,
                'almacen_nombre' => $cosecha->almacen?->nombre ?? 'Almacén agrícola',
                'stock_kg' => round($stockKg, 2),
                'unidad' => 'kg',
                'calibre_default_id' => PedidoCatalogo::calibreSugeridoIdParaProducto($ref),
                'calibres' => PedidoCatalogo::listarCalibresParaProducto($ref),
                'partidas' => [],
            ];
        }

        foreach (PedidoCatalogo::insumosMaterialSiembraGlobales() as $insumo) {
            if (! in_array((int) $insumo->almacenid, $almacenesOrigenIds, true)) {
                continue;
            }
            if ((float) $insumo->stock <= 0) {
                continue;
            }
            $ref = 'insumo:'.$insumo->insumoid;
            $stockKg = (float) (PedidoCatalogo::stockDisponibleProductoPedido($ref, (int) $insumo->almacenid) ?? 0.0);
            if ($stockKg <= 0) {
                continue;
            }
            $productos[] = [
                'producto_ref' => $ref,
                'tipo' => 'insumo',
                'label' => $insumo->nombre,
                'almacenid' => (int) $insumo->almacenid,
                'almacen_nombre' => $insumo->almacen?->nombre ?? 'Almacén agrícola',
                'stock_kg' => round($stockKg, 2),
                'unidad' => 'kg',
                'calibre_default_id' => PedidoCatalogo::calibreSugeridoIdParaProducto($ref),
                'calibres' => PedidoCatalogo::listarCalibresParaProducto($ref),
                'partidas' => $partidasPorInsumo->get($insumo->insumoid, []),
            ];
        }

        $mapaEnRuta = $flotaEstado->mapaEnRuta();
        $vehiculosModels = Vehiculo::query()
            ->with(['tipoVehiculo', 'estadoVehiculo', 'tiposTransporte'])
            ->where('activo', true)
            ->where('ambito_flota', TransportistaFlotaCatalogo::AGRICOLA)
            ->orderBy('placa')
            ->get()
            ->filter(fn (Vehiculo $v) => EstadoVehiculoCatalogo::disponibleParaUso($v) && ! $flotaEstado->estaEnRuta($v, $mapaEnRuta))
            ->values();

        $vehiculos = $vehiculosModels->map(function (Vehiculo $v) use ($capacidad) {
            $cap = $capacidad->capacidadEfectiva($v);

            return [
                'id' => (int) $v->vehiculoid,
                'placa' => $v->placa,
                'marca' => $v->marca,
                'modelo' => $v->modelo,
                'tipo_vehiculo' => $v->tipoVehiculo?->nombre,
                'capacidad_kg' => $cap['kg'],
                'capacidad_m3' => $cap['m3'],
                'licencia_requerida' => $cap['licencia_requerida'],
                'transporte_principal' => $v->tiposTransporte->first()?->nombre ?? 'Carga general',
            ];
        })->values()->all();

        $transportistas = TransportistaPool::scopePool(Usuario::query(), TransportistaFlotaCatalogo::AGRICOLA)
            ->with('perfilTransportista.vehiculo')
            ->orderBy('nombre')
            ->orderBy('apellido')
            ->get()
            ->map(function (Usuario $t) use ($capacidad, $vehiculos) {
                $licencias = $capacidad->licenciasTransportista($t);
                $compatibles = array_values(array_map(
                    fn (array $v) => $v['id'],
                    array_filter(
                        $vehiculos,
                        fn (array $v) => LicenciaConduccionCatalogo::puedeConducirConLicencias($licencias, $v['licencia_requerida'])
                    )
                ));

                return [
                    'id' => (int) $t->usuarioid,
                    'nombre' => trim($t->nombre.' '.($t->apellido ?? '')),
                    'licencias' => $licencias,
                    'vehiculo_default_id' => $t->perfilTransportista?->vehiculoid ? (int) $t->perfilTransportista->vehiculoid : null,
                    'vehiculos_compatibles' => $compatibles,
                ];
            })->values()->all();

        return response()->json([
            'data' => [
                'tipo' => 'agricola',
                'almacenes_origen' => $almacenesOrigen,
                'almacenes_destino' => $almacenesDestino,
                'productos' => $productos,
                'tipos_empaque' => LocalOrgTrackFallback::tiposEmpaqueCatalogList(),
                'transportistas' => $transportistas,
                'vehiculos' => $vehiculos,
            ],
        ]);
    }

    public function calcularCosto(Request $request, CostoEnvioRutaService $costoEnvio): JsonResponse
    {
        $data = $request->validate([
            'paradas' => ['required', 'array', 'min:2'],
            'paradas.*.lat' => ['required', 'numeric', 'between:-90,90'],
            'paradas.*.lng' => ['required', 'numeric', 'between:-180,180'],
            'distancia_m' => ['nullable', 'numeric', 'min:0'],
        ]);

        return response()->json([
            'data' => $costoEnvio->calcular(
                $data['paradas'],
                isset($data['distancia_m']) ? (float) $data['distancia_m'] : null
            ),
        ]);
    }

    public function validarCapacidad(Request $request, TransporteCapacidadService $service): JsonResponse
    {
        $data = $request->validate([
            'vehiculo_id' => ['required', 'integer', 'exists:vehiculo,vehiculoid'],
            'peso_kg' => ['required', 'numeric', 'min:0'],
            'volumen_m3' => ['nullable', 'numeric', 'min:0'],
        ]);

        $vehiculo = Vehiculo::query()->findOrFail((int) $data['vehiculo_id']);
        $pesoKg = (float) $data['peso_kg'];
        $volumenM3 = isset($data['volumen_m3'])
            ? (float) $data['volumen_m3']
            : $service->volumenDesdePeso($pesoKg);

        $cap = $service->capacidadEfectiva($vehiculo);
        $ok = true;
        $mensaje = '';

        try {
            $service->validarCarga($vehiculo, $pesoKg, $volumenM3);
        } catch (InvalidArgumentException $e) {
            $ok = false;
            $mensaje = $e->getMessage();
        }

        return response()->json([
            'data' => [
                'ok' => $ok,
                'mensaje' => $mensaje,
                'capacidad_kg' => $cap['kg'],
                'capacidad_m3' => $cap['m3'],
                'peso_kg' => round($pesoKg, 2),
                'volumen_m3' => round($volumenM3, 2),
                'porcentaje_peso' => $cap['kg'] > 0 ? round(($pesoKg / $cap['kg']) * 100, 1) : null,
                'porcentaje_volumen' => $cap['m3'] > 0 ? round(($volumenM3 / $cap['m3']) * 100, 1) : null,
                'vehiculo' => $vehiculo->placa,
            ],
        ]);
    }

    public function calcularCarga(Request $request, CargaCalculoService $service): JsonResponse
    {
        if ($request->filled('catalogo_tamano_conteo_id')) {
            $resultado = $service->desdeCatalogos(
                (int) $request->input('catalogo_tamano_conteo_id'),
                $request->filled('tipo_empaque_id') ? (int) $request->input('tipo_empaque_id') : null,
                (string) $request->input('forma_pedido', 'empaques'),
                (float) $request->input('cantidad_pedido', 0)
            );
        } else {
            $resultado = $service->calcular($request->only([
                'conteo_por_empaque',
                'peso_promedio_kg',
                'largo_cm',
                'ancho_cm',
                'alto_cm',
                'tara_kg',
                'capacidad_unidades',
                'unidades_por_pallet',
                'forma_pedido',
                'cantidad_pedido',
            ]));
        }

        return response()->json(['data' => $resultado]);
    }

    public function show(Request $request, string $pedido)
    {
        $modelo = $this->consulta($request)->findOrFail($pedido);

        return $this->recurso($modelo);
    }

    private function recurso($pedido): PedidoMovilResource
    {
        return new PedidoMovilResource($pedido->load($pedido instanceof Pedido
            ? ['detalles.cosechaAlmacen.almacen', 'detalles.insumo.almacen', 'envioAsignacion.transportista', 'envioAsignacion.firmaTransportista', 'envioAsignacion.firmaRecepcion', 'ultimaDecision']
            : ['detalles.insumo.almacen', 'puntoVenta', 'ultimaDecision']));
    }

    public function store(Request $request)
    {
        try {
            $pedido = $this->modelo($request) === Pedido::class ? app(PedidoAgricolaCreacionService::class)->crear($request)
                : app(PedidoDistribucionCreacionService::class)->crear($request, app(DisponibilidadMayoristaPdvService::class), app(PuntoVentaAlmacenService::class), app(NotificacionUsuarioService::class));
        } catch (\InvalidArgumentException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
        }

        return $this->recurso($pedido)->response()->setStatusCode(201);
    }

    public function transicion(Request $request, string $pedido, PedidoTransicionService $service)
    {
        $data = $request->validate(['accion' => ['required', 'string', 'in:aceptar,rechazar,reabrir-revision,confirmar-envio-mayorista'], 'motivo_rechazo' => ['required_if:accion,rechazar', 'nullable', 'string', 'max:500'],
            'usuarioid' => ['missing'], 'fecha' => ['missing'], 'fecha_aceptacion' => ['missing'], 'fecha_aceptacion_agricola' => ['missing'], 'decision' => ['missing'], 'reservado' => ['missing'], 'acciones_disponibles' => ['missing'], 'estado' => ['missing'], 'detalles' => ['missing'], 'puntoventaid' => ['missing'], 'creado_por_usuarioid' => ['missing'], 'aceptado_por_usuarioid' => ['missing'], 'cantidad' => ['missing']]);
        $actual = $this->consulta($request)->findOrFail($pedido);
        try {
            return $this->recurso($service->ejecutar($actual, $request->user(), $data['accion'], $data['motivo_rechazo'] ?? null));
        } catch (\InvalidArgumentException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['detalles' => $e->getMessage()]);
        }
    }

    public function update(Request $request, string $pedido)
    {
        $this->consulta($request)->findOrFail($pedido);
        throw \Illuminate\Validation\ValidationException::withMessages(['estado' => 'Use la acción autorizada de cambio de estado; esta API no admite reemplazar libremente el pedido.']);
    }

    public function destroy(Request $request, string $pedido)
    {
        $this->consulta($request)->findOrFail($pedido);
        abort(409, 'La eliminación genérica no está disponible; utilice las acciones autorizadas del pedido.');
    }
}
