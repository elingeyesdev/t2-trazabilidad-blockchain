import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Conserva el prefijo de la API y codifica los parámetros de consulta',
    () {
      final config = ApiConfig(
        baseUrl: 'https://example.test/agrofusion/api///',
      );
      final endpoint = config.endpoint(
        'lotes',
        queryParameters: {'buscar': 'maíz & trigo'},
      );

      expect(config.baseUri.path, '/agrofusion/api/');
      expect(endpoint.path, '/agrofusion/api/lotes');
      expect(endpoint.queryParameters, {'buscar': 'maíz & trigo'});
    },
  );

  test('Rechaza URLs base incompletas o con credenciales y parámetros', () {
    for (final url in [
      '',
      'localhost:8000/api',
      'ftp://example.test/api',
      'https://usuario:clave@example.test/api',
      'https://example.test/api?token=secreto',
      'https://example.test/api#fragmento',
    ]) {
      expect(() => ApiConfig(baseUrl: url), throwsArgumentError, reason: url);
    }
    expect(
      () => ApiConfig(
        baseUrl: 'https://example.test/api',
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('Rechaza rutas que podrían salir de la API configurada', () {
    final config = ApiConfig(baseUrl: 'https://example.test/api');
    for (final path in [
      '',
      'https://otro.example/me',
      '//otro.example/me',
      '/me',
      '../me',
      'lotes/../../me',
      '%2e%2e/me',
      'me?token=secreto',
      'me#fragmento',
    ]) {
      expect(() => config.endpoint(path), throwsArgumentError, reason: path);
    }
  });
}
