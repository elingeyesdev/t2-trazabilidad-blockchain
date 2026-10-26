import 'dart:typed_data';

import 'api_exception.dart';

class ProfilePhoto {
  ProfilePhoto._(this.bytes, this.extension);

  factory ProfilePhoto(Uint8List bytes, {required String name}) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const ApiException('Selecciona una imagen de hasta 2 MB.');
    }
    final extension = name.split('.').last.toLowerCase();
    if (!_types.containsKey(extension)) {
      throw const ApiException('Selecciona una imagen JPG, PNG, WEBP o GIF.');
    }
    return ProfilePhoto._(
      Uint8List.fromList(bytes).asUnmodifiableView(),
      extension,
    );
  }

  static const maxBytes = 2048 * 1024;
  static const _types = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  final Uint8List bytes;
  final String extension;
  String get filename => 'perfil.$extension';
  String get contentType => _types[extension]!;
}
