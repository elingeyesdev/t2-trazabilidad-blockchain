import 'dart:convert';
import 'dart:io';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/models/auth_user.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/module_service.dart';
import 'package:agrofusion_mobile/services/offline_store.dart';
import 'package:agrofusion_mobile/services/pending_queue.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:agrofusion_mobile/services/task_notifier.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  const user = AuthUser(
    id: 8,
    name: 'Lucía',
    email: 'lucia@example.test',
    roles: ['agricultor'],
    permissions: {'lotes.view'},
  );

  late Directory dir;
  late OfflineStore store;
  var online = false;
  var status = 201;
  final posted = <Map<String, dynamic>>[];
  final keys = <String?>[];

  ApiClient client() => ApiClient(
    config: ApiConfig(baseUrl: 'http://localhost/api'),
    sessionStorage: const SessionStorage(),
    offlineStore: store,
    client: MockClient((request) async {
      if (!online) throw http.ClientException('sin señal');
      if (request.method == 'POST') {
        posted.add(jsonDecode(request.body) as Map<String, dynamic>);
        keys.add(request.headers['Idempotency-Key']);
        return http.Response(
          jsonEncode(
            status == 201
                ? {'produccionid': 5, 'loteid': 3, 'cantidad': '10'}
                : {'message': 'El lote ya no existe.'},
          ),
          status,
        );
      }
      return http.Response(
        jsonEncode({
          'data': ['lote A'],
        }),
        200,
      );
    }),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline_test');
    store = OfflineStore(directory: () async => dir);
    online = false;
    status = 201;
    posted.clear();
  });

  tearDown(() => dir.delete(recursive: true));

  test('Sin señal, una lectura devuelve lo último consultado', () async {
    final api = client();
    online = true;
    await api.request('GET', 'lotes', bearerToken: 't');
    expect(api.servedFromCache.value, isFalse);

    online = false;
    final cached = await api.request('GET', 'lotes', bearerToken: 't');
    expect(cached, {
      'data': ['lote A'],
    });
    expect(api.servedFromCache.value, isTrue);

    await store.clearCache();
    await expectLater(
      api.request('GET', 'lotes', bearerToken: 't'),
      throwsA(
        isA<Object>().having(
          (e) => e.toString(),
          'mensaje',
          contains('conectar'),
        ),
      ),
    );
  });

  test('Una cosecha sin señal queda en cola y se envía al volver', () async {
    final queue = PendingQueue(store);
    final service = ModuleService(client());
    await queue.addCosecha(
      user,
      key: 'clave-1',
      label: 'Cosecha de Norte',
      loteId: 3,
      cantidad: '10',
      unidadMedidaId: 1,
    );

    expect(await queue.flush(service, user), 0);
    expect(queue.forUser(user), hasLength(1));

    // La cola sobrevive a reiniciar la app.
    final reopened = PendingQueue(store);
    await reopened.load();
    expect(reopened.forUser(user), hasLength(1));

    online = true;
    expect(await reopened.flush(service, user), 1);
    expect(reopened.forUser(user), isEmpty);
    expect(posted.single['loteid'], 3);
  });

  test('Lo que el servidor rechaza queda marcado y no se reintenta', () async {
    final queue = PendingQueue(store);
    final service = ModuleService(client());
    await queue.addCosecha(
      user,
      key: 'clave-1',
      label: 'Cosecha de Norte',
      loteId: 3,
      cantidad: '10',
      unidadMedidaId: 1,
    );
    online = true;
    status = 422;

    expect(await queue.flush(service, user), 0);
    expect(queue.forUser(user).single.error, 'El lote ya no existe.');

    status = 201;
    expect(await queue.flush(service, user), 0);
    expect(posted, hasLength(1));
  });

  test('Solo avisa de actividades nuevas, no del primer vistazo', () {
    expect(TaskNotifier.fresh(null, [1, 2]), isEmpty);
    expect(TaskNotifier.fresh([1, 2], [1, 2, 3]), [3]);
    expect(TaskNotifier.fresh([1, 2, 3], [1]), isEmpty);
  });

  test(
    'El perfil (/me) nunca sale del caché: sin señal no hay sesión vieja',
    () async {
      final api = client();
      online = true;
      await api.request('GET', 'me', bearerToken: 't');
      online = false;
      await expectLater(
        api.request('GET', 'me', bearerToken: 't'),
        throwsA(
          isA<ApiException>().having((e) => e.offline, 'offline', isTrue),
        ),
      );
    },
  );

  test('Cada envío genera una clave distinta', () {
    expect(PendingQueue.newKey(), isNot(PendingQueue.newKey()));
  });
}
