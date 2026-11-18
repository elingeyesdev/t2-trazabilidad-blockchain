import 'dart:typed_data';

import 'api_exception.dart';
import 'auth_user.dart';

abstract final class ActividadPermissions {
  static bool canAssign(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.roles.contains('jefe_agricultor') &&
      user.permissions.contains('lotes.update');

  static bool canAddObservations(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('lotes.update');

  static bool canClose(AuthUser user, ActividadEditableData? actividad) {
    if (actividad == null || actividad.isCompleted) return false;
    if (user.roles.contains('admin') ||
        user.roles.contains('jefe_agricultor')) {
      return false;
    }
    if (!user.permissions.contains('lotes.view')) return false;
    final assignedId = actividad.responsableId;
    final executorId = actividad.ejecutorId;
    if (assignedId == null && executorId == null) return true;
    return assignedId == user.id || executorId == user.id;
  }
}

class EvidencePhoto {
  EvidencePhoto._(this.bytes, this.extension, this.originalName);

  factory EvidencePhoto(Uint8List bytes, {required String name}) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const ApiException('Selecciona una imagen de hasta 5 MB.');
    }
    final extension = name.split('.').last.toLowerCase();
    if (!_types.containsKey(extension)) {
      throw const ApiException(
        'Selecciona una fotografía JPG, PNG o WebP válida.',
      );
    }
    return EvidencePhoto._(
      Uint8List.fromList(bytes).asUnmodifiableView(),
      extension,
      name.trim().isEmpty ? 'evidencia.$extension' : name.trim(),
    );
  }

  static const maxBytes = 5 * 1024 * 1024;
  static const _types = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  final Uint8List bytes;
  final String extension;
  final String originalName;
  String get filename => 'evidencia.$extension';
  String get contentType => _types[extension]!;
}

class ActividadTipoOption {
  const ActividadTipoOption({
    required this.id,
    required this.name,
    this.description,
  });

  final int id;
  final String name;
  final String? description;

  bool get isIrrigation => name.toLowerCase().contains('riego');

  static List<ActividadTipoOption> listFromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException(
        'No pudimos interpretar los tipos de actividad.',
      );
    }
    final result = <ActividadTipoOption>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = _asInt(row['tipoactividadid']);
      final name = _asText(row['nombre']);
      if (id == null || id <= 0 || name == null) continue;
      result.add(
        ActividadTipoOption(
          id: id,
          name: name,
          description: _asText(row['descripcion']),
        ),
      );
    }
    return result;
  }
}

class PrioridadOption {
  const PrioridadOption({required this.id, required this.name});

  final int id;
  final String name;

  static List<PrioridadOption> listFromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException('No pudimos interpretar las prioridades.');
    }
    final result = <PrioridadOption>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = _asInt(row['prioridadid']);
      final name = _asText(row['nombre']);
      if (id == null || id <= 0 || name == null) continue;
      result.add(PrioridadOption(id: id, name: name));
    }
    return result;
  }
}

class ResponsableOption {
  const ResponsableOption({
    required this.id,
    required this.name,
    this.roleLabel,
  });

  final int id;
  final String name;
  final String? roleLabel;

  String get displayLabel =>
      roleLabel == null || roleLabel!.isEmpty ? name : '$name · $roleLabel';

  static List<ResponsableOption> listFromUsersJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException('No pudimos interpretar la lista de equipo.');
    }
    final result = <ResponsableOption>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = _asInt(row['usuarioid']);
      final firstName = _asText(row['nombre']);
      if (id == null || id <= 0 || firstName == null) continue;
      if (row['activo'] == false) continue;

      final roles = <String>[];
      if (row['roles'] is List) {
        for (final role in row['roles'] as List) {
          if (role is Map<String, dynamic>) {
            final roleName = _asText(role['name']);
            if (roleName != null) roles.add(roleName);
          }
        }
      }
      final roleColumn = _asText(row['role']);
      if (roleColumn != null) roles.add(roleColumn);
      final normalizedRoles = roles.map((r) => r.toLowerCase()).toSet();
      if (normalizedRoles.contains('admin')) continue;

      final lastName = _asText(row['apellido']);
      final fullName = [firstName, ?lastName].join(' ');
      final isAgricultor = normalizedRoles.contains('agricultor');
      final isJefe = normalizedRoles.contains('jefe_agricultor');
      if (normalizedRoles.isNotEmpty && !isAgricultor && !isJefe) continue;

      result.add(
        ResponsableOption(
          id: id,
          name: fullName,
          roleLabel: isJefe
              ? 'Jefe agrícola'
              : (isAgricultor ? 'Agricultor' : null),
        ),
      );
    }
    return result;
  }
}

