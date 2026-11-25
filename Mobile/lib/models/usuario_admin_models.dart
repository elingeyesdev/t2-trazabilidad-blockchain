class UsuarioAdminRecord {
  const UsuarioAdminRecord({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.email,
    required this.estadoCuenta,
    required this.activo,
    this.nombreUsuario,
    this.telefono,
    this.role,
    this.rolSolicitado,
    this.roles = const [],
    this.ciNit,
    this.tipoLicencia,
    this.informacionAdicional,
    this.cartaMotivacion,
  });

  factory UsuarioAdminRecord.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    final rolesRaw = root['roles'];
    final roles = <String>[];
    if (rolesRaw is List) {
      for (final item in rolesRaw) {
        if (item is String && item.trim().isNotEmpty) {
          roles.add(item.trim());
        } else if (item is Map<String, dynamic>) {
          final name = _asText(item['name'] ?? item['nombre']);
          if (name != null) roles.add(name);
        }
      }
    }
    return UsuarioAdminRecord(
      id: _asInt(root['usuarioid'] ?? root['id']) ?? 0,
      nombre: _asText(root['nombre']) ?? '',
      apellido: _asText(root['apellido']) ?? '',
      email: _asText(root['email']) ?? '',
      estadoCuenta: (_asText(root['estado_cuenta']) ?? 'aprobado')
          .toLowerCase(),
      activo: root['activo'] != false,
      nombreUsuario: _asText(root['nombreusuario']),
      telefono: _asText(root['telefono']),
      role: _asText(root['role']),
      rolSolicitado: _asText(root['rol_solicitado']),
      roles: roles,
      ciNit: _asText(root['ci_nit']),
      tipoLicencia: _asText(root['tipo_licencia']),
      informacionAdicional: _asText(root['informacionadicional']),
      cartaMotivacion: _asText(root['carta_motivacion']),
    );
  }

  final int id;
  final String nombre;
  final String apellido;
  final String email;
  final String estadoCuenta;
  final bool activo;
  final String? nombreUsuario;
  final String? telefono;
  final String? role;
  final String? rolSolicitado;
  final List<String> roles;
  final String? ciNit;
  final String? tipoLicencia;
  final String? informacionAdicional;
  final String? cartaMotivacion;

  bool get isPending => estadoCuenta == 'pendiente';

  String get nombreCompleto {
    final full = '$nombre $apellido'.trim();
    return full.isEmpty ? 'Usuario #$id' : full;
  }

  String get estadoLabel =>
      isPending ? 'Pendiente' : (activo ? 'Activo' : 'Inactivo');

  String get rolEfectivo =>
      rolSolicitado ?? role ?? (roles.isNotEmpty ? roles.first : 'agricultor');

  String get rolLabel => _roleLabel(rolEfectivo);

  static String _roleLabel(String raw) => switch (raw.toLowerCase()) {
    'admin' => 'Administrador',
    'agricultor' => 'Agricultor (Operario)',
    'jefe_agricultor' || 'jefe_agricola' => 'Jefe Agricultor',
    'jefe_planta' => 'Jefe Planta',
    'planta' => 'Planta (Operario)',
    'mayorista' || 'jefe_mayorista' => 'Mayorista',
    'minorista' => 'Minorista',
    'transportista' => 'Transportista',
    _ => raw,
  };
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

String? _asText(Object? value) {
  if (value == null) return null;
  if (value is! String && value is! num) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
