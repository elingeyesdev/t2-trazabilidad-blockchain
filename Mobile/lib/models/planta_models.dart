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

  static bool canViewProcesamiento(AuthUser user) =>
      user.permissions.contains('lote_produccion.view');

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

class OrigenProcesamiento {
  const OrigenProcesamiento({
    required this.consumoId,
    required this.insumoId,
    required this.insumo,
    required this.almacenId,
    this.referenciaPartida,
    this.materiaPrimaLoteId,
    this.inventarioPresentacionLoteId,
    this.cantidadConsumida,
    this.cantidadUnidadesConsumidas,
    this.presentacion,
    this.unidadPresentacion,
    this.unidadRegistrada,
    this.unidadCatalogoActual,
    this.movimientoConsumoId,
    this.cantidadRecibida,
    this.unidadRecepcion,
    this.recepcionPedidoId,
    this.recepcionFecha,
    this.origenAgricolaLoteId,
    this.origenAgricolaProduccionId,
    this.origenIndustrialId,
    this.antecedenteRestringido = false,
  });

  factory OrigenProcesamiento.fromJson(Map<String, dynamic> row) {
    final recepcion = row['recepcion'] is Map<String, dynamic>
        ? row['recepcion'] as Map<String, dynamic>
        : null;
    final agricola = row['origen_agricola'] is Map<String, dynamic>
        ? row['origen_agricola'] as Map<String, dynamic>
        : null;
    return OrigenProcesamiento(
      consumoId: _asInt(row['consumo_id']) ?? 0,
      insumoId: _asInt(row['insumo_id']) ?? 0,
      insumo: _asText(row['insumo']) ?? 'Materia prima',
      almacenId: _asInt(row['almacen_id']) ?? 0,
      referenciaPartida: _asText(row['referencia_partida']),
      materiaPrimaLoteId: _asInt(row['materiaprimaloteid']),
      inventarioPresentacionLoteId: _asInt(
        row['inventario_presentacion_loteid'],
      ),
      cantidadConsumida: _asText(row['cantidad_consumida']),
      cantidadUnidadesConsumidas: _asText(row['cantidad_unidades_consumidas']),
      presentacion: _asText(row['presentacion']),
      unidadPresentacion: _asText(row['unidad_presentacion']),
      unidadRegistrada: _asText(row['unidad_registrada']),
      unidadCatalogoActual: _asText(row['unidad_catalogo_actual']),
      movimientoConsumoId: _asInt(row['movimiento_consumo_id']),
      cantidadRecibida: _asText(row['cantidad_recibida']),
      unidadRecepcion: _asText(row['unidad_recepcion']),
      recepcionPedidoId: _asInt(recepcion?['pedidoid']),
      recepcionFecha: _asText(recepcion?['fecha']),
      origenAgricolaLoteId: _asInt(agricola?['loteid']),
      origenAgricolaProduccionId: _asInt(agricola?['produccionid']),
      origenIndustrialId: _asInt(row['origen_industrial_id']),
      antecedenteRestringido: row['antecedente_restringido'] == true,
    );
  }

  final int consumoId;
  final int insumoId;
  final String insumo;
  final int almacenId;
  final String? referenciaPartida;
  final int? materiaPrimaLoteId;
  final int? inventarioPresentacionLoteId;
  final String? cantidadConsumida;
  final String? cantidadUnidadesConsumidas;
  final String? presentacion;
  final String? unidadPresentacion;
  final String? unidadRegistrada;
  final String? unidadCatalogoActual;
  final int? movimientoConsumoId;
  final String? cantidadRecibida;
  final String? unidadRecepcion;
  final int? recepcionPedidoId;
  final String? recepcionFecha;
  final int? origenAgricolaLoteId;
  final int? origenAgricolaProduccionId;
  final int? origenIndustrialId;
  final bool antecedenteRestringido;

