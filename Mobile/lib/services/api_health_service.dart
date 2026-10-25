import '../models/api_exception.dart';
import '../models/api_health.dart';
import 'api_client.dart';

class ApiHealthService {
  const ApiHealthService(this._api);

  final ApiClient _api;

  Future<ApiHealth> check() async {
    final json = await _api.request('GET', 'test-api', authenticated: false);
    final ApiHealth health;
    try {
      health = ApiHealth.fromJson(json);
    } on FormatException {
      throw const ApiException('La respuesta del servidor no es la esperada.');
    }
    if (!health.ok) {
      throw const ApiException('El servidor no confirmó la conexión.');
    }
    return health;
  }
}
