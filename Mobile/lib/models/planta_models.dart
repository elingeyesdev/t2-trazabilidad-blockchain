import 'api_exception.dart';
import 'auth_user.dart';

abstract final class PlantaPermissions {
  static bool isOperarioPlanta(AuthUser user) =>
      user.roles.contains('planta') &&
      !user.roles.contains('jefe_planta') &&
      !user.roles.contains('admin');

  static bool canViewTareas(AuthUser user) =>
      user.permissions.contains('lote_produccion.view') &&
      isOperarioPlanta(user);
}

class TareaPlantaSummary {
  const TareaPlantaSummary({
    required this.id,
    required this.orden,
    required this.estado,
    required this.loteProduccionId,
    required this.procesoNombre,
    required this.maquinaNombre,
    this.maquinaId,
    this.maquinaCodigo,
    this.maquinaActiva = true,
    this.loteCodigo,
    this.loteNombre,
    this.loteProducto,
    this.loteFechaCreacion,
    this.creadoEn,
    this.completadaEn,
    this.observaciones,
  });

  factory TareaPlantaSummary.fromJson(Map<String, dynamic> row) {
    final id = _asInt(row['asignacionetapaplantaid']) ?? 0;
    final procesoMap = row['proceso'] is Map<String, dynamic>
        ? row['proceso'] as Map<String, dynamic>
        : null;
    final maquinaMap = row['maquina'] is Map<String, dynamic>
        ? row['maquina'] as Map<String, dynamic>
        : null;
    final loteMap = row['lote_produccion'] is Map<String, dynamic>
        ? row['lote_produccion'] as Map<String, dynamic>
        : null;
    return TareaPlantaSummary(
      id: id,
      orden: _asInt(row['orden']) ?? 0,
      estado: (_asText(row['estado']) ?? 'pendiente').toLowerCase(),
      loteProduccionId: _asInt(loteMap?['loteproduccionpedidoid']) ?? 0,
      procesoNombre: _asText(procesoMap?['nombre']) ?? 'Proceso #$id',
      maquinaId: _asInt(maquinaMap?['maquinaplantaid']),
      maquinaNombre: _asText(maquinaMap?['nombre']) ?? 'Sin máquina asignada',
      maquinaCodigo: _asText(maquinaMap?['codigo']),
      maquinaActiva: maquinaMap?['activo'] != false,
      loteCodigo: _asText(loteMap?['codigo_lote']),
      loteNombre: _asText(loteMap?['nombre']),
      loteProducto: _asText(loteMap?['producto']),
      loteFechaCreacion: _asText(loteMap?['fecha_creacion']),
      creadoEn: _asText(row['creado_en']),
      completadaEn: _asText(row['completada_en']),
      observaciones: _asText(row['observaciones']),
    );
  }

  final int id;
  final int orden;
  final String estado;
  final int loteProduccionId;
  final String procesoNombre;
  final int? maquinaId;
  final String maquinaNombre;
  final String? maquinaCodigo;
  final bool maquinaActiva;
  final String? loteCodigo;
  final String? loteNombre;
  final String? loteProducto;
  final String? loteFechaCreacion;
  final String? creadoEn;
  final String? completadaEn;
  final String? observaciones;

  bool get isCompleted => estado == 'completada';
  bool get isCancelled => estado == 'cancelada';

  String get estadoLabel => switch (estado) {
    'pendiente' => 'Pendiente',
    'programada' => 'Programada',
    'completada' => 'Completada',
    'cancelada' => 'Cancelada',
    _ => estado,
  };

  String get loteLabel {
    final parts = [?loteCodigo, ?loteNombre];
    return parts.isEmpty
        ? 'Lote industrial #$loteProduccionId'
        : parts.join(' · ');
  }

  String get maquinaLabel =>
      maquinaCodigo == null ? maquinaNombre : '$maquinaNombre ($maquinaCodigo)';
}

class TareasPlantaPage {
  const TareasPlantaPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  factory TareasPlantaPage.fromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException(
        'No pudimos interpretar las tareas de planta asignadas.',
      );
    }
    final items = <TareaPlantaSummary>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final item = TareaPlantaSummary.fromJson(row);
      if (item.id > 0) items.add(item);
    }
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final meta = map['meta'] is Map<String, dynamic>
        ? map['meta'] as Map<String, dynamic>
        : map;
    return TareasPlantaPage(
      items: items,
      currentPage: _asInt(meta['current_page']) ?? 1,
      lastPage: _asInt(meta['last_page']) ?? 1,
      total: _asInt(meta['total']) ?? items.length,
    );
  }

  final List<TareaPlantaSummary> items;
  final int currentPage;
  final int lastPage;
  final int total;
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
