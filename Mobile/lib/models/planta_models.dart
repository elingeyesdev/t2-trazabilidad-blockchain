import 'api_exception.dart';
import 'auth_user.dart';

abstract final class PlantaPermissions {
  static bool isOperarioPlanta(AuthUser user) =>
      user.roles.contains('planta') &&
      !user.roles.contains('jefe_planta') &&
      !user.roles.contains('admin');

  static bool canViewTareas(AuthUser user) =>
      user.permissions.contains('lote_produccion.view') &&
      isOperarioPlanta(user);

  static bool canViewRecepciones(AuthUser user) =>
      user.permissions.contains('recepcion_planta.view');

  static bool canConfirmRecepcion(AuthUser user) =>
      !user.roles.contains('admin') &&
      user.permissions.contains('recepcion_planta.confirm');
}

class TareaPlantaSummary {
  const TareaPlantaSummary({
    required this.id,
    required this.orden,
    required this.estado,
    required this.loteProduccionId,
    required this.procesoNombre,
    required this.maquinaNombre,
    this.maquinaId,
    this.maquinaCodigo,
    this.maquinaActiva = true,
    this.loteCodigo,
    this.loteNombre,
    this.loteProducto,
    this.loteFechaCreacion,
    this.creadoEn,
    this.completadaEn,
    this.observaciones,
  });

  factory TareaPlantaSummary.fromJson(Map<String, dynamic> row) {
    final id = _asInt(row['asignacionetapaplantaid']) ?? 0;
    final procesoMap = row['proceso'] is Map<String, dynamic>
        ? row['proceso'] as Map<String, dynamic>
        : null;
    final maquinaMap = row['maquina'] is Map<String, dynamic>
        ? row['maquina'] as Map<String, dynamic>
        : null;
    final loteMap = row['lote_produccion'] is Map<String, dynamic>
        ? row['lote_produccion'] as Map<String, dynamic>
        : null;
    return TareaPlantaSummary(
      id: id,
      orden: _asInt(row['orden']) ?? 0,
      estado: (_asText(row['estado']) ?? 'pendiente').toLowerCase(),
      loteProduccionId: _asInt(loteMap?['loteproduccionpedidoid']) ?? 0,
      procesoNombre: _asText(procesoMap?['nombre']) ?? 'Proceso #$id',
      maquinaId: _asInt(maquinaMap?['maquinaplantaid']),
      maquinaNombre: _asText(maquinaMap?['nombre']) ?? 'Sin máquina asignada',
      maquinaCodigo: _asText(maquinaMap?['codigo']),
      maquinaActiva: maquinaMap?['activo'] != false,
      loteCodigo: _asText(loteMap?['codigo_lote']),
      loteNombre: _asText(loteMap?['nombre']),
      loteProducto: _asText(loteMap?['producto']),
      loteFechaCreacion: _asText(loteMap?['fecha_creacion']),
      creadoEn: _asText(row['creado_en']),
      completadaEn: _asText(row['completada_en']),
      observaciones: _asText(row['observaciones']),
    );
  }

  final int id;
  final int orden;
  final String estado;
  final int loteProduccionId;
  final String procesoNombre;
  final int? maquinaId;
  final String maquinaNombre;
  final String? maquinaCodigo;
  final bool maquinaActiva;
  final String? loteCodigo;
  final String? loteNombre;
  final String? loteProducto;
  final String? loteFechaCreacion;
  final String? creadoEn;
  final String? completadaEn;
  final String? observaciones;

  bool get isCompleted => estado == 'completada';
  bool get isCancelled => estado == 'cancelada';

  String get estadoLabel => switch (estado) {
    'pendiente' => 'Pendiente',
    'programada' => 'Programada',
    'completada' => 'Completada',
    'cancelada' => 'Cancelada',
    _ => estado,
  };

  String get loteLabel {
    final parts = [?loteCodigo, ?loteNombre];
    return parts.isEmpty
        ? 'Lote industrial #$loteProduccionId'
        : parts.join(' · ');
  }

  String get maquinaLabel =>
      maquinaCodigo == null ? maquinaNombre : '$maquinaNombre ($maquinaCodigo)';
}

class TareasPlantaPage {
  const TareasPlantaPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  factory TareasPlantaPage.fromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException(
        'No pudimos interpretar las tareas de planta asignadas.',
      );
    }
    final items = <TareaPlantaSummary>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final item = TareaPlantaSummary.fromJson(row);
      if (item.id > 0) items.add(item);
    }
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final meta = map['meta'] is Map<String, dynamic>
        ? map['meta'] as Map<String, dynamic>
        : map;
    return TareasPlantaPage(
      items: items,
      currentPage: _asInt(meta['current_page']) ?? 1,
      lastPage: _asInt(meta['last_page']) ?? 1,
      total: _asInt(meta['total']) ?? items.length,
    );
  }

  final List<TareaPlantaSummary> items;
  final int currentPage;
  final int lastPage;
  final int total;
}

