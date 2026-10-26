import 'dart:async';

import 'package:agrofusion_mobile/app.dart';
import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/screens/auth/login_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/widgets/app_loading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  ApiClient apiWith(MockClient client) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: const SessionStorage(),
      client: client,
    );
    addTearDown(api.close);
    return api;
  }

  testWidgets('Navega a conexión, muestra carga y permite volver al inicio', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final api = apiWith(MockClient((_) => response.future));
    await tester.pumpWidget(AgroFusionApp(apiClient: api));

    await tester.tap(find.text('Comprobar conexión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AppLoading), findsOneWidget);

    response.complete(http.Response('{"ok":true}', 200));
    await tester.pumpAndSettle();
    expect(find.text('Conexión disponible'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Permite reintentar después de un error del servidor', (
    tester,
  ) async {
    var attempts = 0;
    final api = apiWith(
      MockClient((_) async {
        attempts++;
        return attempts == 1
            ? http.Response('', 503)
            : http.Response('{"ok":true}', 200);
      }),
    );
    await tester.pumpWidget(AgroFusionApp(apiClient: api));

    await tester.tap(find.text('Comprobar conexión'));
    await tester.pumpAndSettle();
    expect(
      find.text('El servidor no está disponible. Intenta más tarde.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Conexión disponible'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
