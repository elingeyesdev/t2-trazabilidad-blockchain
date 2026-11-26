import '../models/api_exception.dart';
import '../models/trazabilidad_publica_models.dart';
import 'api_client.dart';

class TrazabilidadPublicaService {
  const TrazabilidadPublicaService(this._api);

  final ApiClient _api;

  Future<TrazabilidadPublicaReporte> consultarReporte(String rawInput) async {
    final codigo = TrazabilidadCodigoParser.extract(rawInput);
    if (codigo == null) {
      throw const ApiException(
        'El código o enlace QR no corresponde a un código de trazabilidad válido.',
        statusCode: 422,
      );
    }

    final response = await _api.request(
      'GET',
      'trazabilidad/${Uri.encodeComponent(codigo)}',
      authenticated: false,
    );
    return TrazabilidadPublicaReporte.fromJson(response, fallbackCode: codigo);
  }

  Future<TrazabilidadPublicaResumen> consultarPorCodigo(String rawInput) =>
      consultarReporte(rawInput);

  /// Construye la URL pública web (`/trazabilidad/{codigo}`) a partir de la
  /// configuración de la API cuando el servidor no envía `url_publica`.
  Uri buildPublicWebUrl(String codigo, {String? serverUrl}) {
    if (serverUrl != null && serverUrl.trim().isNotEmpty) {
      final parsed = Uri.tryParse(serverUrl.trim());
      if (parsed != null && parsed.hasScheme && parsed.hasAuthority) {
        return parsed;
      }
    }
    return _webOriginUri().resolve(
      '/trazabilidad/${Uri.encodeComponent(codigo)}',
    );
  }

  /// Resuelve una URL de evidencia/archivo pública (absoluta o relativa al host).
  Uri? resolvePublicAssetUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) return null;
    if (parsed.hasScheme && parsed.hasAuthority) {
      return parsed;
    }
    return _webOriginUri().resolveUri(parsed);
  }

  Uri _webOriginUri() {
    final apiUri = _api.config.baseUri;
    final segments = apiUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isNotEmpty && segments.last.toLowerCase() == 'api') {
      segments.removeLast();
    }
    return Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
      pathSegments: segments,
    );
  }
}