class LoteOption {
  const LoteOption({required this.id, required this.name, this.cropName});

  final int id;
  final String name;
  final String? cropName;

  String get displayLabel =>
      cropName == null || cropName!.isEmpty ? name : '$name · $cropName';
}

class ActividadEditableData {
  const ActividadEditableData({
    required this.id,
    required this.loteId,
    required this.description,
    this.responsableId,
    this.ejecutorId,
    this.observations,
    this.resultado,
    this.evidenceUrl,
    this.consumos = const [],
    this.isCompleted = false,
  });

  factory ActividadEditableData.fromJson(Map<String, dynamic> row) {
    final id = _asInt(row['actividadid']) ?? 0;
    final loteId =
        _asInt(row['loteid']) ??
        (row['lote'] is Map<String, dynamic>
            ? _asInt((row['lote'] as Map<String, dynamic>)['loteid'])
            : null) ??
        0;
    final responsableId =
        _asInt(row['usuarioid']) ??
        (row['usuario'] is Map<String, dynamic>
            ? _asInt((row['usuario'] as Map<String, dynamic>)['usuarioid'])
            : null);
    final ejecutorId =
        _asInt(row['usuarioid_ejecutor']) ??
        (row['ejecutor'] is Map<String, dynamic>
            ? _asInt((row['ejecutor'] as Map<String, dynamic>)['usuarioid'])
            : null);
    return ActividadEditableData(
      id: id,
      loteId: loteId,
      description: _asText(row['descripcion']) ?? 'Actividad #$id',
      responsableId: responsableId,
      ejecutorId: ejecutorId,
      observations: _asText(row['observaciones']),
      resultado: _asText(row['resultado']),
      evidenceUrl: _asText(row['evidencia_foto_url']),
      consumos: ActividadConsumoRecord.listFromJson(row['consumos']),
      isCompleted: row['fechafin'] != null,
    );
  }

  final int id;
  final int loteId;
  final String description;
  final int? responsableId;
  final int? ejecutorId;
  final String? observations;
  final String? resultado;
  final String? evidenceUrl;
  final List<ActividadConsumoRecord> consumos;
  final bool isCompleted;
}

class AlmacenOption {
  const AlmacenOption({
    required this.id,
    required this.name,
    this.ambito,
    this.location,
  });

  final int id;
  final String name;
  final String? ambito;
  final String? location;

  bool get isAgricultural =>
      ambito == null || ambito!.toLowerCase() == 'agricola';

  String get displayLabel =>
      location == null || location!.isEmpty ? name : '$name · $location';

  static List<AlmacenOption> listFromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException('No pudimos interpretar los almacenes.');
    }
    final result = <AlmacenOption>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      if (row['activo'] == false) continue;
      final id = _asInt(row['almacenid']);
      final name = _asText(row['nombre']);
      if (id == null || id <= 0 || name == null) continue;
      final option = AlmacenOption(
        id: id,
        name: name,
        ambito: _asText(row['ambito']),
        location: _asText(row['ubicacion']),
      );
      if (!option.isAgricultural) continue;
      result.add(option);
    }
    return result;
  }
}

class InsumoOption {
  const InsumoOption({
    required this.id,
    required this.name,
    required this.stock,
    required this.unitLabel,
    this.almacenId,
    this.unidadMedidaId,
    this.tipoNombre,
  });

  final int id;
  final String name;
  final double stock;
  final String unitLabel;
  final int? almacenId;
  final int? unidadMedidaId;
  final String? tipoNombre;

  String get formattedStock => '${formatQuantity(stock)} $unitLabel';

  String get displayLabel => '$name ($formattedStock disp.)';

