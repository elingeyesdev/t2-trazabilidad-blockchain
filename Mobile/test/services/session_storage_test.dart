import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Guarda el token para otras instancias y borra solo su propia clave',
    () async {
      const session = SessionStorage();
      const storage = FlutterSecureStorage();
      await storage.write(key: 'otra_clave', value: 'conservar');

      expect(await session.readToken(), isNull);
      await session.saveToken('1|token-de-prueba');
      expect(await const SessionStorage().readToken(), '1|token-de-prueba');

      await session.clearToken();
      expect(await session.readToken(), isNull);
      expect(await storage.read(key: 'otra_clave'), 'conservar');
    },
  );

  test(
    'Rechaza tokens vacíos o con espacios sin reemplazar la sesión',
    () async {
      const session = SessionStorage();
      await session.saveToken('1|token-valido');
      for (final token in ['', ' ', 'token con espacios', 'token\ninyectado']) {
        expect(() => session.saveToken(token), throwsArgumentError);
      }
      expect(await session.readToken(), '1|token-valido');
    },
  );
}
