import 'api_exception.dart';

class FieldRecordInfo {
  FieldRecordInfo._({
    required this.status,
    required Map<String, String> summary,
    required Map<String, String> details,
  }) : summary = Map.unmodifiable(summary),
       details = Map.unmodifiable(details);

  factory FieldRecordInfo.lote(Map<String, dynamic> row) {
    final crop = _crop(row);
    final status = _related(row, 'estado_tipo', 'nombre');
    final responsible = _person(row);
    final sowing = _date(row, 'fechasiembra');
    final pending = _pending(row);
    return FieldRecordInfo._(
      status: _capitalize(status),
      summary: {
        'Cultivo': crop,
        'Responsable': responsible,
        'Siembra': sowing,
        'Pendientes': pending == null ? unavailable : '$pending',
      },
      details: {
        'Cultivo': crop,
        'Estado': _capitalize(status) ?? unavailable,
        'Responsable': responsible,
        'Fecha de siembra': sowing,
        'Actividades pendientes': pending == null ? unavailable : '$pending',
        'Ubicación': _text(row, 'ubicacion') ?? 'Sin registrar',
        'Superficie': _area(row),
        'Código de trazabilidad':
            _text(row, 'codigo_trazabilidad') ?? 'Sin registrar',
        'Fecha de creación': _date(row, 'fechacreacion', includeTime: true),
      },
    );
  }

  factory FieldRecordInfo.actividad(Map<String, dynamic> row) {
    final lot = _relation(row, 'lote');
    final lotId = row['loteid'];
    final lotName = lot == null ? null : _text(lot, 'nombre');
    final lotLabel =
        lotName ?? (lotId is int && lotId > 0 ? '#$lotId' : unavailable);
    final responsible = _person(row);
    final planned = _date(row, 'fecha_planificada');
    final finished = _date(row, 'fechafin', includeTime: true);
    final String? status;
    if (!row.containsKey('fechafin')) {
      status = null;
    } else {
      status = row['fechafin'] == null
          ? 'Pendiente'
          : finished == 'Sin registrar'
          ? null
          : 'Completada';
    }
    return FieldRecordInfo._(
      status: status,
      summary: {
        'Lote': lotLabel,
        'Responsable': responsible,
        'Fecha planificada': planned,
      },
      details: {
        'Lote': lotLabel,
        'Cultivo': lot == null ? unavailable : _crop(lot),
        'Estado': status ?? unavailable,
        'Responsable': responsible,
        'Fecha planificada': planned,
        'Inicio': _date(row, 'fechainicio', includeTime: true),
        'Finalización': finished,
        'Tipo de actividad':
            _related(row, 'tipo_actividad', 'nombre') ?? unavailable,
        'Prioridad': _related(row, 'prioridad', 'nombre') ?? unavailable,
        'Observaciones': row.containsKey('observaciones')
            ? _text(row, 'observaciones') ?? 'Sin observaciones'
            : unavailable,
      },
    );
  }

  static const unavailable = 'No disponible';
  static const _invalid = ApiException(
    'No pudimos interpretar los datos del registro. Intenta actualizar.',
  );

  final String? status;
  final Map<String, String> summary;
  final Map<String, String> details;

  static String? _text(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String && value is! num) throw _invalid;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, dynamic>? _relation(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! Map<String, dynamic>) throw _invalid;
    return value;
  }

  static String? _related(Map<String, dynamic> row, String key, String field) {
    final relation = _relation(row, key);
    return relation == null ? null : _text(relation, field);
  }

  static String _crop(Map<String, dynamic> row) =>
      _related(row, 'insumo_semilla', 'nombre') ??
      _related(row, 'cultivo', 'nombre') ??
      unavailable;

  static String _person(Map<String, dynamic> row) {
    final person = [
      _related(row, 'usuario', 'nombre'),
      _related(row, 'usuario', 'apellido'),
    ].whereType<String>().join(' ');
    return person.isEmpty ? unavailable : person;
  }

  static String? _capitalize(String? value) =>
      value == null ? null : '${value[0].toUpperCase()}${value.substring(1)}';

  static String _date(
    Map<String, dynamic> row,
    String key, {
    bool includeTime = false,
  }) {
    final value = _text(row, key);
    if (value == null) return 'Sin registrar';
    final parsed = DateTime.tryParse(value);
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:$|[T ])',
    ).firstMatch(value);
    if (parsed == null || match == null) throw _invalid;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final dayOfMonth = int.parse(match[3]!);
    final calendar = DateTime.utc(year, month, dayOfMonth);
    if (calendar.year != year ||
        calendar.month != month ||
        calendar.day != dayOfMonth) {
      throw _invalid;
    }
    final date = includeTime ? parsed.toLocal() : calendar;
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${two(date.day)}/${two(date.month)}/${date.year}';
    return includeTime && value.length > 10
        ? '$day · ${two(date.hour)}:${two(date.minute)}'
        : day;
  }

  static String _area(Map<String, dynamic> row) {
    final value = _text(row, 'superficie');
    if (value == null) return 'Sin registrar';
    final area = num.tryParse(value);
    if (area == null || !area.isFinite || area < 0) throw _invalid;
    final parts = area.toStringAsFixed(2).split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '$integer,${parts.last} ${(area - 1).abs() < .00001 ? 'hectárea' : 'hectáreas'}';
  }

  static int? _pending(Map<String, dynamic> row) {
    final supplied = row['actividades_pendientes'];
    if (supplied != null) {
      if (supplied is! int || supplied < 0) throw _invalid;
      return supplied;
    }
    final activities = row['actividades'];
    if (activities == null) return null;
    if (activities is! List) throw _invalid;
    var pending = 0;
    for (final activity in activities) {
      if (activity is! Map<String, dynamic>) throw _invalid;
      if (!activity.containsKey('fechafin')) return null;
      final end = activity['fechafin'];
      if (end == null) {
        pending++;
      } else if (_date(activity, 'fechafin', includeTime: true) ==
          'Sin registrar') {
        return null;
      }
    }
    return pending;
  }
}
