import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ApiClient apiWith(MockClient client) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: const SessionStorage(),
      client: client,
    );
    addTearDown(api.close);
    return api;
  }

  testWidgets(
    'No muestra opciones de comprobar conexión en inicio de sesión ni en inicio',
    (tester) async {
      final api = apiWith(
        MockClient((request) async {
          if (request.url.path == '/api/me') {
            return http.Response(
              jsonEncode({
                'usuarioid': 1,
                'nombre': 'Admin',
                'apellido': 'Sistema',
                'email': 'admin@agrofusion.com',
                'activo': true,
                'estado_cuenta': 'aprobado',
                'roles': [
                  {'id': 1, 'name': 'admin'},
                ],
                'permissions': ['lotes.view'],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{}', 404);
        }),
      );

      await tester.pumpWidget(AgroFusionApp(apiClient: api));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Comprobar conexión'), findsNothing);

      await const SessionStorage().saveToken('1|nav-check');
      await tester.pumpWidget(
        AgroFusionApp(key: const ValueKey('authenticated'), apiClient: api),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hola, Admin'), findsOneWidget);
      expect(find.text('Comprobar conexión'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
