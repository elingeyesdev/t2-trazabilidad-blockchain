class LogoutResult {
  const LogoutResult({required this.localCleared, required this.remoteClosed});

  final bool localCleared;
  final bool remoteClosed;

  String get message {
    if (!localCleared) {
      return 'No se pudo eliminar la sesión de este dispositivo. Reintenta el cierre de sesión.';
    }
    if (!remoteClosed) {
      return 'Sesión cerrada en este dispositivo. No se pudo confirmar el cierre en el servidor.';
    }
    return 'Sesión cerrada correctamente.';
  }
}
