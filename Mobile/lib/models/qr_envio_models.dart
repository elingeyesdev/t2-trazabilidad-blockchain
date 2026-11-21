import 'auth_user.dart';

enum EnvioTipo {
  agricola('agricola', 'Envío agrícola'),
  distribucion('distribucion', 'Envío de distribución'),
  traslado('traslado', 'Traslado planta a mayorista');

  const EnvioTipo(this.value, this.label);

  final String value;
  final String label;

  static EnvioTipo? fromValue(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final tipo in values) {
      if (tipo.value == normalized) return tipo;
    }
    return null;
  }
}

abstract final class QrPermissions {
  static bool canUseQr(AuthUser user) =>
      user.permissions.contains('recepcion_planta.view') ||
      user.permissions.contains('pedidos.view') ||
      user.permissions.contains('asignaciones.view') ||
      user.permissions.contains('pedidos_distribucion.view');
}

class EnvioDestino {
  const EnvioDestino({this.id, this.nombre, this.direccion});

  factory EnvioDestino.fromJson(Map<String, dynamic> map) => EnvioDestino(
    id: _asInt(map['id']),
    nombre: _asText(map['nombre']),
    direccion: _asText(map['direccion']),
  );

  final int? id;
  final String? nombre;
  final String? direccion;

  String get label {
    if (nombre != null && direccion != null) return '$nombre · $direccion';
    if (nombre != null) return nombre!;
    if (direccion != null) return direccion!;
    if (id != null) return 'Destino #$id';
    return 'Destino sin especificar';
  }
}

class EnvioLinea {
  const EnvioLinea({
    required this.id,
    required this.producto,
    required this.cantidadEnviada,
    required this.unidad,
    this.pedidoId,
    this.pedido,
    this.presentacion,
  });

  factory EnvioLinea.fromJson(Map<String, dynamic> map) => EnvioLinea(
    id: _asInt(map['id']) ?? 0,
    producto: _asText(map['producto']) ?? 'Producto',
    cantidadEnviada: _asText(map['cantidad_enviada']) ?? '0',
    unidad: _asText(map['unidad']) ?? 'unidades',
    pedidoId: _asInt(map['pedido_id']),
    pedido: _asText(map['pedido']),
    presentacion: _asText(map['presentacion']),
  );

  final int id;
  final String producto;
  final String cantidadEnviada;
  final String unidad;
  final int? pedidoId;
  final String? pedido;
  final String? presentacion;

  String get title =>
      presentacion != null ? '$producto · $presentacion' : producto;

  String get formattedEnviada =>
      '${_formatDecimalText(cantidadEnviada)} $unidad';
}

class EnvioRecepcionResumen {
  const EnvioRecepcionResumen({required this.id, this.fecha, this.url});

  factory EnvioRecepcionResumen.fromJson(Map<String, dynamic> map) =>
      EnvioRecepcionResumen(
        id: _asInt(map['id']) ?? 0,
        fecha: _asText(map['fecha']),
        url: _asText(map['url']),
      );

  final int id;
  final String? fecha;
  final String? url;
}

class EnvioResumen {
  const EnvioResumen({
    required this.id,
    required this.tipo,
    required this.referencia,
    required this.estado,
    this.destinos = const [],
    this.lineas = const [],
    this.fechaSalida,
    this.llegadaConfirmada,
    this.recepciones = const [],
  });

  factory EnvioResumen.fromJson(Map<String, dynamic> map) {
    final tipo =
        EnvioTipo.fromValue(_asText(map['tipo'])) ?? EnvioTipo.distribucion;
    final id = _asInt(map['id']) ?? 0;
    final fechas = map['fechas'] is Map<String, dynamic>
        ? map['fechas'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return EnvioResumen(
      id: id,
      tipo: tipo,
      referencia: _asText(map['referencia']) ?? 'Envío #$id',
      estado: (_asText(map['estado']) ?? 'pendiente').toLowerCase(),
      destinos: _parseList(map['destinos'], EnvioDestino.fromJson),
      lineas: _parseList(map['lineas'], EnvioLinea.fromJson),
      fechaSalida: _asText(fechas['salida']),
      llegadaConfirmada: _asText(fechas['llegada_confirmada']),
      recepciones: _parseList(
        map['recepciones'],
        EnvioRecepcionResumen.fromJson,
      ),
    );
  }

  final int id;
  final EnvioTipo tipo;
  final String referencia;
  final String estado;
  final List<EnvioDestino> destinos;
  final List<EnvioLinea> lineas;
  final String? fechaSalida;
  final String? llegadaConfirmada;
  final List<EnvioRecepcionResumen> recepciones;

  String get estadoLabel => switch (estado) {
    'pendiente' => 'Pendiente',
    'en_ruta' || 'en_transito' => 'En ruta',
    'en_transporte_planta' => 'En transporte a planta',
    'recibido' || 'completada' || 'entregado' => 'Completado',
    'cancelada' || 'cancelado' => 'Cancelado',
    _ => estado,
  };

  static List<T> _parseList<T>(
    Object? raw,
    T Function(Map<String, dynamic>) builder,
  ) {
    if (raw is! List) return const [];
    final items = <T>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        items.add(builder(entry));
      }
    }
    return items;
  }
}

class QrResolucionResult {
  const QrResolucionResult({
    required this.codigo,
    required this.recepcionId,
    required this.utilizado,
    required this.puedeConfirmar,
    required this.envio,
  });

  factory QrResolucionResult.fromJson(Object? json, {required String codigo}) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    final envioMap = root['envio'] is Map<String, dynamic>
        ? root['envio'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return QrResolucionResult(
      codigo: codigo,
      recepcionId: _asInt(root['recepcion_id']) ?? 0,
      utilizado: root['utilizado'] == true,
      puedeConfirmar: root['puede_confirmar'] == true,
      envio: EnvioResumen.fromJson(envioMap),
    );
  }

  final String codigo;
  final int recepcionId;
  final bool utilizado;
  final bool puedeConfirmar;
  final EnvioResumen envio;
}

String _formatDecimalText(String raw) {
  final trimmed = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$').hasMatch(trimmed)) return trimmed;
  if (!trimmed.contains('.')) return trimmed;
  return trimmed.replaceFirst(RegExp(r'\.?0+$'), '');
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
