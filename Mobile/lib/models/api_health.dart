class ApiHealth {
  const ApiHealth({required this.ok});

  factory ApiHealth.fromJson(Object? json) {
    if (json case {'ok': bool ok}) {
      return ApiHealth(ok: ok);
    }
    throw const FormatException('La respuesta debe incluir un booleano ok.');
  }

  final bool ok;
}
