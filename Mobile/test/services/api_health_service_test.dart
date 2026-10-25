import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/api_health_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  ApiHealthService serviceFor(Object? payload) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: const SessionStorage(),
      client: MockClient((request) async {
        expect(request.url.path, '/api/test-api');
        expect(request.headers['Authorization'], isNull);
        return http.Response(jsonEncode(payload), 200);
      }),
    );
    addTearDown(api.close);
    return ApiHealthService(api);
  }

  test('Acepta el contrato público de Laravel sin leer credenciales', () async {
    expect((await serviceFor({'ok': true}).check()).ok, isTrue);
  });

  test(
    'No presenta como éxito una respuesta incompatible o negativa',
    () async {
      for (final payload in [
        {'ok': false},
        {'ok': 'true'},
        {'otro': true},
        [],
        null,
      ]) {
        await expectLater(
          serviceFor(payload).check(),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );
}
