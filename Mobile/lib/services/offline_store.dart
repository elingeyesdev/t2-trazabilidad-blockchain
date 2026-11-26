import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Archivos locales para trabajar sin señal: últimas respuestas consultadas
/// (caché de lectura) y la cola de registros por enviar.
///
/// Se guarda como JSON en la carpeta privada de la app. Las pruebas pasan
/// una carpeta temporal en [directory].
class OfflineStore {
  OfflineStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file(String name) async {
    final dir = Directory('${(await _directory()).path}/offline');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$name');
  }

  // FNV-1a (dos carriles de 32 bits compatibles con Dart VM y Web/dart2js).
  static String _name(String key) {
    var h1 = 0x811c9dc5;
    var h2 = 0x9e3779b9;
    for (final unit in key.codeUnits) {
      h1 = ((h1 ^ unit) * 0x01000193) & 0xffffffff;
      h2 = ((h2 ^ (unit + 17)) * 0x01000193) & 0xffffffff;
    }
    return 'c_${h1.toRadixString(16)}${h2.toRadixString(16)}.json';
  }

  Future<void> putCache(String key, Object? json) async {
    try {
      await (await _file(_name(key))).writeAsString(jsonEncode(json));
    } catch (_) {
      // El caché es una ayuda: si no se puede escribir, la app sigue igual.
    }
  }

  Future<Object?> getCache(String key) async {
    try {
      final file = await _file(_name(key));
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Borra lo consultado (no la cola). Se usa al cerrar sesión para que otra
  /// cuenta en el mismo teléfono no vea datos ajenos.
  Future<void> clearCache() async {
    try {
      final dir = Directory('${(await _directory()).path}/offline');
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && entity.uri.pathSegments.last.startsWith('c_')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }

  /// Lista de ids ya vistos por un usuario (para avisar solo lo nuevo).
  Future<List<int>?> readSeen(String name) async {
    try {
      final file = await _file('seen_$name.json');
      if (!await file.exists()) return null;
      return (jsonDecode(await file.readAsString()) as List).cast<int>();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSeen(String name, List<int> ids) async {
    final file = await _file('seen_$name.json');
    await file.writeAsString(jsonEncode(ids));
  }

  Future<List<Map<String, dynamic>>> readQueue() async {
    try {
      final file = await _file('queue.json');
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString());
      return data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> writeQueue(List<Map<String, dynamic>> items) async {
    final file = await _file('queue.json');
    await file.writeAsString(jsonEncode(items), flush: true);
  }
}