  String get loteOrigenLabel {
    if (origenAgricolaLoteId != null) {
      if (origenAgricolaProduccionId != null) {
        return 'Lote agrícola #$origenAgricolaLoteId · Cosecha #$origenAgricolaProduccionId';
      }
      return 'Lote agrícola #$origenAgricolaLoteId';
    }
    if (origenIndustrialId != null) {
      return 'Lote de producción #$origenIndustrialId';
    }
    if (antecedenteRestringido) {
      return 'Antecedente restringido por permisos';
    }
    if (referenciaPartida != null) {
      return 'Partida $referenciaPartida';
    }
    if (materiaPrimaLoteId != null) {
      return 'Partida de materia prima #$materiaPrimaLoteId';
    }
    if (inventarioPresentacionLoteId != null) {
      return 'Partida de presentación #$inventarioPresentacionLoteId';
    }
    return 'Sin lote de origen vinculado';
  }

  String get formattedConsumida {
    if (cantidadConsumida == null) return 'Cantidad no registrada';
    final amount = _formatDecimalText(cantidadConsumida!);
    if (unidadRegistrada != null) {
      return '$amount $unidadRegistrada';
    }
    if (unidadCatalogoActual != null) {
      return '$amount (unidad histórica desconocida; catálogo actual: $unidadCatalogoActual)';
    }
    return '$amount (unidad histórica desconocida)';
  }

  String? get formattedUnidadesConsumidas {
    if (cantidadUnidadesConsumidas == null) return null;
    final amount = _formatDecimalText(cantidadUnidadesConsumidas!);
    final unit = unidadPresentacion;
    return unit != null ? '$amount $unit' : amount;
  }

  String? get formattedRecibida {
    if (cantidadRecibida == null) return null;
    final amount = _formatDecimalText(cantidadRecibida!);
    final unit = unidadRecepcion;
    return unit != null ? '$amount $unit' : amount;
  }
}

class ProductoObtenidoProcesamiento {
  const ProductoObtenidoProcesamiento({
    required this.partidaId,
    required this.insumoId,
    required this.producto,
    this.presentacionId,
    this.presentacion,
  });

  factory ProductoObtenidoProcesamiento.fromJson(Map<String, dynamic> row) =>
      ProductoObtenidoProcesamiento(
        partidaId: _asInt(row['partida_id']) ?? 0,
        insumoId: _asInt(row['insumo_id']) ?? 0,
        producto: _asText(row['producto']) ?? 'Producto sin nombre',
        presentacionId: _asInt(row['presentacion_id']),
        presentacion: _asText(row['presentacion']),
      );

  final int partidaId;
  final int insumoId;
  final String producto;
  final int? presentacionId;
  final String? presentacion;

  String get label =>
      presentacion != null ? '$producto · $presentacion' : producto;
}

class IngresoProduccionProcesamiento {
  const IngresoProduccionProcesamiento({
    required this.almacenajeId,
    required this.almacenId,
    this.insumoId,
    this.producto,
    this.presentacionId,
    this.presentacion,
    this.partidaId,
    this.cantidadIngresada,
    this.unidad,
    this.cantidadKg,
    this.almacen,
    this.fecha,
    this.estado,
  });

  factory IngresoProduccionProcesamiento.fromJson(Map<String, dynamic> row) =>
      IngresoProduccionProcesamiento(
        almacenajeId: _asInt(row['almacenaje_id']) ?? 0,
        almacenId: _asInt(row['almacen_id']) ?? 0,
        insumoId: _asInt(row['insumo_id']),
        producto: _asText(row['producto']),
        presentacionId: _asInt(row['presentacion_id']),
        presentacion: _asText(row['presentacion']),
        partidaId: _asInt(row['partida_id']),
        cantidadIngresada: _asText(row['cantidad_ingresada']),
        unidad: _asText(row['unidad']),
        cantidadKg: _asText(row['cantidad_kg']),
        almacen: _asText(row['almacen']),
        fecha: _asText(row['fecha']),
        estado: _asText(row['estado']),
      );

  final int almacenajeId;
  final int almacenId;
  final int? insumoId;
  final String? producto;
  final int? presentacionId;
  final String? presentacion;
  final int? partidaId;
  final String? cantidadIngresada;
  final String? unidad;
  final String? cantidadKg;
  final String? almacen;
  final String? fecha;
  final String? estado;

  String get almacenLabel => almacen ?? 'Almacén #$almacenId';

  String? get formattedCantidad {
    if (cantidadIngresada == null) return null;
    final amount = _formatDecimalText(cantidadIngresada!);
    return unidad != null ? '$amount $unidad' : amount;
  }

