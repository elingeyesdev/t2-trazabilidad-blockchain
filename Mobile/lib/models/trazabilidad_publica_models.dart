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
