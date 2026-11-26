import 'auth_user.dart';

abstract final class IncidentePermissions {
  static bool canView(AuthUser user) =>
      user.permissions.contains('incidentes.view');

  static bool canCreate(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('incidentes.create');

  static bool canResolve(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('incidentes.resolve');
}

class IncidenteFormArgs {
  const IncidenteFormArgs({
    required this.afectadoTipo,
    required this.afectadoId,
    required this.referenciaLabel,
  });

  final String afectadoTipo;
  final int afectadoId;
  final String referenciaLabel;
}

class IncidenteRecord {
  const IncidenteRecord({
    required this.id,
    required this.tipo,
    required this.descripcion,
    required this.estado,
    required this.seguimiento,
    this.afectadoReferencia,
    this.responsableNombre,
    this.reportadoPorNombre,
    this.createdAt,
    this.notaResolucion,
    this.fechaResolucion,
    this.resueltoPorNombre,
    this.puedeResolver,
  });

  factory IncidenteRecord.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    final estado = (_asText(root['estado']) ?? 'abierto').toLowerCase();
    final seguimiento =
        _asText(root['seguimiento']) ??
        (estado == 'resuelto'
            ? 'Resuelta'
            : (estado == 'abierto' || estado == 'pendiente'
                  ? 'Pendiente de resolución'
                  : estado));
    final reportadoPor = root['reportado_por'] is Map<String, dynamic>
        ? root['reportado_por'] as Map<String, dynamic>
        : null;
    final resueltoPor = root['resuelto_por'] is Map<String, dynamic>
        ? root['resuelto_por'] as Map<String, dynamic>
        : null;
    final responsable = root['responsable'] is Map<String, dynamic>
        ? root['responsable'] as Map<String, dynamic>
        : null;
    return IncidenteRecord(
      id: _asInt(root['incidenteenvioid'] ?? root['id']) ?? 0,
      tipo: _asText(root['tipo']) ?? 'Incidencia',
      descripcion: _asText(root['descripcion']) ?? '',
      estado: estado,
      seguimiento: seguimiento,
      afectadoReferencia: _asText(root['afectado_referencia']),
      responsableNombre:
          _asText(root['responsable_nombre']) ??
          _asText(responsable?['nombre']),
      reportadoPorNombre: _asText(reportadoPor?['nombre']),
      createdAt: _asText(root['created_at']),
      notaResolucion: _asText(root['nota_resolucion']),
      fechaResolucion: _asText(root['fecha_resolucion']),
      resueltoPorNombre: _asText(resueltoPor?['nombre']),
      puedeResolver: root['puede_resolver'] is bool
          ? root['puede_resolver'] as bool
          : null,
    );
  }

  final int id;
  final String tipo;
  final String descripcion;
  final String estado;
  final String seguimiento;
  final String? afectadoReferencia;
  final String? responsableNombre;
  final String? reportadoPorNombre;
  final String? createdAt;
  final String? notaResolucion;
  final String? fechaResolucion;
  final String? resueltoPorNombre;
  final bool? puedeResolver;

  bool get isResolved => estado == 'resuelto';
}

class IncidentesPage {
  const IncidentesPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  factory IncidentesPage.fromJson(Object? json) {
    final rows = json is List
        ? json
        : json is Map<String, dynamic> && json['data'] is List
        ? json['data'] as List
        : const [];
    final items = <IncidenteRecord>[];
    for (final entry in rows) {
      if (entry is Map<String, dynamic>) {
        final item = IncidenteRecord.fromJson(entry);
        if (item.id > 0) items.add(item);
      }
    }
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final meta = map['meta'] is Map<String, dynamic>
        ? map['meta'] as Map<String, dynamic>
        : map;
    return IncidentesPage(
      items: items,
      currentPage: _asInt(meta['current_page']) ?? 1,
      lastPage: _asInt(meta['last_page']) ?? 1,
    );
  }

  final List<IncidenteRecord> items;
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
