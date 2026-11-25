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

  const adminUser = {
    'usuarioid': 1,
    'nombre': 'Admin',
    'apellido': 'Sistema',
    'email': 'admin@agrofusion.test',
    'nombreusuario': 'admin',
    'activo': true,
    'estado_cuenta': 'aprobado',
    'roles': [
      {'name': 'admin'},
    ],
    'permissions': ['usuarios.admin'],
  };

  http.Response jsonResponse(Object? value, [int status = 200]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> openUsuariosModule(WidgetTester tester, ApiClient api) async {
    await tester.pumpWidget(
      AgroFusionApp(apiClient: api, sessionStorage: storage),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trabajo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Admin abre detalle de usuario pendiente desde Usuarios, ve datos reales y aprueba la solicitud',
    (tester) async {
      await storage.saveToken('1|admin-token');

      var aprobado = false;
      var approvePostCount = 0;

      Map<String, dynamic> robertoJson() => {
        'usuarioid': 25,
        'nombre': 'Roberto',
        'apellido': 'Mar',
        'email': 'RM@agrofusion.com',
        'nombreusuario': 'rmar',
        'telefono': null,
        'role': 'agricultor',
        'rol_solicitado': 'agricultor',
        'roles': [
          {'nombre': 'agricultor'},
        ],
        'estado_cuenta': aprobado ? 'aprobado' : 'pendiente',
        'carta_motivacion': null,
        'ci_nit': null,
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/health') {
            return jsonResponse({'status': 'ok'});
          }
          if (request.url.path == '/api/me' && request.method == 'GET') {
            return jsonResponse(adminUser);
          }
          if (request.url.path == '/api/usuarios' && request.method == 'GET') {
            return jsonResponse({
              'data': [robertoJson()],
              'current_page': 1,
              'last_page': 1,
              'total': 1,
            });
          }
          if (request.url.path == '/api/usuarios/25' &&
              request.method == 'GET') {
            return jsonResponse({'user': robertoJson()});
          }
          if (request.url.path == '/api/usuarios/25/aprobar' &&
              request.method == 'POST') {
            approvePostCount++;
            aprobado = true;
            return jsonResponse({
              'message': 'Solicitud de Roberto Mar aprobada.',
              'user': robertoJson(),
            });
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );

      await openUsuariosModule(tester, api);

      expect(find.text('Roberto'), findsOneWidget);
      await tester.tap(find.text('Roberto'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle de usuario'), findsOneWidget);
      expect(find.text('Roberto Mar'), findsOneWidget);
      expect(find.text('Agricultor (Operario)'), findsWidgets);
      expect(find.text('@rmar'), findsOneWidget);
      expect(find.text('RM@agrofusion.com'), findsWidgets);
      expect(find.text('No registrado'), findsOneWidget);
      expect(find.text('Carta de motivación'), findsNothing);

      final approveBtn = find.byKey(const ValueKey('usuario.aprobar'));
      await tester.ensureVisible(approveBtn);
      await tester.tap(approveBtn);
      await tester.pumpAndSettle();

      expect(find.text('¿Aprobar solicitud de registro?'), findsOneWidget);
      await tester.tap(find.text('Aprobar solicitud'));
      await tester.pumpAndSettle();

      expect(approvePostCount, 1);
      expect(find.text('Solicitud de Roberto Mar aprobada.'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(find.byKey(const ValueKey('usuario.aprobar')), findsNothing);
      expect(find.byKey(const ValueKey('usuario.rechazar')), findsNothing);
    },
  );

  testWidgets(
    'Admin puede rechazar una solicitud pendiente y vuelve al listado actualizado',
    (tester) async {
      await storage.saveToken('1|admin-token');

      var rechazado = false;
      var rejectPostCount = 0;

      const carlosJson = {
        'usuarioid': 26,
        'nombre': 'Carlos',
        'apellido': 'Paz',
        'email': 'carlos@agrofusion.com',
        'nombreusuario': 'cpaz',
        'telefono': '70012345',
        'role': 'minorista',
        'rol_solicitado': 'minorista',
        'estado_cuenta': 'pendiente',
        'ci_nit': '1234567',
        'carta_motivacion': 'Distribuyo papa en la zona sur.',
      };

      final api = ApiClient(
        config: ApiConfig(baseUrl: 'https://example.test/api'),
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path == '/api/health') {
            return jsonResponse({'status': 'ok'});
          }
          if (request.url.path == '/api/me' && request.method == 'GET') {
            return jsonResponse(adminUser);
          }
          if (request.url.path == '/api/usuarios' && request.method == 'GET') {
            return jsonResponse({
              'data': rechazado ? const [] : const [carlosJson],
              'current_page': 1,
              'last_page': 1,
              'total': rechazado ? 0 : 1,
            });
          }
          if (request.url.path == '/api/usuarios/26' &&
              request.method == 'GET') {
            return jsonResponse({'user': carlosJson});
          }
          if (request.url.path == '/api/usuarios/26/rechazar' &&
              request.method == 'POST') {
            rejectPostCount++;
            rechazado = true;
            return jsonResponse({'message': 'Solicitud rechazada.'});
          }
          return jsonResponse({'message': 'Not found'}, 404);
        }),
      );

      await openUsuariosModule(tester, api);

      await tester.tap(find.text('Carlos'));
      await tester.pumpAndSettle();

      expect(find.text('Carlos Paz'), findsOneWidget);

      expect(find.text('1234567'), findsOneWidget);
      expect(find.text('Distribuyo papa en la zona sur.'), findsOneWidget);

      final rejectBtn = find.byKey(const ValueKey('usuario.rechazar'));
      await tester.ensureVisible(rejectBtn);
      await tester.tap(rejectBtn);
      await tester.pumpAndSettle();

      expect(find.text('¿Rechazar esta solicitud?'), findsOneWidget);
      await tester.tap(find.text('Rechazar solicitud'));
      await tester.pumpAndSettle();

      expect(rejectPostCount, 1);
      expect(find.text('Carlos'), findsNothing);
    },
  );
}
