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
      user.roles.contains('jefe_agricola');

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
    this.estado,
    this.transportistaUsuarioId,
    this.fechaRecepcionPlanta,
  });

  factory PedidoEnvioInfo.fromJson(Map<String, dynamic> map) => PedidoEnvioInfo(
    id: _asInt(map['id']) ?? 0,
    estado: _asText(map['estado']),
    transportistaUsuarioId: _asInt(map['transportista_usuarioid']),
    fechaRecepcionPlanta: _asText(map['fecha_recepcion_planta']),
  );

  final int id;
  final String? estado;
  final int? transportistaUsuarioId;
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
    this.fecha,
    this.fechaEntregaDeseada,
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
      fecha: _asText(root['fecha']),
      fechaEntregaDeseada: _asText(root['fecha_entrega_deseada']),
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
  final String? fecha;
  final String? fechaEntregaDeseada;
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
