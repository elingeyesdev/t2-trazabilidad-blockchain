import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/api_exception.dart';
import 'session_storage.dart';

class ApiClient {
  ApiClient({
    required this.config,
    required this._sessionStorage,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final ApiConfig config;
  final SessionStorage _sessionStorage;
  final http.Client _client;
  final _sessionExpired = StreamController<bool>.broadcast(sync: true);

  Stream<bool> get sessionExpired => _sessionExpired.stream;

  void _notifySessionExpired(bool localCleared) {
    if (!_sessionExpired.isClosed) _sessionExpired.add(localCleared);
  }

  Future<Object?> request(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
    Map<String, String>? fields,
    List<http.MultipartFile>? files,
    bool authenticated = true,
    String? bearerToken,
  }) async {
    final uri = config.endpoint(path, queryParameters: queryParameters);
    final abort = Completer<void>();
    final http.BaseRequest request;
    if (fields != null || files != null) {
      if (body != null) {
        throw const ApiException(
          'No se puede combinar JSON con un formulario multipart.',
        );
      }
      request =
          http.AbortableMultipartRequest(
              method,
              uri,
              abortTrigger: abort.future,
            )
            ..fields.addAll(fields ?? {})
            ..files.addAll(files ?? []);
    } else {
      final jsonRequest = http.AbortableRequest(
        method,
        uri,
        abortTrigger: abort.future,
      );
      if (body != null) {
        jsonRequest.headers['Content-Type'] = 'application/json; charset=utf-8';
        jsonRequest.body = jsonEncode(body);
      }
      request = jsonRequest;
    }
    request.followRedirects = false;
    request.headers['Accept'] = 'application/json';

    try {
      final token = authenticated
          ? bearerToken ?? await _sessionStorage.readToken()
          : null;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final response =
          await (() async {
            return http.Response.fromStream(await _client.send(request));
          })().timeout(
            config.timeout,
            onTimeout: () {
              abort.complete();
              throw TimeoutException('La API no respondió a tiempo.');
            },
          );

      if (response.statusCode == 401 && token != null) {
        try {
          final current = await _sessionStorage.readToken();
          if (current == token) {
            await _sessionStorage.clearToken();
            _notifySessionExpired(true);
          } else if (current == null) {
            _notifySessionExpired(true);
          }
        } catch (_) {
          _notifySessionExpired(false);
          throw const ApiException(
            'No se pudo limpiar el almacenamiento de sesión. Intenta de nuevo.',
            statusCode: 401,
          );
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpError(response);
      }
      if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
        return null;
      }

      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw const ApiException(
          'La API devolvió una respuesta JSON inválida.',
        );
      }
    } on TimeoutException {
      throw const ApiException(
        'La solicitud tardó demasiado. Intenta de nuevo.',
      );
    } on http.ClientException {
      throw const ApiException(
        'No se pudo conectar con el servidor. Revisa tu conexión e intenta de nuevo.',
      );
    } on PlatformException {
      throw const ApiException(
        'No se pudo acceder al almacenamiento de sesión.',
      );
    }
  }

  ApiException _httpError(http.Response response) {
    Object? payload;
    try {
      payload = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      // Un error HTTP puede contener HTML o un cuerpo vacío.
    }

    final errors = <String, List<String>>{};
    if (payload case {'errors': Map<String, dynamic> fields}) {
      for (final entry in fields.entries) {
        final messages = entry.value;
        if (messages is List) {
          errors[entry.key] = messages.whereType<String>().toList();
        }
      }
    }

    final defaultMessage = switch (response.statusCode) {
      401 => 'La sesión no es válida. Inicia sesión de nuevo.',
      403 => 'No tienes permiso para realizar esta acción.',
      422 => 'Revisa los datos enviados.',
      >= 500 => 'El servidor no está disponible. Intenta más tarde.',
      _ => 'No se pudo completar la solicitud.',
    };
    final message =
        response.statusCode < 500 &&
            payload is Map<String, dynamic> &&
            payload['message'] is String &&
            (payload['message'] as String).trim().isNotEmpty
        ? payload['message'] as String
        : defaultMessage;

    return ApiException(
      message,
      statusCode: response.statusCode,
      validationErrors: errors,
    );
  }

  void close() {
    _client.close();
    unawaited(_sessionExpired.close());
  }
}
