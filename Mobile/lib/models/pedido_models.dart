import 'auth_user.dart';

enum PedidoTipo {
  agricola('agricola', 'pedidos-agricolas', 'Agrícola'),
  distribucion('distribucion', 'pedidos-distribucion', 'Distribución');

  const PedidoTipo(this.value, this.endpoint, this.label);

  final String value;
  final String endpoint;
  final String label;

  static PedidoTipo? fromValue(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final tipo in values) {
      if (tipo.value == normalized) return tipo;
    }
    return null;
  }
}

abstract final class PedidoPermissions {
  static bool canViewAgricola(AuthUser user) =>
      user.permissions.contains('pedidos.view');

  static bool canViewDistribucion(AuthUser user) =>
      user.permissions.contains('pedidos_distribucion.view');

  static bool canViewAny(AuthUser user) =>
      canViewAgricola(user) || canViewDistribucion(user);

  static bool canCreateAgricola(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('pedidos.create') &&
      user.roles.any(const {'jefe_agricultor', 'jefe_agricola'}.contains);

  static bool canCreateDistribucion(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('pedidos_distribucion.create') &&
      user.roles.any(
        const {'minorista', 'mayorista', 'jefe_mayorista'}.contains,
      );

  static bool canCreateAny(AuthUser user) =>
      canCreateAgricola(user) || canCreateDistribucion(user);
}

class PedidoDetalleLinea {
  const PedidoDetalleLinea({
    required this.id,
    required this.producto,
    required this.cantidad,
    this.productoRef,
    this.insumoId,
    this.materiaPrimaLoteId,
    this.produccionAlmacenamientoId,
    this.presentacionId,
    this.presentacion,
    this.unidad,
    this.cantidadKg,
    this.almacenOrigenId,
    this.inventarioPresentacionLoteId,
  });

  factory PedidoDetalleLinea.fromJson(Map<String, dynamic> row) =>
      PedidoDetalleLinea(
        id: _asInt(row['id']) ?? 0,
        producto: _asText(row['producto']) ?? 'Producto',
        cantidad: _asText(row['cantidad']) ?? '0',
        productoRef: _asText(row['producto_ref']),
        insumoId: _asInt(row['insumoid']),
        materiaPrimaLoteId: _asInt(row['materiaprimaloteid']),
        produccionAlmacenamientoId: _asInt(row['produccionalmacenamientoid']),
        presentacionId: _asInt(row['presentacionid']),
        presentacion: _asText(row['presentacion']),
        unidad: _asText(row['unidad']),
        cantidadKg: _asText(row['cantidad_kg']),
        almacenOrigenId: _asInt(row['almacen_origenid']),
        inventarioPresentacionLoteId: _asInt(
          row['inventario_presentacion_loteid'],
        ),
      );

  final int id;
  final String producto;
  final String cantidad;
  final String? productoRef;
  final int? insumoId;
  final int? materiaPrimaLoteId;
  final int? produccionAlmacenamientoId;
  final int? presentacionId;
  final String? presentacion;
  final String? unidad;
  final String? cantidadKg;
  final int? almacenOrigenId;
  final int? inventarioPresentacionLoteId;

  String get title =>
      presentacion != null ? '$producto · $presentacion' : producto;

  String get formattedCantidad {
    final amount = _formatDecimalText(cantidad);
    return unidad != null ? '$amount $unidad' : amount;
  }

  String? get formattedKg =>
      cantidadKg == null ? null : '${_formatDecimalText(cantidadKg!)} kg';
}

class PedidoDestino {
  const PedidoDestino({
    this.puntoVentaId,
    this.nombre,
    this.direccion,
    this.latitud,
    this.longitud,
  });

  factory PedidoDestino.fromJson(Object? json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    return PedidoDestino(
      puntoVentaId: _asInt(map['puntoventaid']),
      nombre: _asText(map['nombre']),
      direccion: _asText(map['direccion']),
      latitud: _asText(map['latitud']),
      longitud: _asText(map['longitud']),
    );
  }

  final int? puntoVentaId;
  final String? nombre;
  final String? direccion;
  final String? latitud;
  final String? longitud;

  String get label {
    if (nombre != null) {
      return puntoVentaId != null ? '$nombre (PDV #$puntoVentaId)' : nombre!;
    }
    if (puntoVentaId != null) return 'Punto de venta #$puntoVentaId';
    if (direccion != null) return direccion!;
    if (latitud != null && longitud != null) return '$latitud, $longitud';
    return 'Destino sin especificar';
  }
}

class PedidoEnvioInfo {
  const PedidoEnvioInfo({
    required this.id,
    this.externoEnvioId,
    this.estado,
    this.transportistaUsuarioId,
    this.transportistaNombre,
    this.vehiculoPlaca,
    this.costoBs,
    this.fechaRecepcionPlanta,
  });

  factory PedidoEnvioInfo.fromJson(Map<String, dynamic> map) => PedidoEnvioInfo(
    id: _asInt(map['id']) ?? 0,
    externoEnvioId: _asText(map['externo_envio_id']),
    estado: _asText(map['estado']),
    transportistaUsuarioId: _asInt(map['transportista_usuarioid']),
    transportistaNombre: _asText(map['transportista_nombre']),
    vehiculoPlaca: _asText(map['vehiculo_placa']),
    costoBs: _asDouble(map['costo_bs']),
    fechaRecepcionPlanta: _asText(map['fecha_recepcion_planta']),
  );

  final int id;
  final String? externoEnvioId;
  final String? estado;
  final int? transportistaUsuarioId;
  final String? transportistaNombre;
  final String? vehiculoPlaca;
  final double? costoBs;
  final String? fechaRecepcionPlanta;
}

class PedidoDecision {
  const PedidoDecision({
    this.accion,
    this.estadoResultante,
    this.motivo,
    this.usuarioId,
    this.fecha,
  });

  factory PedidoDecision.fromJson(Map<String, dynamic> map) => PedidoDecision(
    accion: _asText(map['accion']),
    estadoResultante: _asText(map['estado_resultante']),
    motivo: _asText(map['motivo']),
    usuarioId: _asInt(map['usuarioid']),
    fecha: _asText(map['fecha']),
  );

  final String? accion;
  final String? estadoResultante;
  final String? motivo;
  final int? usuarioId;
  final String? fecha;
}

class PedidoRecord {
  const PedidoRecord({
    required this.tipo,
    required this.id,
    required this.numeroSolicitud,
    required this.estado,
    required this.destino,
    this.origen,
    this.fecha,
    this.fechaEntregaDeseada,
    this.horaRecogida,
    this.horaEntregaEstimada,
    this.instruccionesRecogida,
    this.instruccionesEntrega,
    this.creadoPorUsuarioId,
    this.aceptadoPorUsuarioId,
    this.fechaAceptacion,
    this.envioIniciadoMayorista,
    this.fechaConfirmacionMinorista,
    this.fechaEnvio,
    this.fechaRecepcion,
    this.envio,
    this.observaciones,
    this.decision,
    this.motivoRechazo,
    this.accionesDisponibles = const [],
    this.detalles = const [],
  });

  factory PedidoRecord.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    final tipo =
        PedidoTipo.fromValue(_asText(root['tipo'])) ?? PedidoTipo.distribucion;
    final id = _asInt(root['id']) ?? 0;
    final detallesRaw = root['detalles'];
    final detalles = <PedidoDetalleLinea>[];
    if (detallesRaw is List) {
      for (final entry in detallesRaw) {
        if (entry is Map<String, dynamic>) {
          detalles.add(PedidoDetalleLinea.fromJson(entry));
        }
      }
    }
    final accionesRaw = root['acciones_disponibles'];
    final acciones = <String>[];
    if (accionesRaw is List) {
      for (final item in accionesRaw) {
        final text = _asText(item);
        if (text != null) acciones.add(text);
      }
    }
    return PedidoRecord(
      tipo: tipo,
      id: id,
      numeroSolicitud:
          _asText(root['numero_solicitud']) ?? 'Pedido ${tipo.label} #$id',
      estado: (_asText(root['estado']) ?? 'pendiente').toLowerCase(),
      destino: PedidoDestino.fromJson(root['destino']),
      origen: root['origen'] is Map<String, dynamic>
          ? PedidoDestino.fromJson(root['origen'])
          : null,
      fecha: _asText(root['fecha']),
      fechaEntregaDeseada: _asText(root['fecha_entrega_deseada']),
      horaRecogida: _asText(root['hora_recogida']),
      horaEntregaEstimada: _asText(root['hora_entrega_estimada']),
      instruccionesRecogida: _asText(root['instrucciones_recogida']),
      instruccionesEntrega: _asText(root['instrucciones_entrega']),
      creadoPorUsuarioId: _asInt(root['creado_por_usuarioid']),
      aceptadoPorUsuarioId: _asInt(root['aceptado_por_usuarioid']),
      fechaAceptacion: _asText(root['fecha_aceptacion']),
      envioIniciadoMayorista: root['envio_iniciado_mayorista'] is bool
          ? root['envio_iniciado_mayorista'] as bool
          : null,
      fechaConfirmacionMinorista: _asText(root['fecha_confirmacion_minorista']),
      fechaEnvio: _asText(root['fecha_envio']),
      fechaRecepcion: _asText(root['fecha_recepcion']),
      envio: root['envio'] is Map<String, dynamic>
          ? PedidoEnvioInfo.fromJson(root['envio'] as Map<String, dynamic>)
          : null,
      observaciones: _asText(root['observaciones']),
      decision: root['decision'] is Map<String, dynamic>
          ? PedidoDecision.fromJson(root['decision'] as Map<String, dynamic>)
          : null,
      motivoRechazo: _asText(root['motivo_rechazo']),
      accionesDisponibles: acciones,
      detalles: detalles,
    );
  }

  final PedidoTipo tipo;
  final int id;
  final String numeroSolicitud;
  final String estado;
  final PedidoDestino destino;
  final PedidoDestino? origen;
  final String? fecha;
  final String? fechaEntregaDeseada;
  final String? horaRecogida;
  final String? horaEntregaEstimada;
  final String? instruccionesRecogida;
  final String? instruccionesEntrega;
  final int? creadoPorUsuarioId;
  final int? aceptadoPorUsuarioId;
  final String? fechaAceptacion;
  final bool? envioIniciadoMayorista;
  final String? fechaConfirmacionMinorista;
  final String? fechaEnvio;
  final String? fechaRecepcion;
  final PedidoEnvioInfo? envio;
  final String? observaciones;
  final PedidoDecision? decision;
  final String? motivoRechazo;
  final List<String> accionesDisponibles;
  final List<PedidoDetalleLinea> detalles;

  String get estadoLabel => switch (estado) {
    'pendiente' => 'Pendiente',
    'sin asignacion' => 'Sin asignación',
    'confirmado' => 'Confirmado',
    'rechazado' => 'Rechazado',
    'en_transito' => 'En tránsito',
    'recibido' => 'Recibido',
    'entregado' => 'Entregado',
    _ => estado,
  };
}

class PedidosPage {
  const PedidosPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  factory PedidosPage.fromJson(Object? json) {
    final rows = json is List
        ? json
        : json is Map<String, dynamic> && json['data'] is List
        ? json['data'] as List
        : const [];
    final items = <PedidoRecord>[];
    for (final entry in rows) {
      if (entry is Map<String, dynamic>) {
        final item = PedidoRecord.fromJson(entry);
        if (item.id > 0) items.add(item);
      }
    }
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final meta = map['meta'] is Map<String, dynamic>
        ? map['meta'] as Map<String, dynamic>
        : map;
    return PedidosPage(
      items: items,
      currentPage: _asInt(meta['current_page']) ?? 1,
      lastPage: _asInt(meta['last_page']) ?? 1,
    );
  }