class ParametroRequerido {
  const ParametroRequerido({
    required this.variableEstandarId,
    required this.nombre,
    this.unidad,
    this.valorMinimo,
    this.valorMaximo,
  });

  factory ParametroRequerido.fromJson(Map<String, dynamic> row) =>
      ParametroRequerido(
        variableEstandarId: _asInt(row['variableestandarid']) ?? 0,
        nombre: _asText(row['nombre']) ?? 'Parámetro',
        unidad: _asText(row['unidad']),
        valorMinimo: _asDouble(row['valor_minimo']),
        valorMaximo: _asDouble(row['valor_maximo']),
      );

  final int variableEstandarId;
  final String nombre;
  final String? unidad;
  final double? valorMinimo;
  final double? valorMaximo;

  String? get rangeHint {
    if (valorMinimo == null || valorMaximo == null) return null;
    final min = _formatNumber(valorMinimo!);
    final max = _formatNumber(valorMaximo!);
    final unit = unidad == null || unidad!.isEmpty ? '' : ' $unidad';
    return 'Rango permitido: $min a $max$unit';
  }
}

class ResultadoParametro {
  const ResultadoParametro({
    required this.variableEstandarId,
    required this.nombre,
    required this.valor,
    this.unidad,
  });

  factory ResultadoParametro.fromJson(Map<String, dynamic> row) =>
      ResultadoParametro(
        variableEstandarId: _asInt(row['variableestandarid']) ?? 0,
        nombre: _asText(row['nombre']) ?? 'Parámetro',
        valor: _asText(row['valor_decimal']) ?? _asText(row['valor']) ?? '-',
        unidad: _asText(row['unidad']),
      );

  final int variableEstandarId;
  final String nombre;
  final String valor;
  final String? unidad;

  String get formattedValue =>
      unidad == null || unidad!.isEmpty ? valor : '$valor $unidad';
}

class TareaPlantaDetail {
  const TareaPlantaDetail({
    required this.tarea,
    required this.puedeCompletar,
    this.requisitoPendiente,
    this.maquinasElegibles = const [],
    this.parametrosRequeridos = const [],
    this.resultadoParametros = const [],
    this.fechaRegistro,
  });

  factory TareaPlantaDetail.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const ApiException(
        'No pudimos interpretar el detalle de la tarea.',
      );
    }
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final tarea = TareaPlantaSummary.fromJson(data);
    if (tarea.id <= 0) {
      throw const ApiException('La tarea de planta recibida no es válida.');
    }
    final meta = json['meta'] is Map<String, dynamic>
        ? json['meta'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final elegibles = <int>[];
    if (meta['maquinas_elegibles'] is List) {
      for (final id in meta['maquinas_elegibles'] as List) {
        final parsed = _asInt(id);
        if (parsed != null && parsed > 0) elegibles.add(parsed);
      }
    }
    final requeridos = <ParametroRequerido>[];
    if (meta['parametros_requeridos'] is List) {
      for (final row in meta['parametros_requeridos'] as List) {
        if (row is Map<String, dynamic>) {
          final param = ParametroRequerido.fromJson(row);
          if (param.variableEstandarId > 0) requeridos.add(param);
        }
      }
    }
    final resultadoMap = data['resultado'] is Map<String, dynamic>
        ? data['resultado'] as Map<String, dynamic>
        : null;
    final resultadoParams = <ResultadoParametro>[];
    if (resultadoMap?['parametros'] is List) {
      for (final row in resultadoMap!['parametros'] as List) {
        if (row is Map<String, dynamic>) {
          resultadoParams.add(ResultadoParametro.fromJson(row));
        }
      }
    }
    return TareaPlantaDetail(
      tarea: tarea,
      puedeCompletar: meta['puede_completar'] == true,
      requisitoPendiente: _asText(meta['requisito_pendiente']),
      maquinasElegibles: elegibles,
      parametrosRequeridos: requeridos,
      resultadoParametros: resultadoParams,
      fechaRegistro: _asText(resultadoMap?['fecha_registro']),
    );
  }

  final TareaPlantaSummary tarea;
  final bool puedeCompletar;
  final String? requisitoPendiente;
  final List<int> maquinasElegibles;
  final List<ParametroRequerido> parametrosRequeridos;
  final List<ResultadoParametro> resultadoParametros;
  final String? fechaRegistro;
}

class RecepcionLinea {
  const RecepcionLinea({
    required this.detallePedidoId,
    required this.producto,
    required this.cantidadEnviada,
    required this.unidad,
    this.produccionAlmacenamientoId,
    this.produccionId,
    this.loteId,
    this.cantidadRecibida,
  });

  factory RecepcionLinea.fromJson(
    Map<String, dynamic> row, {
    String? receivedOverride,
  }) => RecepcionLinea(
    detallePedidoId: _asInt(row['detallepedidoid']) ?? 0,
    producto: _asText(row['producto']) ?? 'Materia prima',
    cantidadEnviada: _asText(row['cantidad_enviada']) ?? '0',
    unidad: _asText(row['unidad']) ?? 'kg',
    produccionAlmacenamientoId: _asInt(row['produccionalmacenamientoid']),
    produccionId: _asInt(row['produccionid']),
    loteId: _asInt(row['loteid']),
    cantidadRecibida: receivedOverride ?? _asText(row['cantidad_recibida']),
  );