  String? get formattedKg =>
      cantidadKg == null ? null : '${_formatDecimalText(cantidadKg!)} kg';
}

class UbicacionActualProcesamiento {
  const UbicacionActualProcesamiento({
    required this.partidaId,
    required this.insumoId,
    required this.almacenId,
    this.producto,
    this.presentacionId,
    this.presentacion,
    this.unidad,
    this.cantidadActual,
    this.cantidadActualKg,
    this.almacen,
  });

  factory UbicacionActualProcesamiento.fromJson(Map<String, dynamic> row) =>
      UbicacionActualProcesamiento(
        partidaId: _asInt(row['partida_id']) ?? 0,
        insumoId: _asInt(row['insumo_id']) ?? 0,
        almacenId: _asInt(row['almacen_id']) ?? 0,
        producto: _asText(row['producto']),
        presentacionId: _asInt(row['presentacion_id']),
        presentacion: _asText(row['presentacion']),
        unidad: _asText(row['unidad']),
        cantidadActual: _asText(row['cantidad_actual']),
        cantidadActualKg: _asText(row['cantidad_actual_kg']),
        almacen: _asText(row['almacen']),
      );

  final int partidaId;
  final int insumoId;
  final int almacenId;
  final String? producto;
  final int? presentacionId;
  final String? presentacion;
  final String? unidad;
  final String? cantidadActual;
  final String? cantidadActualKg;
  final String? almacen;

  String get almacenLabel => almacen ?? 'Almacén #$almacenId';

  String? get formattedCantidadActual {
    if (cantidadActual == null) return null;
    final amount = _formatDecimalText(cantidadActual!);
    return unidad != null ? '$amount $unidad' : amount;
  }

  String? get formattedKgActual => cantidadActualKg == null
      ? null
      : '${_formatDecimalText(cantidadActualKg!)} kg';
}

class RestriccionesProcesamiento {
  const RestriccionesProcesamiento({
    this.origenes = false,
    this.destinos = false,
    this.ubicacionesActuales = false,
  });

  factory RestriccionesProcesamiento.fromJson(Object? json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    return RestriccionesProcesamiento(
      origenes: map['origenes'] == true,
      destinos: map['destinos'] == true,
      ubicacionesActuales: map['ubicaciones_actuales'] == true,
    );
  }

  final bool origenes;
  final bool destinos;
  final bool ubicacionesActuales;

  bool get hasAny => origenes || destinos || ubicacionesActuales;
}

class ProcesamientoRecorrido {
  const ProcesamientoRecorrido({
    required this.loteProduccionId,
    this.codigo,
    this.nombre,
    this.origenes = const [],
    this.productosObtenidos = const [],
    this.ingresosProduccion = const [],
    this.ubicacionesActuales = const [],
    this.restricciones = const RestriccionesProcesamiento(),
  });

  factory ProcesamientoRecorrido.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};
    final lote = root['lote_produccion'] is Map<String, dynamic>
        ? root['lote_produccion'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return ProcesamientoRecorrido(
      loteProduccionId: _asInt(lote['id']) ?? 0,
      codigo: _asText(lote['codigo']),
      nombre: _asText(lote['nombre']),
      origenes: _parseList(root['origenes'], OrigenProcesamiento.fromJson),
      productosObtenidos: _parseList(
        root['productos_obtenidos'],
        ProductoObtenidoProcesamiento.fromJson,
      ),
      ingresosProduccion: _parseList(
        root['ingresos_produccion'],
        IngresoProduccionProcesamiento.fromJson,
      ),
      ubicacionesActuales: _parseList(
        root['ubicaciones_actuales'],
        UbicacionActualProcesamiento.fromJson,
      ),
      restricciones: RestriccionesProcesamiento.fromJson(root['restricciones']),
    );
  }

  final int loteProduccionId;
  final String? codigo;
  final String? nombre;
  final List<OrigenProcesamiento> origenes;
  final List<ProductoObtenidoProcesamiento> productosObtenidos;
  final List<IngresoProduccionProcesamiento> ingresosProduccion;
  final List<UbicacionActualProcesamiento> ubicacionesActuales;
  final RestriccionesProcesamiento restricciones;

  String get title => nombre ?? codigo ?? 'Proceso #$loteProduccionId';

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