  final List<PedidoRecord> items;
  final int currentPage;
  final int lastPage;
}

String pedidoAccionLabel(String accion) => switch (accion) {
  'aceptar' => 'Aceptar pedido',
  'rechazar' => 'Rechazar pedido',
  'reabrir-revision' => 'Reabrir revisión',
  'confirmar-envio-mayorista' => 'Confirmar envío de mayorista',
  _ => accion,
};

String? validatePedidoQuantity(String? raw, {required String unitLabel}) {
  final normalized = (raw ?? '').trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return 'Indica la cantidad ($unitLabel).';
  }
  if (!RegExp(
    r'^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$',
  ).hasMatch(normalized)) {
    return 'Indica una cantidad positiva con hasta seis decimales.';
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) {
    return 'La cantidad debe ser mayor que cero.';
  }
  return null;
}

String _formatDecimalText(String raw) {
  final trimmed = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$').hasMatch(trimmed)) return trimmed;
  if (!trimmed.contains('.')) return trimmed;
  return trimmed.replaceFirst(RegExp(r'\.?0+$'), '');
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _asText(Object? value) {
  if (value == null) return null;
  if (value is! String && value is! num) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim().replaceAll(',', '.'));
  return null;
}

class PedidoAlmacenOption {
  const PedidoAlmacenOption({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.lat,
    required this.lng,
    this.ubicacion,
  });

