import 'auth_user.dart';

abstract final class EntregaPermissions {
  static bool canViewRutas(AuthUser user) =>
      user.permissions.contains('rutas_multi.view');

  static bool canViewEnviosAgricolas(AuthUser user) =>
      user.permissions.contains('asignaciones.view') ||
      user.permissions.contains('pedidos.view') ||
      user.permissions.contains('recepcion_planta.view');

  static bool canViewEnviosDistribucion(AuthUser user) =>
      user.permissions.contains('pedidos_distribucion.view');

  static bool canViewAny(AuthUser user) =>
      canViewRutas(user) ||
      canViewEnviosAgricolas(user) ||
      canViewEnviosDistribucion(user);

  static bool canUpdateAvance(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('rutas_multi.update');
}

Uri? buildExternalMapsUri({
  String? latitud,
  String? longitud,
  String? direccion,
  String? destino,
}) {
  final lat = latitud?.trim();
  final lng = longitud?.trim();
  if (lat != null &&
      lng != null &&
      double.tryParse(lat) != null &&
      double.tryParse(lng) != null) {
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$lat,$lng',
    });
  }
  final query = (direccion?.trim().isNotEmpty == true)
      ? direccion!.trim()
      : (destino?.trim().isNotEmpty == true ? destino!.trim() : null);
  if (query == null) return null;
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
}

class ParadaEntrega {
  const ParadaEntrega({
    required this.id,
    required this.orden,
    required this.estado,
    this.destino,
    this.externoEnvioId,
    this.pedidoId,
    this.direccion,
    this.latitud,
    this.longitud,
  });

  factory ParadaEntrega.fromJson(Map<String, dynamic> map) {
    final pedido = map['pedido'] is Map<String, dynamic>
        ? map['pedido'] as Map<String, dynamic>
        : null;
    return ParadaEntrega(
      id: _asInt(map['rutaparadaid'] ?? map['id']) ?? 0,
      orden: _asInt(map['orden']) ?? 0,
      estado: (_asText(map['estado']) ?? 'pendiente').toLowerCase(),
      destino: _asText(map['destino']) ?? _asText(pedido?['nombre_planta']),
      externoEnvioId: _asText(map['externo_envio_id']),
      pedidoId: _asInt(map['pedidoid']),
      direccion:
          _asText(map['direccion']) ?? _asText(pedido?['direccion_texto']),
      latitud: _asText(map['latitud']) ?? _asText(pedido?['latitud']),
      longitud: _asText(map['longitud']) ?? _asText(pedido?['longitud']),
    );
  }

  final int id;
  final int orden;
  final String estado;
  final String? destino;
  final String? externoEnvioId;
  final int? pedidoId;
  final String? direccion;
  final String? latitud;
  final String? longitud;

  String get destinoLabel => destino ?? direccion ?? 'Destino sin especificar';

  String get estadoLabel => switch (estado) {
    'pendiente' => 'Pendiente',
    'en_ruta' || 'en_camino' => 'En ruta',
    'entregada' || 'completada' => 'Completada',
    'cancelada' => 'Cancelada',
    _ => estado,
  };

  Uri? get mapsUri => buildExternalMapsUri(
    latitud: latitud,
    longitud: longitud,
    direccion: direccion,
    destino: destino,
  );
}

class RutaEntregaRecord {
  const RutaEntregaRecord({
    required this.id,
    required this.nombre,
    required this.estado,
    this.fechaSalida,
    this.fechaCierre,
    this.transportistaNombre,
    this.paradasCount = 0,
    this.paradas = const [],
  });

  factory RutaEntregaRecord.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    final id = _asInt(root['rutamultientregaid'] ?? root['id']) ?? 0;
    final transportista = root['transportista'] is Map<String, dynamic>
        ? root['transportista'] as Map<String, dynamic>
        : null;
    final tNombre = _asText(transportista?['nombre']);
    final tApellido = _asText(transportista?['apellido']);
    final transportistaFull = [?tNombre, ?tApellido].join(' ');
    final rawParadas = root['paradas'];
    final paradas = <ParadaEntrega>[];
    if (rawParadas is List) {
      for (final entry in rawParadas) {
        if (entry is Map<String, dynamic>) {
          paradas.add(ParadaEntrega.fromJson(entry));
        }
      }
      paradas.sort((a, b) {
        final cmp = a.orden.compareTo(b.orden);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      });
    }
    return RutaEntregaRecord(
      id: id,
      nombre: _asText(root['nombre']) ?? 'Ruta #$id',
      estado: (_asText(root['estado']) ?? 'planificada').toLowerCase(),
      fechaSalida: _asText(root['fecha_salida']),
      fechaCierre: _asText(root['fecha_cierre']),
      transportistaNombre: transportistaFull.isEmpty ? null : transportistaFull,
      paradasCount: _asInt(root['paradas_count']) ?? paradas.length,
      paradas: paradas,
    );
  }

  final int id;
  final String nombre;
  final String estado;
  final String? fechaSalida;
  final String? fechaCierre;
  final String? transportistaNombre;
  final int paradasCount;
  final List<ParadaEntrega> paradas;

  String get estadoLabel => switch (estado) {
    'planificada' => 'Planificada',
    'en_ruta' => 'En ruta',
    'completada' => 'Completada',
    'cancelada' => 'Cancelada',
    _ => estado,
  };

  List<(String estado, String label)> get nextAllowedAdvances =>
      switch (estado) {
        'planificada' => const [('en_ruta', 'Iniciar ruta')],
        'en_ruta' => const [('completada', 'Finalizar entrega')],
        _ => const [],
      };
}

class RutasEntregaPage {
  const RutasEntregaPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  factory RutasEntregaPage.fromJson(Object? json) {
    final rows = json is List
        ? json
        : json is Map<String, dynamic> && json['data'] is List
        ? json['data'] as List
        : const [];
    final items = <RutaEntregaRecord>[];
    for (final entry in rows) {
      if (entry is Map<String, dynamic>) {
        final item = RutaEntregaRecord.fromJson(entry);
        if (item.id > 0) items.add(item);
      }
    }
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final meta = map['meta'] is Map<String, dynamic>
        ? map['meta'] as Map<String, dynamic>
        : map;
    return RutasEntregaPage(
      items: items,
      currentPage: _asInt(meta['current_page']) ?? 1,
      lastPage: _asInt(meta['last_page']) ?? 1,
    );
  }

  final List<RutaEntregaRecord> items;
  final int currentPage;
  final int lastPage;
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
