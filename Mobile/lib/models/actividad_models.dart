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
  final bool isCompleted;
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
