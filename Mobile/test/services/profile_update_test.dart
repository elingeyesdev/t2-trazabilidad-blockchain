import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agrofusion_mobile/config/api_config.dart';
import 'package:agrofusion_mobile/models/api_exception.dart';
import 'package:agrofusion_mobile/models/profile_photo.dart';
import 'package:agrofusion_mobile/services/api_client.dart';
import 'package:agrofusion_mobile/services/auth_service.dart';
import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const updatedProfile = {
  'usuarioid': 1,
  'nombre': 'Ana',
  'email': 'ana@example.test',
  'activo': true,
  'estado_cuenta': 'aprobado',
  'nombreusuario': 'ana.nueva',
  'nombreusuario_editado': true,
  'profile_capabilities': {'update_username': false, 'update_photo': true},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = SessionStorage();
  http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  AuthService serviceWith(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final api = ApiClient(
      config: ApiConfig(baseUrl: 'https://example.test/api'),
      sessionStorage: storage,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    return AuthService(api, storage);
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await storage.saveToken('1|token-perfil');
  });

  test(
    'Actualiza únicamente nombreusuario con PATCH y conserva las capacidades del servidor',
    () async {
      final service = serviceWith((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.toString(), 'https://example.test/api/me');
        expect(request.headers['Authorization'], 'Bearer 1|token-perfil');
        expect(jsonDecode(request.body), {'nombreusuario': 'ana.nueva'});
        expect(request.followRedirects, isFalse);
        return jsonResponse(updatedProfile);
      });
      final user = await service.updateProfile(
        userId: 1,
        username: ' ana.nueva ',
      );
      expect(user.username, 'ana.nueva');
      expect(user.canUpdateUsername, isFalse);
      expect(user.canUpdatePhoto, isTrue);
    },
  );

  for (final withName in [false, true]) {
    test(
      'Envía la fotografía multipart ${withName ? 'con nombre' : 'sin reenviar un nombre bloqueado'}',
      () async {
        final photo = ProfilePhoto(
          Uint8List.fromList([0, 255, 13, 10, 42]),
          name: 'C:/privado/FOTO.PNG',
        );
        final service = serviceWith((request) async {
          expect(request.method, 'POST');
          expect(request.headers['Accept'], 'application/json');
          expect(request.headers['Authorization'], 'Bearer 1|token-perfil');
          expect(
            request.headers['Content-Type'],
            contains('multipart/form-data; boundary='),
          );
          expect(request.followRedirects, isFalse);
          final body = latin1.decode(request.bodyBytes);
          expect(body, contains('name="_method"\r\n\r\nPATCH'));
          expect(body, contains('name="imagen"; filename="perfil.png"'));
          expect(body, contains('content-type: image/png'));
          expect(body, contains(latin1.decode(photo.bytes)));
          expect(body.contains('name="nombreusuario"'), withName);
          expect(body, isNot(contains('privado')));
          expect(body, isNot(contains('name="usuarioid"')));
          return jsonResponse(updatedProfile);
        });
        expect(
          (await service.updateProfile(
            userId: 1,
            username: withName ? 'ana.nueva' : null,
            photo: photo,
          )).id,
          1,
        );
      },
    );
  }

  test(
    'Rechaza una escritura vacía y una sesión ausente antes de enviar HTTP',
    () async {
      var calls = 0;
      final service = serviceWith((_) async {
        calls++;
        return jsonResponse(updatedProfile);
      });
      await expectLater(
        service.updateProfile(userId: 1),
        throwsA(isA<ApiException>()),
      );
      await storage.clearToken();
      await expectLater(
        service.updateProfile(userId: 1, username: 'ana.nueva'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'estado', 401)),
      );
      expect(calls, 0);
    },
  );

  for (final status in [403, 422, 503]) {
    test('Conserva la sesión y los errores de escritura $status', () async {
      final service = serviceWith(
        (_) async => jsonResponse({
          'message': 'Cambio rechazado',
          'errors': {
            'nombreusuario': ['Nombre no disponible'],
          },
        }, status),
      );
      await expectLater(
        service.updateProfile(userId: 1, username: 'ana.nueva'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'estado', status),
        ),
      );
      expect(await storage.readToken(), '1|token-perfil');
    });
  }

  test(
    'Un 401 multipart limpia la sesión mediante el cliente compartido',
    () async {
      final service = serviceWith((_) async => jsonResponse({}, 401));
      await expectLater(
        service.updateProfile(
          userId: 1,
          photo: ProfilePhoto(Uint8List.fromList([1]), name: 'foto.jpg'),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'estado', 401)),
      );
      expect(await storage.readToken(), isNull);
    },
  );

  test(
    'No acepta una respuesta tardía si otra sesión reemplazó el token',
    () async {
      final pending = Completer<http.Response>();
      final service = serviceWith((_) => pending.future);
      final result = expectLater(
        service.updateProfile(userId: 1, username: 'ana.nueva'),
        throwsA(isA<ApiException>()),
      );
      await Future<void>.delayed(Duration.zero);
      await storage.saveToken('2|token-nuevo');
      pending.complete(jsonResponse(updatedProfile));
      await result;
      expect(await storage.readToken(), '2|token-nuevo');
    },
  );

  test(
    'No acepta un perfil ajeno ni una respuesta exitosa malformada',
    () async {
      for (final response in [
        {...updatedProfile, 'usuarioid': 2},
        {'ok': true},
      ]) {
        final service = serviceWith((_) async => jsonResponse(response));
        await expectLater(
          service.updateProfile(userId: 1, username: 'ana.nueva'),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  test(
    'La fotografía limita tamaño y formato y conserva los bytes originales',
    () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final photo = ProfilePhoto(bytes, name: 'FOTO.JPEG');
      bytes[0] = 9;
      expect(photo.bytes, [1, 2, 3]);
      expect(photo.contentType, 'image/jpeg');
      expect(() => photo.bytes[0] = 7, throwsUnsupportedError);
      expect(
        () => ProfilePhoto(Uint8List(0), name: 'a.png'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => ProfilePhoto(Uint8List(ProfilePhoto.maxBytes + 1), name: 'a.png'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => ProfilePhoto(Uint8List(1), name: 'a.heic'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