  factory PedidoAlmacenOption.fromJson(Map<String, dynamic> map) =>
      PedidoAlmacenOption(
        id: _asInt(map['id']) ?? 0,
        nombre: _asText(map['nombre']) ?? 'Almacén',
        ubicacion: _asText(map['ubicacion']),
        direccion:
            _asText(map['direccion']) ??
            _asText(map['ubicacion']) ??
            _asText(map['nombre']) ??
            '',
        lat: _asDouble(map['lat']) ?? 0,
        lng: _asDouble(map['lng']) ?? 0,
      );

  final int id;
  final String nombre;
  final String? ubicacion;
  final String direccion;
  final double lat;
  final double lng;
}

class PedidoCalibreOption {
  const PedidoCalibreOption({
    required this.id,
    required this.nombre,
    this.idProducto,
    this.conteoPorEmpaque = 0,
    this.pesoPromedioKg = 0,
    this.tipoEmpaqueId,
    this.tipoEmpaqueNombre,
  });

  factory PedidoCalibreOption.fromJson(Map<String, dynamic> map) =>
      PedidoCalibreOption(
        id: _asInt(map['id']) ?? 0,
        idProducto: _asInt(map['id_producto']),
        nombre: _asText(map['nombre']) ?? 'Estándar',
        conteoPorEmpaque: _asInt(map['conteo_por_empaque']) ?? 0,
        pesoPromedioKg: _asDouble(map['peso_promedio_kg']) ?? 0,
        tipoEmpaqueId: _asInt(map['id_tipo_empaque']),
        tipoEmpaqueNombre: _asText(map['tipo_empaque']),
      );

