import 'api_exception.dart';
import 'auth_user.dart';

abstract final class LotePermissions {
  static bool canCreate(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('lotes.create');

  static bool canEdit(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('lotes.update');
}

class SeedOption {
  const SeedOption({
    required this.id,
    required this.name,
    this.unit,
    this.stock,
    this.typeName,
  });

  final int id;
  final String name;
  final String? unit;
  final double? stock;
  final String? typeName;

  bool get isSeedType {
    final normalized = typeName?.trim().toLowerCase() ?? '';
    return normalized.contains('siembra') || normalized.contains('semilla');
  }

  String get displayLabel {
    if (stock == null) return name;
    final formattedStock = stock == stock!.roundToDouble()
        ? stock!.toInt().toString()
        : stock!.toStringAsFixed(2);
    final unitSuffix = unit == null || unit!.trim().isEmpty ? '' : ' $unit';
    return '$name ($formattedStock$unitSuffix disp.)';
  }

  static List<SeedOption> listFromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException(
        'No pudimos interpretar el catálogo de semillas.',
      );
    }

    final options = <SeedOption>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = _asInt(row['insumoid']);
      final name = _asText(row['nombre']);
      if (id == null || id <= 0 || name == null) continue;

      final tipo = row['tipo'];
      final typeName = tipo is Map<String, dynamic>
          ? _asText(tipo['nombre'])
          : null;
      final unidad = row['unidad_medida'] ?? row['unidadMedida'];
      final unit = unidad is Map<String, dynamic>
          ? (_asText(unidad['abreviatura']) ?? _asText(unidad['nombre']))
          : null;
      final stock = _asDouble(row['stock']);

      options.add(
        SeedOption(
          id: id,
          name: name,
          unit: unit,
          stock: stock,
          typeName: typeName,
        ),
      );
    }

    final seedsOnly = options.where((option) => option.isSeedType).toList();
    if (seedsOnly.isNotEmpty) return seedsOnly;
    final hasAnyType = options.any((option) => option.typeName != null);
    return hasAnyType ? const [] : options;
  }
}

class LoteEditableData {
  const LoteEditableData({
    required this.id,
    required this.name,
    this.superficie,
    this.ubicacion,
    this.latitud,
    this.longitud,
    this.insumoSemillaId,
    this.insumoSemillaNombre,
    this.cantidadSemillaPlanificada,
    this.estadoNombre,
  });

  factory LoteEditableData.fromJson(Map<String, dynamic> row) {
    final id = _asInt(row['loteid']) ?? 0;
    final insumo = row['insumo_semilla'] ?? row['insumoSemilla'];
    final estado = row['estado_tipo'] ?? row['estadoTipo'];
    return LoteEditableData(
      id: id,
      name: _asText(row['nombre']) ?? 'Lote #$id',
      superficie: _asDouble(row['superficie']),
      ubicacion: _asText(row['ubicacion']),
      latitud: _asDouble(row['latitud']),
      longitud: _asDouble(row['longitud']),
      insumoSemillaId:
          _asInt(row['insumosemillaid']) ??
          (insumo is Map<String, dynamic> ? _asInt(insumo['insumoid']) : null),
      insumoSemillaNombre: insumo is Map<String, dynamic>
          ? _asText(insumo['nombre'])
          : null,
      cantidadSemillaPlanificada: _asDouble(
        row['cantidad_semilla_planificada'],
      ),
      estadoNombre: estado is Map<String, dynamic>
          ? _asText(estado['nombre'])
          : null,
    );
  }

  final int id;
  final String name;
  final double? superficie;
  final String? ubicacion;
  final double? latitud;
  final double? longitud;
  final int? insumoSemillaId;
  final String? insumoSemillaNombre;
  final double? cantidadSemillaPlanificada;
  final String? estadoNombre;

  bool get isClosed {
    final normalized = estadoNombre?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return const {
      'cosechado',
      'finalizado',
      'certificado',
      'no conforme',
      'en descanso',
      'archivado',
      'suspendido',
    }.contains(normalized);
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  if (value is String) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}

String? _asText(Object? value) {
  if (value == null) return null;
  if (value is! String && value is! num) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
