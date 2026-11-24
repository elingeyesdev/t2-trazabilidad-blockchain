abstract final class TrazabilidadCodigoParser {
  static final RegExp _validCodePattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]{2,63}$',
  );

  /// Extrae y normaliza un código de trazabilidad desde un código directo
  /// (`TRZ-PDV-...`, `TRZ-...`) o desde una URL pública
  /// (`https://.../trazabilidad/TRZ-PDV-...`).
  static String? extract(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final candidate = _extractRawCandidate(trimmed);
    if (candidate == null) return null;

    final normalized = candidate.trim().toUpperCase();
    if (!_validCodePattern.hasMatch(normalized)) return null;
    return normalized;
  }

  static String? _extractRawCandidate(String input) {
    final looksLikeUrlOrPath =
        input.contains('://') || input.contains('/') || input.contains('?');
    if (!looksLikeUrlOrPath) {
      return input;
    }

    final uri = Uri.tryParse(input);
    if (uri == null) return null;

    final fromQuery =
        uri.queryParameters['codigo'] ?? uri.queryParameters['code'];
    if (fromQuery != null && fromQuery.trim().isNotEmpty) {
      return fromQuery.trim();
    }

    final segments = uri.pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();

    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].toLowerCase() == 'trazabilidad') {
        try {
          return Uri.decodeComponent(segments[i + 1]);
        } catch (_) {
          return segments[i + 1];
        }
      }
    }

    return null;
  }
}

class TrazabilidadPublicaResumen {
  const TrazabilidadPublicaResumen({
    required this.codigo,
    required this.producto,
    this.puntoVenta,
    this.minorista,
    this.loteAgricola,
    this.loteCodigo,
    this.pedido,
    this.totalEventos = 0,
    this.rawData = const <String, dynamic>{},
  });

  factory TrazabilidadPublicaResumen.fromJson(
    Object? json, {
    required String fallbackCode,
  }) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};

    final eventos = root['eventos'];
    final totalFromField = _asInt(root['total_eventos']);
    final totalEventos =
        totalFromField ?? (eventos is List ? eventos.length : 0);

    return TrazabilidadPublicaResumen(
      codigo: _asText(root['codigo']) ?? fallbackCode,
      producto:
          _asText(root['producto']) ??
          _asText(root['lote_agricola']) ??
          'Producto trazado',
      puntoVenta: _asText(root['punto_venta']),
      minorista: _asText(root['minorista']),
      loteAgricola: _asText(root['lote_agricola']),
      loteCodigo: _asText(root['lote_codigo']),
      pedido: _asText(root['pedido']),
      totalEventos: totalEventos,
      rawData: Map<String, dynamic>.unmodifiable(root),
    );
  }

  final String codigo;
  final String producto;
  final String? puntoVenta;
  final String? minorista;
  final String? loteAgricola;
  final String? loteCodigo;
  final String? pedido;
  final int totalEventos;
  final Map<String, dynamic> rawData;
}

String? _asText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty || text == '—' ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