  final int id;
  final int? idProducto;
  final String nombre;
  final int conteoPorEmpaque;
  final double pesoPromedioKg;
  final int? tipoEmpaqueId;
  final String? tipoEmpaqueNombre;

  double get pesoPorEmpaqueKg =>
      conteoPorEmpaque > 0 && pesoPromedioKg > 0
      ? conteoPorEmpaque * pesoPromedioKg
      : 0;
}

class PedidoPartidaOption {
  const PedidoPartidaOption({
    required this.id,
    required this.label,
    required this.cantidadDisponible,
  });

  factory PedidoPartidaOption.fromJson(Map<String, dynamic> map) =>
      PedidoPartidaOption(
        id: _asInt(map['id']) ?? 0,
        label: _asText(map['label']) ?? 'Partida',
        cantidadDisponible: _asDouble(map['cantidad_disponible']) ?? 0,
      );

  final int id;
  final String label;
  final double cantidadDisponible;
}

class PedidoProductoAgricolaOption {
  const PedidoProductoAgricolaOption({
    required this.productoRef,
    required this.tipo,
    required this.label,
    required this.almacenId,
    required this.almacenNombre,
    required this.stockKg,
    this.unidad = 'kg',
    this.calibreDefaultId,
    this.calibres = const [],
    this.partidas = const [],
  });

