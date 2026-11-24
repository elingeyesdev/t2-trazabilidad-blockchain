import '../models/api_exception.dart';
import '../models/trazabilidad_publica_models.dart';
import 'api_client.dart';

class TrazabilidadPublicaService {
  const TrazabilidadPublicaService(this._api);

  final ApiClient _api;

  Future<TrazabilidadPublicaResumen> consultarPorCodigo(String rawInput) async {
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
    return TrazabilidadPublicaResumen.fromJson(response, fallbackCode: codigo);
  }
}
