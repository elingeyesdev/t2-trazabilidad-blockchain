import 'package:agrofusion_mobile/services/session_storage.dart';
import 'package:flutter/services.dart';

class FailingSessionStorage extends SessionStorage {
  bool failRead = false;
  bool failClear = false;

  @override
  Future<String?> readToken() {
    if (failRead) throw PlatformException(code: 'test-storage-read-failed');
    return super.readToken();
  }

  @override
  Future<void> clearToken() {
    if (failClear) throw PlatformException(code: 'test-storage-clear-failed');
    return super.clearToken();
  }
}