  factory PedidoProductoAgricolaOption.fromJson(Map<String, dynamic> map) {
    final calibresRaw = map['calibres'];
    final calibres = <PedidoCalibreOption>[
      if (calibresRaw is List)
        for (final entry in calibresRaw)
          if (entry is Map<String, dynamic>)
            PedidoCalibreOption.fromJson(entry),
    ];
    final partidasRaw = map['partidas'];
    final partidas = <PedidoPartidaOption>[
      if (partidasRaw is List)
        for (final entry in partidasRaw)
          if (entry is Map<String, dynamic>)
            PedidoPartidaOption.fromJson(entry),
    ];
    return PedidoProductoAgricolaOption(
      productoRef: _asText(map['producto_ref']) ?? '',
      tipo: _asText(map['tipo']) ?? 'cosecha',
      label: _asText(map['label']) ?? 'Producto',
      almacenId: _asInt(map['almacenid']) ?? 0,
      almacenNombre: _asText(map['almacen_nombre']) ?? 'Almacén agrícola',
      stockKg: _asDouble(map['stock_kg']) ?? 0,
      unidad: _asText(map['unidad']) ?? 'kg',
      calibreDefaultId: _asInt(map['calibre_default_id']),
      calibres: calibres,
      partidas: partidas,
    );
  }

  final String productoRef;
  final String tipo;
  final String label;
  final int almacenId;
  final String almacenNombre;
  final double stockKg;
  final String unidad;
  final int? calibreDefaultId;
  final List<PedidoCalibreOption> calibres;
  final List<PedidoPartidaOption> partidas;

  int? get insumoId {
    if (!productoRef.startsWith('insumo:')) return null;
    return int.tryParse(productoRef.substring(7));
  }
}

class PedidoTipoEmpaqueOption {
  const PedidoTipoEmpaqueOption({required this.id, required this.nombre});

  factory PedidoTipoEmpaqueOption.fromJson(Map<String, dynamic> map) =>
      PedidoTipoEmpaqueOption(
        id: _asInt(map['id']) ?? 0,
        nombre: _asText(map['nombre']) ?? 'Empaque',
      );

  final int id;
  final String nombre;
}

class PedidoTransportistaOption {
  const PedidoTransportistaOption({
    required this.id,
    required this.nombre,
    this.licencias = const [],
    this.vehiculoDefaultId,
    this.vehiculosCompatibles = const [],
  });

  factory PedidoTransportistaOption.fromJson(Map<String, dynamic> map) {
    final licRaw = map['licencias'];
    final vehRaw = map['vehiculos_compatibles'];
    return PedidoTransportistaOption(
      id: _asInt(map['id']) ?? 0,
      nombre: _asText(map['nombre']) ?? 'Transportista',
      licencias: [
        if (licRaw is List)
          for (final item in licRaw) ?_asText(item),
      ],
      vehiculoDefaultId: _asInt(map['vehiculo_default_id']),
      vehiculosCompatibles: [
        if (vehRaw is List)
          for (final item in vehRaw) ?_asInt(item),
      ],
    );
  }

  final int id;
  final String nombre;
  final List<String> licencias;
  final int? vehiculoDefaultId;
  final List<int> vehiculosCompatibles;
}

class PedidoVehiculoOption {
  const PedidoVehiculoOption({
    required this.id,
    required this.placa,
    this.marca,
    this.modelo,
    this.tipoVehiculo,
    this.capacidadKg = 0,
    this.capacidadM3 = 0,
    this.licenciaRequerida,
    this.transportePrincipal,
  });

  factory PedidoVehiculoOption.fromJson(Map<String, dynamic> map) =>
      PedidoVehiculoOption(
        id: _asInt(map['id']) ?? 0,
        placa: _asText(map['placa']) ?? 'Vehículo',
        marca: _asText(map['marca']),
        modelo: _asText(map['modelo']),
        tipoVehiculo: _asText(map['tipo_vehiculo']),
        capacidadKg: _asDouble(map['capacidad_kg']) ?? 0,
        capacidadM3: _asDouble(map['capacidad_m3']) ?? 0,
        licenciaRequerida: _asText(map['licencia_requerida']),
        transportePrincipal: _asText(map['transporte_principal']),
      );

  final int id;
  final String placa;
  final String? marca;
  final String? modelo;
  final String? tipoVehiculo;
  final double capacidadKg;
  final double capacidadM3;
  final String? licenciaRequerida;
  final String? transportePrincipal;

