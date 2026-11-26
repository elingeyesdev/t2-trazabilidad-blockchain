import 'dart:convert';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/screens/modules/movimientos_screen.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/widgets/movimiento_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({'agrofusion.auth_token': 't'});

  const user = AuthUser(
    id: 1,
    name: 'Ana',
    email: 'ana@example.test',
    roles: ['agricultor'],
    permissions: {'almacen.movimientos.view'},
  );

  String today() => DateTime.now().toIso8601String().substring(0, 10);

  Map<String, dynamic> row(
    int id,
    String naturaleza,
    String tipo,
    String qty,
  ) => {
    'almacen_movimientoid': id,
    'almacenid': 4,
    'insumoid': 7,
    'fecha': today(),
    'cantidad': qty,
    'unidad': 'kg',
    'saldo_anterior': '20',
    'saldo_posterior': '25',
    'insumo': {'insumoid': 7, 'nombre': 'Fertilizante NPK'},
    'almacen': {'nombre': 'Bodega Central'},
    'tipo': {'nombre': tipo, 'naturaleza': naturaleza},
    'usuario': {'nombre': 'Luis', 'apellido': 'Rojas'},
  };

  testWidgets('Explica cada movimiento en palabras y los agrupa por día', (
    tester,
  ) async {
    final queries = <String>[];
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'http://localhost/api'),
      sessionStorage: const SessionStorage(),
      client: MockClient((request) async {
        queries.add(request.url.query);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'data': [
                row(2, 'salida', 'Envío', '10'),
                row(1, 'ingreso', 'Compra', '5'),
              ],
            }),
          ),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MovimientosScreen(
          user: user,
          service: ModuleService(api),
          onRefreshPermissions: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Salida · Envío'), findsOneWidget);
    expect(find.text('Entrada · Compra'), findsOneWidget);
    expect(find.text('Quedan 25 kg (antes 20)'), findsNWidgets(2));
    expect(find.text('Almacén: Bodega Central'), findsNWidgets(2));

    await tester.tap(find.text('Salidas'));
    await tester.pumpAndSettle();
    expect(queries.last, contains('naturaleza=salida'));
  });

  test('describeDay nombra hoy, ayer y fechas anteriores', () {
    final now = DateTime(2026, 11, 23);
    expect(describeDay('2026-11-23', now: now), 'Hoy');
    expect(describeDay('2026-11-22 08:00:00', now: now), 'Ayer');
    expect(describeDay('2026-10-05', now: now), '5 de octubre');
    expect(describeDay('2025-12-31', now: now), '31 de diciembre de 2025');
    expect(describeDay('sin fecha', now: now), 'sin fecha');
  });
}
