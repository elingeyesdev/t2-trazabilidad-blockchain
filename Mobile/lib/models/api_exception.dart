class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.validationErrors = const {},
    this.offline = false,
  });

  final String message;
  final int? statusCode;
  final Map<String, List<String>> validationErrors;

  /// Sin señal o sin respuesta: el envío puede reintentarse más tarde.
  final bool offline;

  @override
  String toString() => message;
}
