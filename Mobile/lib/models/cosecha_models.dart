import 'api_exception.dart';
import 'auth_user.dart';

abstract final class CosechaPermissions {
  static bool canCreate(AuthUser user) =>
      !user.roles.contains('admin') && user.permissions.contains('lotes.view');
}

class CosechaUnidadOption {
  const CosechaUnidadOption({
    required this.id,
    required this.name,
    required this.abbreviation,
    this.category,
  });

  final int id;
  final String name;
  final String abbreviation;
  final String? category;

  bool get isWeight => category == null || category!.toLowerCase() == 'peso';

  bool get isKilogram {
    final abbr = abbreviation.toLowerCase();
    final lowerName = name.toLowerCase();
    return abbr == 'kg' || lowerName.contains('kilogram');
  }

  String get displayLabel =>
      abbreviation.isEmpty || abbreviation.toLowerCase() == name.toLowerCase()
      ? name
      : '$name ($abbreviation)';

  static List<CosechaUnidadOption> listFromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException(
        'No pudimos interpretar las unidades de medida.',
      );
    }
    final result = <CosechaUnidadOption>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = _asInt(row['unidadmedidaid']);
      final name = _asText(row['nombre']);
      if (id == null || id <= 0 || name == null) continue;
      final option = CosechaUnidadOption(
        id: id,
        name: name,
        abbreviation: _asText(row['abreviatura']) ?? name,
        category: _asText(row['categoria']),
      );
      if (!option.isWeight) continue;
      result.add(option);
    }
    return result;
  }
}

class CosechaPresentacionOption {
  const CosechaPresentacionOption({
    required this.id,
    required this.name,
    this.pesoPromedioKg,
    this.conteoPorEmpaque,
    this.empaque,
  });

  final int id;
  final String name;
  final String? pesoPromedioKg;
  final int? conteoPorEmpaque;
  final String? empaque;

  String get displayLabel {
    final parts = <String>[name];
    if (empaque != null && empaque!.isNotEmpty) {
      parts.add(empaque!);
    }
    final meta = <String>[
      if (pesoPromedioKg != null)
        '${formatCosechaDecimal(pesoPromedioKg!)} kg/u',
      if (conteoPorEmpaque != null && conteoPorEmpaque! > 0)
        '$conteoPorEmpaque/empaque',
    ];
    if (meta.isEmpty) return parts.join(' · ');
    return '${parts.join(' · ')} (${meta.join(', ')})';
  }
}

class CosechaConfiguracion {
  const CosechaConfiguracion({
    this.predeterminadaId,
    this.presentaciones = const [],
  });

  factory CosechaConfiguracion.fromJson(Object? json) {
    final map =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    if (map is! Map<String, dynamic>) {
      throw const ApiException(
        'No pudimos interpretar las presentaciones del lote.',
      );
    }
    final rawList = map['presentaciones'];
    final items = <CosechaPresentacionOption>[];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is! Map<String, dynamic>) continue;
        final id = _asInt(row['catalogotamanoconteoid']);
        final name = _asText(row['nombre']);
        if (id == null || id <= 0 || name == null) continue;
        items.add(
          CosechaPresentacionOption(
            id: id,
            name: name,
            pesoPromedioKg: _asText(row['peso_promedio_kg']),
            conteoPorEmpaque: _asInt(row['conteo_por_empaque']),
            empaque: _asText(row['empaque']),
          ),
        );
      }
    }
    return CosechaConfiguracion(
      predeterminadaId: _asInt(map['predeterminada_id']),
      presentaciones: items,
    );
  }

  final int? predeterminadaId;
  final List<CosechaPresentacionOption> presentaciones;
}

class CosechaDetailData {
  const CosechaDetailData({
    required this.id,
    required this.loteId,
    this.loteName,
    this.cantidad,
    this.unidadMedidaId,
    this.unidad,
    this.cantidadBaseKg,
    this.cantidadUnidades,
    this.cantidadEmpaques,
    this.fechaCosecha,
    this.observaciones,
    this.calibreId,
    this.calibreNombre,
    this.empaqueLabel,
    this.pesoPromedioKg,
    this.conteoPorEmpaque,
    this.resumenEquivalencia,
    this.presentacionOk = false,
  });

