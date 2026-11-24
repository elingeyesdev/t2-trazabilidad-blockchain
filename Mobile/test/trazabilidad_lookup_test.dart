import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();

  const approvedUser = {
    'usuarioid': 12,
    'nombre': 'Lucía',
    'apellido': 'Quispe',
    'email': 'lucia@agrofusion.test',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'id': 3, 'name': 'minorista'},
    ],
    'permissions': ['pedidos_distribucion.view'],
  };

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Un consumidor sin sesión puede abrir la consulta de trazabilidad desde LoginScreen',
    (tester) async {
      var authCalls = 0;
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          authCalls++;
          return jsonResponse({'message': 'Unexpected call'}, 500);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(apiClient: api, sessionStorage: storage),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('login.trazabilidad_publica'));
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Consultar trazabilidad'), findsOneWidget);
      expect(authCalls, 0);
    },
  );

  testWidgets(
    'Un usuario autenticado también cuenta con acceso rápido a trazabilidad desde Inicio',
    (tester) async {
      await storage.saveToken('1|minorista-token');
      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/me') {
            return jsonResponse(approvedUser);
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );
      addTearDown(api.close);

      await tester.pumpWidget(
        AgroFusionApp(apiClient: api, sessionStorage: storage),
      );
      await tester.pumpAndSettle();

      final shortcut = find.byKey(const ValueKey('home.trazabilidad_publica'));
      expect(shortcut, findsOneWidget);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();

      expect(find.text('Consultar trazabilidad'), findsOneWidget);
    },
  );
}
