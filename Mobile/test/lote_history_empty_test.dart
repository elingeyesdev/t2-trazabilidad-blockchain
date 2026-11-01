import 'dart:async';
import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/screens/modules/lote_activity_history_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/theme/app_theme.dart';
import 'package:agrofusion_mobile/widgets/activity_history_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const emptyTitle = 'No hay actividades para mostrar';
  const user = AuthUser(
    id: 1,
    name: 'Ana',
    email: 'ana@example.test',
    permissions: {'lotes.view'},
  );
  const activity = {
    'actividadid': 71,
    'loteid': 7,
    'descripcion': 'Riego del sector norte',
    'fechafin': null,
  };

  http.Response json(Object? value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
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

  Future<void> start(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: const SessionStorage(),
      client: MockClient(handler),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LoteActivityHistoryScreen(
          loteId: 7,
          loteName: 'Parcela Norte',
          user: user,
          service: ModuleService(api),
          onRefreshPermissions: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Un historial vacío identifica el lote y permite actualizar sus actividades',
    (tester) async {
      var calls = 0;
      final pending = Completer<http.Response>();
      await start(tester, (request) async {
        expect(request.url.path, '/api/lotes/7/actividades');
        expect(request.url.queryParameters['page'], '1');
        return ++calls == 1 ? json(page([])) : pending.future;
      });
      expect(find.text(emptyTitle), findsOneWidget);
      expect(find.textContaining('Parcela Norte · #7'), findsOneWidget);
      expect(find.byType(ActivityHistoryCard), findsNothing);
      expect(find.text('Siguiente'), findsNothing);
      expect(find.text('No pudimos cargar la información'), findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Actualizar historial'),
      );
      await tester.pump();
      expect(find.text('Cargando historial...'), findsOneWidget);
      expect(find.text(emptyTitle), findsNothing);
      pending.complete(json(page([activity])));
      await tester.pumpAndSettle();
      expect(find.text('Riego del sector norte'), findsOneWidget);
      expect(find.text(emptyTitle), findsNothing);
      expect(calls, 2);
    },
  );

  testWidgets(
    'Una página que queda vacía ofrece volver al inicio del historial',
    (tester) async {
      final pages = <int>[];
      await start(tester, (request) async {
        final number = int.parse(request.url.queryParameters['page']!);
        pages.add(number);
        return json(
          page(number == 1 ? [activity] : [], number: number, last: 2),
        );
      });
      await tester.scrollUntilVisible(find.text('Siguiente'), 200);
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Esta página no tiene actividades'), findsOneWidget);
      expect(find.text(emptyTitle), findsNothing);
      await tester.tap(find.text('Volver a la primera página'));
      await tester.pumpAndSettle();
      expect(find.text('Riego del sector norte'), findsOneWidget);
      expect(pages, [1, 2, 1]);
    },
  );

  for (final failure in ['servidor', 'respuesta inválida']) {
    testWidgets('Un fallo de $failure no se presenta como un historial vacío', (
      tester,
    ) async {
      await start(
        tester,
        (_) async => failure == 'servidor'
            ? json({}, 503)
            : json({
                'data': null,
                'meta': {'current_page': 1, 'last_page': 1},
              }),
      );
      expect(find.text('No pudimos cargar la información'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text(emptyTitle), findsNothing);
    });
  }

  for (final size in [const Size(320, 740), const Size(812, 375)]) {
    testWidgets('El mensaje y su botón se leen con letras grandes en $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var calls = 0;
      await start(tester, (_) async {
        calls++;
        return json(page([]));
      });
      final update = find.widgetWithText(FilledButton, 'Actualizar historial');
      await tester.ensureVisible(update);
      await tester.tap(update);
      await tester.pumpAndSettle();
      expect(find.text(emptyTitle), findsOneWidget);
      expect(find.textContaining('Parcela Norte · #7'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Volver al lote'),
        findsOneWidget,
      );
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