  factory CosechaDetailData.fromJson(Map<String, dynamic> row) {
    final id = _asInt(row['produccionid']) ?? 0;
    final loteMap = row['lote'] is Map<String, dynamic>
        ? row['lote'] as Map<String, dynamic>
        : null;
    final presMap = row['presentacion'] is Map<String, dynamic>
        ? row['presentacion'] as Map<String, dynamic>
        : null;
    final unitMap = row['unidad_medida'] is Map<String, dynamic>
        ? row['unidad_medida'] as Map<String, dynamic>
        : (row['unidadMedida'] is Map<String, dynamic>
              ? row['unidadMedida'] as Map<String, dynamic>
              : null);
    final unidad =
        _asText(row['unidad']) ??
        _asText(presMap?['unidad_abreviatura']) ??
        _asText(unitMap?['abreviatura']) ??
        _asText(unitMap?['nombre']);
    final cantidad = _asText(row['cantidad']);
    final cantidadBaseKg =
        _asText(row['cantidad_base']) ??
        _asText(row['cantidadkg']) ??
        _asText(presMap?['kg']);
    final cantidadUnidades =
        _asInt(row['cantidad_unidades']) ?? _asInt(presMap?['unidades']);
    final cantidadEmpaques =
        _asInt(row['cantidad_empaques']) ?? _asInt(presMap?['empaques']);
    return CosechaDetailData(
      id: id,
      loteId: _asInt(row['loteid']) ?? _asInt(loteMap?['loteid']) ?? 0,
      loteName: _asText(loteMap?['nombre']),
      cantidad: cantidad,
      unidadMedidaId: _asInt(row['unidadmedidaid']),
      unidad: unidad,
      cantidadBaseKg: cantidadBaseKg,
      cantidadUnidades: cantidadUnidades,
      cantidadEmpaques: cantidadEmpaques,
      fechaCosecha: _asText(row['fechacosecha']),
      observaciones: _asText(row['observaciones']),
      calibreId:
          _asInt(row['catalogotamanoconteoid']) ??
          _asInt(presMap?['calibre_id']),
      calibreNombre: _asText(presMap?['calibre_nombre']),
      empaqueLabel: _asText(presMap?['empaque_label']),
      pesoPromedioKg: _asText(presMap?['peso_promedio_kg']),
      conteoPorEmpaque: _asInt(presMap?['conteo_por_empaque']),
      resumenEquivalencia: _asText(presMap?['resumen']),
      presentacionOk:
          presMap?['ok'] == true ||
          (cantidadUnidades != null && cantidadEmpaques != null),
    );
  }

  final int id;
  final int loteId;
  final String? loteName;
  final String? cantidad;
  final int? unidadMedidaId;
  final String? unidad;
  final String? cantidadBaseKg;
  final int? cantidadUnidades;
  final int? cantidadEmpaques;
  final String? fechaCosecha;
  final String? observaciones;
  final int? calibreId;
  final String? calibreNombre;
  final String? empaqueLabel;
  final String? pesoPromedioKg;
  final int? conteoPorEmpaque;
  final String? resumenEquivalencia;
  final bool presentacionOk;

  String get formattedQuantity {
    final qty = cantidad == null ? null : formatCosechaDecimal(cantidad!);
    if (qty == null) return 'Sin registrar';
    return unidad == null || unidad!.isEmpty ? qty : '$qty $unidad';
  }

  String? get formattedBaseKg => cantidadBaseKg == null
      ? null
      : '${formatCosechaDecimal(cantidadBaseKg!)} kg';

  String? get equivalenciaLine {
    if (resumenEquivalencia != null) return resumenEquivalencia;
    if (cantidadEmpaques != null && cantidadUnidades != null) {
      final label = empaqueLabel ?? 'Empaques';
      return '$cantidadEmpaques $label · $cantidadUnidades unidades';
    }
    return null;
  }

  String get loteLabel =>
      loteName ?? (loteId > 0 ? 'Lote #$loteId' : 'Sin registrar');

  Map<String, String> toSummaryMap() => {
    'Lote': loteLabel,
    'Cantidad': formattedQuantity,
    if (formattedBaseKg != null && unidad?.toLowerCase() != 'kg')
      'Equivalencia base': formattedBaseKg!,
    'Equivalencia': ?equivalenciaLine,
    'Presentación': ?calibreNombre,
    'Fecha de cosecha': fechaCosecha ?? 'Sin registrar',
  };
}

String formatCosechaDecimal(String raw) {
  final trimmed = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$').hasMatch(trimmed)) {
    return trimmed;
  }
  if (!trimmed.contains('.')) return trimmed;
  return trimmed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String? validateCosechaQuantity(String? raw) {
  final normalized = (raw ?? '').trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return 'Indica la cantidad cosechada.';
  }
  if (!RegExp(
    r'^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$',
  ).hasMatch(normalized)) {
    return 'Indica una cantidad positiva válida.';
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) {
    return 'La cantidad cosechada debe ser mayor que cero.';
  }
  return null;
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
