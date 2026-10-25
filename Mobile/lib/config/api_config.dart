class ApiConfig {
  ApiConfig({
    required String baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : baseUri = _parseBaseUrl(baseUrl) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Debe ser positivo.');
    }
  }

  factory ApiConfig.fromEnvironment() {
    return ApiConfig(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8000/api',
      ),
    );
  }

  final Uri baseUri;
  final Duration timeout;

  Uri endpoint(String path, {Map<String, String>? queryParameters}) {
    final relative = Uri.parse(path);
    if (path.isEmpty ||
        relative.hasScheme ||
        relative.hasAuthority ||
        relative.path.startsWith('/') ||
        relative.hasQuery ||
        relative.hasFragment ||
        relative.pathSegments.any(
          (segment) => segment == '..' || segment == '.',
        )) {
      throw ArgumentError('Usa una ruta relativa a la API.');
    }

    return baseUri
        .resolveUri(relative)
        .replace(queryParameters: queryParameters);
  }

  static Uri _parseBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('API_BASE_URL debe ser una URL HTTP o HTTPS válida.');
    }

    return uri.replace(path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/');
  }
}