  static List<InsumoOption> listFromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException('No pudimos interpretar los insumos.');
    }
    final result = <InsumoOption>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = _asInt(row['insumoid']);
      final name = _asText(row['nombre']);
      if (id == null || id <= 0 || name == null) continue;
      final unitMap = row['unidad_medida'] is Map<String, dynamic>
          ? row['unidad_medida'] as Map<String, dynamic>
          : (row['unidadMedida'] is Map<String, dynamic>
                ? row['unidadMedida'] as Map<String, dynamic>
                : null);
      final unitLabel =
          _asText(unitMap?['abreviatura']) ??
          _asText(unitMap?['nombre']) ??
          _asText(row['unidad']) ??
          'u';
      final tipoMap = row['tipo'] is Map<String, dynamic>
          ? row['tipo'] as Map<String, dynamic>
          : null;
      result.add(
        InsumoOption(
          id: id,
          name: name,
          stock: _asDouble(row['stock']) ?? 0,
          unitLabel: unitLabel,
          almacenId: _asInt(row['almacenid']),
          unidadMedidaId:
              _asInt(row['unidadmedidaid']) ??
              _asInt(unitMap?['unidadmedidaid']),
          tipoNombre: _asText(tipoMap?['nombre']),
        ),
      );
    }
    return result;
  }
}

class ActividadConsumoRecord {
  const ActividadConsumoRecord({
    required this.insumoId,
    required this.cantidad,
    required this.name,
    this.almacenId,
    this.unidadMedidaId,
    this.unitLabel,
  });

  final int insumoId;
  final int? almacenId;
  final double cantidad;
  final String name;
  final int? unidadMedidaId;
  final String? unitLabel;

  String get formattedQuantity {
    final qty = formatQuantity(cantidad);
    return unitLabel == null || unitLabel!.isEmpty ? qty : '$qty $unitLabel';
  }

  static List<ActividadConsumoRecord> listFromJson(Object? json) {
    if (json is! List) return const [];
    final result = <ActividadConsumoRecord>[];
    for (final row in json) {
      if (row is! Map<String, dynamic>) continue;
      final insumoId = _asInt(row['insumoid']);
      final cantidad = _asDouble(row['cantidad']);
      if (insumoId == null || insumoId <= 0 || cantidad == null) continue;
      result.add(
        ActividadConsumoRecord(
          insumoId: insumoId,
          almacenId: _asInt(row['almacenid']),
          cantidad: cantidad,
          name: _asText(row['nombre']) ?? 'Insumo #$insumoId',
          unidadMedidaId: _asInt(row['unidadmedidaid']),
          unitLabel: _asText(row['unidad']),
        ),
      );
    }
    return result;
  }
}

class ActividadConsumoInput {
  const ActividadConsumoInput({
    required this.insumoId,
    required this.almacenId,
    required this.quantityText,
    this.unidadMedidaId,
  });

  final int insumoId;
  final int almacenId;
  final String quantityText;
  final int? unidadMedidaId;

  Map<String, Object?> toPayload() => {
    'insumoid': insumoId,
    'almacenid': almacenId,
    'cantidad': quantityText,
    'unidadmedidaid': ?unidadMedidaId,
  };
}

final RegExp _quantityPattern = RegExp(
  r'^(?:0|[1-9][0-9]{0,10})(?:\.[0-9]{1,3})?$',
);

String normalizeQuantityInput(String raw) => raw.trim().replaceAll(',', '.');

double? parseQuantityInput(String raw) {
  final normalized = normalizeQuantityInput(raw);
  if (normalized.isEmpty || !_quantityPattern.hasMatch(normalized)) {
    return null;
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

String formatQuantity(num value) {
  final rounded = (value * 1000).round() / 1000;
  final fixed = rounded.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String? validateConsumptionQuantity(
  String? raw, {
  required double availableStock,
  required String unitLabel,
}) {
  final normalized = normalizeQuantityInput(raw ?? '');
  if (normalized.isEmpty) {
    return 'Indica la cantidad utilizada en $unitLabel.';
  }
  if (!_quantityPattern.hasMatch(normalized)) {
    return 'Indica una cantidad positiva con hasta tres decimales.';
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) {
    return 'La cantidad utilizada debe ser mayor que cero.';
  }
  final availableScaled = (availableStock * 1000).round();
  final requestedScaled = (parsed * 1000).round();
  if (requestedScaled > availableScaled) {
    return 'Existencias insuficientes: hay ${formatQuantity(availableStock)} $unitLabel disponibles. Corrige la cantidad.';
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
  return null;
}

String? _asText(Object? value) {
  if (value == null) return null;
  if (value is! String && value is! num) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
