import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/screens/modules/lote_activity_history_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const storage = SessionStorage();
  const user = AuthUser(
    id: 1,
    name: 'Ana',
    email: 'ana@example.test',
    permissions: {'lotes.view'},
  );
  const lots = [
    {'loteid': 7, 'nombre': 'Parcela Norte'},
    {'loteid': 8, 'nombre': 'Parcela Sur'},
  ];
  const north = {
    'actividadid': 71,
    'loteid': 7,
    'descripcion': 'Riego del Norte',
    'lote': {'loteid': 7, 'nombre': 'Parcela Norte'},
  };
  const northSecond = {
    'actividadid': 72,
    'loteid': 7,
    'descripcion': 'Abono del Norte',
  };
  const south = {
    'actividadid': 81,
    'loteid': 8,
    'descripcion': 'Revisión del Sur',
  };

  http.Response json(Object? value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, Object?> page(
    List<Object?> rows, {
    int number = 1,
    int last = 1,
  }) => {
    'data': rows,
    'meta': {'current_page': number, 'last_page': last},
  };

  ApiClient client(Future<http.Response> Function(http.Request) handler) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    return api;
  }

  Widget history(ModuleService service, int id, String name) => MaterialApp(
    theme: AppTheme.light,
    home: LoteActivityHistoryScreen(
      loteId: id,
      loteName: name,
      user: user,
      service: service,
      onRefreshPermissions: () {},
    ),
  );

  Future<void> openHistory(WidgetTester tester, String lotName) async {
    await tester.tap(find.text(lotName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Historial de actividades'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|historial-lote');
  });

  testWidgets(
    'Cambiar de lote no conserva actividades ni la página del anterior',
    (tester) async {
      final calls = <String>[];
      final api = client((request) async {
        if (request.url.path == '/api/me') {
          return json({
            'usuarioid': 1,
            'nombre': 'Ana',
            'email': 'ana@example.test',
            'activo': true,
            'estado_cuenta': 'aprobado',
            'permissions': ['lotes.view'],
          });
        }
        if (request.url.path == '/api/lotes') return json(page(lots));
        if (request.url.path.endsWith('/actividades')) {
          final id = request.url.pathSegments[2];
          final number = int.parse(request.url.queryParameters['page']!);
          calls.add('$id:$number');
          return json(
            page(
              [
                id == '8'
                    ? south
                    : number == 1
                    ? north
                    : northSecond,
              ],
              number: number,
              last: id == '7' ? 2 : 1,
            ),
          );
        }
        final id = int.parse(request.url.pathSegments.last);
        return json({'data': lots.singleWhere((lot) => lot['loteid'] == id)});
      });
      await tester.pumpWidget(AgroFusionApp(apiClient: api));
      await tester.pumpAndSettle();
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .pushNamed('/modules/lotes'),
      );
      await tester.pumpAndSettle();

      await openHistory(tester, 'Parcela Norte');
      expect(find.text('Lote #7'), findsOneWidget);
      expect(find.text('Riego del Norte'), findsOneWidget);
      expect(find.text('Revisión del Sur'), findsNothing);
      await tester.scrollUntilVisible(find.text('Siguiente'), 200);
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Abono del Norte'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Volver al lote'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volver a la lista'));
      await tester.pumpAndSettle();

      await openHistory(tester, 'Parcela Sur');
      expect(find.text('Lote #8'), findsOneWidget);
      expect(find.text('Parcela Sur'), findsOneWidget);
      expect(find.text('Revisión del Sur'), findsOneWidget);
      expect(find.text('Riego del Norte'), findsNothing);
      expect(find.text('Abono del Norte'), findsNothing);
      expect(find.text('Página 2 de 2'), findsNothing);
      expect(calls, ['7:1', '7:2', '8:1']);
    },
  );

  for (final mismatch in ['actividad', 'lote relacionado']) {
    testWidgets('Rechaza una página que mezcla lotes en $mismatch', (
      tester,
    ) async {
      var calls = 0;
      final api = client((request) async {
        final number = int.parse(request.url.queryParameters['page']!);
        calls++;
        if (number == 1) return json(page([north], last: 2));
        return json(
          page(
            [
              northSecond,
              if (calls == 2)
                mismatch == 'actividad'
                    ? south
                    : {
                        ...north,
                        'lote': {'loteid': 8, 'nombre': 'Parcela Sur'},
                      },
            ],
            number: 2,
            last: 2,
          ),
        );
      });
      await tester.pumpWidget(history(ModuleService(api), 7, 'Parcela Norte'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Siguiente'), 200);
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'La información recibida no corresponde al historial solicitado.',
        ),
        findsOneWidget,
      );
      expect(find.text('Riego del Norte'), findsNothing);
      expect(find.text('Abono del Norte'), findsNothing);
      expect(find.text('Revisión del Sur'), findsNothing);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Abono del Norte'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Página 2 de 2'), 200);
      expect(find.text('Página 2 de 2'), findsOneWidget);
      expect(calls, 3);
    });
  }

  testWidgets(
    'Una respuesta tardía del lote anterior no sustituye el historial actual',
    (tester) async {
      final delayed = Completer<http.Response>();
      final calls = <String>[];
      final api = client((request) async {
        final id = request.url.pathSegments[2];
        final number = int.parse(request.url.queryParameters['page']!);
        calls.add('$id:$number');
        if (id == '7' && number == 2) return delayed.future;
        return json(page([id == '7' ? north : south], last: id == '7' ? 2 : 1));
      });
      final service = ModuleService(api);
      await tester.pumpWidget(history(service, 7, 'Parcela Norte'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Siguiente'), 200);
      await tester.tap(find.text('Siguiente'));
      await tester.pump();
      expect(find.text('Cargando historial...'), findsOneWidget);
      await tester.pumpWidget(history(service, 8, 'Parcela Sur'));
      await tester.pumpAndSettle();
      expect(find.text('Lote #8'), findsOneWidget);
      expect(find.text('Revisión del Sur'), findsOneWidget);
      delayed.complete(json(page([northSecond], number: 2, last: 2)));
      await tester.pumpAndSettle();
      expect(find.text('Revisión del Sur'), findsOneWidget);
      expect(find.text('Abono del Norte'), findsNothing);
      await tester.pumpWidget(history(service, 7, 'Parcela Norte'));
      await tester.pumpAndSettle();
      expect(find.text('Riego del Norte'), findsOneWidget);
      expect(find.text('Revisión del Sur'), findsNothing);
      expect(calls, ['7:1', '7:2', '8:1', '7:1']);
    },
  );
}