  final int detallePedidoId;
  final String producto;
  final String cantidadEnviada;
  final String unidad;
  final int? produccionAlmacenamientoId;
  final int? produccionId;
  final int? loteId;
  final String? cantidadRecibida;

  double get enviadaValue =>
      double.tryParse(cantidadEnviada.replaceAll(',', '.')) ?? 0;

  String get formattedEnviada =>
      '${_formatDecimalText(cantidadEnviada)} $unidad';

  String? get formattedRecibida => cantidadRecibida == null
      ? null
      : '${_formatDecimalText(cantidadRecibida!)} $unidad';

  String get origenLoteLabel {
    if (loteId != null && loteId! > 0) {
      return produccionId != null && produccionId! > 0
          ? 'Lote #$loteId · Cosecha #$produccionId'
          : 'Lote #$loteId';
    }
    return 'Sin lote de origen vinculado';
  }
}

class RecepcionPlantaRecord {
  const RecepcionPlantaRecord({
    required this.pedidoId,
    required this.numeroSolicitud,
    required this.estado,
    this.envioId,
    this.almacenId,
    this.fechaRecepcion,
    this.lineas = const [],
  });

  factory RecepcionPlantaRecord.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const ApiException(
        'No pudimos interpretar la recepción de planta.',
      );
    }
    final row = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    final pedidoId = _asInt(row['pedidoid']) ?? 0;
    final receivedByLine = <int, String>{};
    if (row['recepcion'] is List) {
      for (final item in row['recepcion'] as List) {
        if (item is! Map<String, dynamic>) continue;
        final id = _asInt(item['detallepedidoid']);
        final qty =
            _asText(item['cantidad_recibida']) ?? _asText(item['cantidad']);
        if (id != null && qty != null) {
          receivedByLine[id] = qty;
        }
      }
    }
    final lineas = <RecepcionLinea>[];
    if (row['lineas'] is List) {
      for (final item in row['lineas'] as List) {
        if (item is! Map<String, dynamic>) continue;
        final id = _asInt(item['detallepedidoid']) ?? 0;
        final line = RecepcionLinea.fromJson(
          item,
          receivedOverride: receivedByLine[id],
        );
        if (line.detallePedidoId > 0) lineas.add(line);
      }
    }
    return RecepcionPlantaRecord(
      pedidoId: pedidoId,
      numeroSolicitud: _asText(row['numero_solicitud']) ?? 'Pedido #$pedidoId',
      estado: (_asText(row['estado']) ?? 'pendiente').toLowerCase(),
      envioId: _asInt(row['envioasignacionmultipleid']),
      almacenId: _asInt(row['almacenid']),
      fechaRecepcion: _asText(row['fecha_recepcion_planta']),
      lineas: lineas,
    );
  }

  final int pedidoId;
  final String numeroSolicitud;
  final String estado;
  final int? envioId;
  final int? almacenId;
  final String? fechaRecepcion;
  final List<RecepcionLinea> lineas;

  bool get isReceived => fechaRecepcion != null;

  String get estadoLabel => isReceived ? 'Recibida' : 'Pendiente de recepción';
}

class RecepcionesPlantaPage {
  const RecepcionesPlantaPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  factory RecepcionesPlantaPage.fromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException(
        'No pudimos interpretar las recepciones de planta.',
      );
    }
    final items = <RecepcionPlantaRecord>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final item = RecepcionPlantaRecord.fromJson(row);
      if (item.pedidoId > 0) items.add(item);
    }
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final meta = map['meta'] is Map<String, dynamic>
        ? map['meta'] as Map<String, dynamic>
        : map;
    return RecepcionesPlantaPage(
      items: items,
      currentPage: _asInt(meta['current_page']) ?? 1,
      lastPage: _asInt(meta['last_page']) ?? 1,
    );
  }

  final List<RecepcionPlantaRecord> items;
  final int currentPage;
  final int lastPage;
}

String _formatDecimalText(String raw) {
  final trimmed = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$').hasMatch(trimmed)) return trimmed;
  if (!trimmed.contains('.')) return trimmed;
  return trimmed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String? validateRecepcionQuantity(String? raw, {required double maxEnviada}) {
  final normalized = (raw ?? '').trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return 'Indica la cantidad recibida en kg.';
  }
  if (!RegExp(
    r'^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$',
  ).hasMatch(normalized)) {
    return 'Indica una cantidad positiva con hasta seis decimales.';
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) {
    return 'La cantidad recibida debe ser mayor que cero.';
  }
  if (parsed > maxEnviada + 1e-9) {
    final maxText = _formatDecimalText(maxEnviada.toStringAsFixed(6));
    return 'No puede superar la cantidad enviada ($maxText kg).';
  }
  return null;
}

String _formatNumber(double value) {
  final fixed = value.toStringAsFixed(6);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
  return null;
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