  String get displayLabel {
    final parts = <String>[
      placa,
      if ([marca, modelo].whereType<String>().isNotEmpty)
        [marca, modelo].whereType<String>().join(' '),
      if (capacidadKg > 0) '${capacidadKg.toStringAsFixed(0)} kg',
      ?transportePrincipal,
    ];
    return parts.join(' · ');
  }
}

class PedidoAgricolaFormData {
  const PedidoAgricolaFormData({
    this.almacenesOrigen = const [],
    this.almacenesDestino = const [],
    this.productos = const [],
    this.tiposEmpaque = const [],
    this.transportistas = const [],
    this.vehiculos = const [],
  });

  factory PedidoAgricolaFormData.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};

    List<T> parseList<T>(
      String key,
      T Function(Map<String, dynamic>) builder,
    ) {
      final raw = root[key];
      if (raw is! List) return <T>[];
      return [
        for (final entry in raw)
          if (entry is Map<String, dynamic>) builder(entry),
      ];
    }

    return PedidoAgricolaFormData(
      almacenesOrigen: parseList(
        'almacenes_origen',
        PedidoAlmacenOption.fromJson,
      ),
      almacenesDestino: parseList(
        'almacenes_destino',
        PedidoAlmacenOption.fromJson,
      ),
      productos: parseList('productos', PedidoProductoAgricolaOption.fromJson),
      tiposEmpaque: parseList(
        'tipos_empaque',
        PedidoTipoEmpaqueOption.fromJson,
      ),
      transportistas: parseList(
        'transportistas',
        PedidoTransportistaOption.fromJson,
      ),
      vehiculos: parseList('vehiculos', PedidoVehiculoOption.fromJson),
    );
  }

  final List<PedidoAlmacenOption> almacenesOrigen;
  final List<PedidoAlmacenOption> almacenesDestino;
  final List<PedidoProductoAgricolaOption> productos;
  final List<PedidoTipoEmpaqueOption> tiposEmpaque;
  final List<PedidoTransportistaOption> transportistas;
  final List<PedidoVehiculoOption> vehiculos;
}

class PedidoCostoEstimacion {
  const PedidoCostoEstimacion({
    required this.costoBs,
    required this.distanciaKm,
    required this.paradas,
    required this.detalle,
    this.lluvia = false,
  });

  factory PedidoCostoEstimacion.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    return PedidoCostoEstimacion(
      costoBs: (_asDouble(root['costo_bs']) ?? 0).round(),
      distanciaKm: _asDouble(root['distancia_km']) ?? 0,
      paradas: _asInt(root['paradas']) ?? 0,
      detalle: _asText(root['detalle']) ?? '',
      lluvia: root['lluvia'] == true,
    );
  }

  final int costoBs;
  final double distanciaKm;
  final int paradas;
  final String detalle;
  final bool lluvia;
}

class PedidoCapacidadValidacion {
  const PedidoCapacidadValidacion({
    required this.ok,
    required this.mensaje,
    required this.capacidadKg,
    required this.capacidadM3,
    required this.pesoKg,
    required this.volumenM3,
    this.porcentajePeso,
    this.porcentajeVolumen,
    this.vehiculo,
  });

  factory PedidoCapacidadValidacion.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    return PedidoCapacidadValidacion(
      ok: root['ok'] != false,
      mensaje: _asText(root['mensaje']) ?? '',
      capacidadKg: _asDouble(root['capacidad_kg']) ?? 0,
      capacidadM3: _asDouble(root['capacidad_m3']) ?? 0,
      pesoKg: _asDouble(root['peso_kg']) ?? 0,
      volumenM3: _asDouble(root['volumen_m3']) ?? 0,
      porcentajePeso: _asDouble(root['porcentaje_peso']),
      porcentajeVolumen: _asDouble(root['porcentaje_volumen']),
      vehiculo: _asText(root['vehiculo']),
    );
  }

  final bool ok;
  final String mensaje;
  final double capacidadKg;
  final double capacidadM3;
  final double pesoKg;
  final double volumenM3;
  final double? porcentajePeso;
  final double? porcentajeVolumen;
  final String? vehiculo;
}

class PedidoDistribucionPuntoOption {
  const PedidoDistribucionPuntoOption({
    required this.id,
    required this.nombre,
    this.direccion,
  });

  factory PedidoDistribucionPuntoOption.fromJson(Map<String, dynamic> map) =>
      PedidoDistribucionPuntoOption(
        id: _asInt(map['id']) ?? 0,
        nombre: _asText(map['nombre']) ?? 'Punto de venta',
        direccion: _asText(map['direccion']),
      );

  final int id;
  final String nombre;
  final String? direccion;
}

class PedidoDistribucionPresentacionOption {
  const PedidoDistribucionPresentacionOption({
    required this.id,
    required this.nombre,
    required this.pesoNetoKg,
    required this.unidadEtiqueta,
    required this.stockUnidades,
    required this.stockKg,
  });

  factory PedidoDistribucionPresentacionOption.fromJson(
    Map<String, dynamic> map,
  ) => PedidoDistribucionPresentacionOption(
    id: _asInt(map['id']) ?? 0,
    nombre: _asText(map['nombre']) ?? 'Presentación',
    pesoNetoKg: _asDouble(map['peso_neto_kg']) ?? 0,
    unidadEtiqueta: _asText(map['unidad_etiqueta']) ?? 'unidades',
    stockUnidades: _asDouble(map['stock_unidades']) ?? 0,
    stockKg: _asDouble(map['stock_kg']) ?? 0,
  );

  final int id;
  final String nombre;
  final double pesoNetoKg;
  final String unidadEtiqueta;
  final double stockUnidades;
  final double stockKg;
}

class PedidoDistribucionProductoOption {
  const PedidoDistribucionProductoOption({
    required this.insumoId,
    required this.label,
    required this.almacenMayoristaOrigenId,
    required this.almacenNombre,
    required this.stockKg,
    this.presentaciones = const [],
  });

  factory PedidoDistribucionProductoOption.fromJson(Map<String, dynamic> map) {
    final presRaw = map['presentaciones'];
    return PedidoDistribucionProductoOption(
      insumoId: _asInt(map['insumoid']) ?? 0,
      label: _asText(map['label']) ?? 'Producto',
      almacenMayoristaOrigenId: _asInt(map['almacen_mayorista_origenid']) ?? 0,
      almacenNombre: _asText(map['almacen_nombre']) ?? '',
      stockKg: _asDouble(map['stock_kg']) ?? 0,
      presentaciones: [
        if (presRaw is List)
          for (final item in presRaw)
            if (item is Map<String, dynamic>)
              PedidoDistribucionPresentacionOption.fromJson(item),
      ],
    );
  }

  final int insumoId;
  final String label;
  final int almacenMayoristaOrigenId;
  final String almacenNombre;
  final double stockKg;
  final List<PedidoDistribucionPresentacionOption> presentaciones;
}

class PedidoDistribucionFormData {
  const PedidoDistribucionFormData({
    this.puntosVenta = const [],
    this.almacenesMayoristas = const [],
    this.productos = const [],
  });

  factory PedidoDistribucionFormData.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};

    List<T> parseList<T>(
      String key,
      T Function(Map<String, dynamic>) builder,
    ) {
      final raw = root[key];
      if (raw is! List) return <T>[];
      return [
        for (final entry in raw)
          if (entry is Map<String, dynamic>) builder(entry),
      ];
    }

    return PedidoDistribucionFormData(
      puntosVenta: parseList(
        'puntos_venta',
        PedidoDistribucionPuntoOption.fromJson,
      ),
      almacenesMayoristas: parseList(
        'almacenes_mayoristas',
        PedidoDistribucionPuntoOption.fromJson,
      ),
      productos: parseList(
        'productos',
        PedidoDistribucionProductoOption.fromJson,
      ),
    );
  }

  final List<PedidoDistribucionPuntoOption> puntosVenta;
  final List<PedidoDistribucionPuntoOption> almacenesMayoristas;
  final List<PedidoDistribucionProductoOption> productos;

  bool get hasOptions => puntosVenta.isNotEmpty && productos.isNotEmpty;
}
