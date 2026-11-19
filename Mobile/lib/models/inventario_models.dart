import 'api_exception.dart';
import 'auth_user.dart';

abstract final class InventarioPermissions {
  static bool canViewExistencias(AuthUser user) =>
      user.permissions.contains('inventario.view');

  static bool canViewMovimientos(AuthUser user) =>
      user.permissions.contains('almacen.movimientos.view');

  static bool canRegisterIngreso(AuthUser user) =>
      !user.roles.contains('admin') &&
      (user.permissions.contains('almacen.ingresos.create') ||
          user.permissions.contains('punto_venta.ajuste_stock'));

  static bool canRegisterSalida(AuthUser user) =>
      !user.roles.contains('admin') &&
      (user.permissions.contains('almacen.salidas.create') ||
          user.permissions.contains('punto_venta.ajuste_stock'));

  static bool canRegisterAjuste(AuthUser user) =>
      canRegisterIngreso(user) || canRegisterSalida(user);
}

enum MovimientoFormMode { ingreso, salida, ajuste }

class MovimientoTipoOption {
  const MovimientoTipoOption({
    required this.id,
    required this.name,
    required this.naturaleza,
  });

  final int id;
  final String name;
  final String naturaleza;

  bool get isAjuste => name.toLowerCase().contains('ajuste');
  bool get isSalida => naturaleza == 'salida';

  static const List<MovimientoTipoOption> defaults = [
    MovimientoTipoOption(id: 1, name: 'Compra', naturaleza: 'ingreso'),
    MovimientoTipoOption(
      id: 2,
      name: 'Producción recibida',
      naturaleza: 'ingreso',
    ),
    MovimientoTipoOption(id: 3, name: 'Devolución', naturaleza: 'ingreso'),
    MovimientoTipoOption(id: 4, name: 'Ajuste positivo', naturaleza: 'ingreso'),
    MovimientoTipoOption(id: 5, name: 'Envío', naturaleza: 'salida'),
    MovimientoTipoOption(id: 6, name: 'Consumo interno', naturaleza: 'salida'),
    MovimientoTipoOption(id: 7, name: 'Merma', naturaleza: 'salida'),
    MovimientoTipoOption(id: 8, name: 'Ajuste negativo', naturaleza: 'salida'),
  ];

  static List<MovimientoTipoOption> forMode(
    MovimientoFormMode mode, {
    bool allowIngreso = true,
    bool allowSalida = true,
  }) {
    return switch (mode) {
      MovimientoFormMode.ingreso =>
        defaults
            .where((t) => t.naturaleza == 'ingreso' && !t.isAjuste)
            .toList(),
      MovimientoFormMode.salida =>
        defaults.where((t) => t.naturaleza == 'salida' && !t.isAjuste).toList(),
      MovimientoFormMode.ajuste =>
        defaults
            .where(
              (t) =>
                  t.isAjuste &&
                  ((t.naturaleza == 'ingreso' && allowIngreso) ||
                      (t.naturaleza == 'salida' && allowSalida)),
            )
            .toList(),
    };
  }
}

class ExistenciaPartida {
  const ExistenciaPartida({
    this.materiaPrimaLoteId,
    this.presentacionLoteId,
    required this.referencia,
    required this.cantidadFisica,
    this.fechaRecepcion,
    this.fechaVencimiento,
    this.vencimientoEstado,
    this.utilizable = true,
  });

  factory ExistenciaPartida.fromJson(Map<String, dynamic> row) {
    final mpId = _asInt(row['materiaprimaloteid']);
    final presId = _asInt(row['inventario_presentacion_loteid']);
    return ExistenciaPartida(
      materiaPrimaLoteId: mpId,
      presentacionLoteId: presId,
      referencia:
          _asText(row['referencia']) ??
          (mpId != null
              ? 'Partida #$mpId'
              : (presId != null ? 'Presentación #$presId' : 'Partida')),
      cantidadFisica: _asText(row['cantidad_fisica']) ?? '0',
      fechaRecepcion: _asText(row['fecha_recepcion']),
      fechaVencimiento: _asText(row['fecha_vencimiento']),
      vencimientoEstado: _asText(row['vencimiento_estado']),
      utilizable: row['utilizable'] != false,
    );
  }

  final int? materiaPrimaLoteId;
  final int? presentacionLoteId;
  final String referencia;
  final String cantidadFisica;
  final String? fechaRecepcion;
  final String? fechaVencimiento;
  final String? vencimientoEstado;
  final bool utilizable;

  String? get partidaKey {
    if (materiaPrimaLoteId != null && materiaPrimaLoteId! > 0) {
      return 'm:$materiaPrimaLoteId';
    }
    if (presentacionLoteId != null && presentacionLoteId! > 0) {
      return 'p:$presentacionLoteId';
    }
    return null;
  }

  String displayLabel(String unitLabel) {
    final qty = '${formatInventarioDecimal(cantidadFisica)} $unitLabel';
    final date = fechaVencimiento != null
        ? ' · Vence $fechaVencimiento'
        : ' · Sin fecha registrada';
    return '$referencia ($qty$date)';
  }
}

class AlmacenExistencia {
  const AlmacenExistencia({
    required this.insumoId,
    required this.nombre,
    required this.unidad,
    required this.cantidadFisica,
    required this.cantidadDisponible,
    this.unidadMedidaId,
    this.cantidadVencida = '0',
    this.cantidadBloqueada = '0',
    this.cantidadReservada = '0',
    this.cantidadSinPartida = '0',
    this.minimo,
    this.existenciasBajas = false,
    this.partidas = const [],
  });

  factory AlmacenExistencia.fromJson(Map<String, dynamic> row) {
    final id = _asInt(row['insumoid']) ?? 0;
    final rawPartidas = row['partidas'];
    final partidas = <ExistenciaPartida>[];
    if (rawPartidas is List) {
      for (final item in rawPartidas) {
        if (item is Map<String, dynamic>) {
          partidas.add(ExistenciaPartida.fromJson(item));
        }
      }
    }
    return AlmacenExistencia(
      insumoId: id,
      nombre: _asText(row['nombre']) ?? 'Producto #$id',
      unidadMedidaId: _asInt(row['unidadmedidaid']),
      unidad: _asText(row['unidad']) ?? 'u',
      cantidadFisica: _asText(row['cantidad_fisica']) ?? '0',
      cantidadDisponible: _asText(row['cantidad_disponible']) ?? '0',
      cantidadVencida: _asText(row['cantidad_vencida']) ?? '0',
      cantidadBloqueada: _asText(row['cantidad_bloqueada']) ?? '0',
      cantidadReservada: _asText(row['cantidad_reservada']) ?? '0',
      cantidadSinPartida: _asText(row['cantidad_sin_partida']) ?? '0',
      minimo: _asText(row['minimo']),
      existenciasBajas: row['existencias_bajas'] == true,
      partidas: partidas,
    );
  }

  final int insumoId;
  final String nombre;
  final int? unidadMedidaId;
  final String unidad;
  final String cantidadFisica;
  final String cantidadDisponible;
  final String cantidadVencida;
  final String cantidadBloqueada;
  final String cantidadReservada;
  final String cantidadSinPartida;
  final String? minimo;
  final bool existenciasBajas;
  final List<ExistenciaPartida> partidas;

  double get disponibleValue =>
      double.tryParse(cantidadDisponible.replaceAll(',', '.')) ?? 0;

  double get sinPartidaValue =>
      double.tryParse(cantidadSinPartida.replaceAll(',', '.')) ?? 0;

  String get formattedDisponible =>
      '${formatInventarioDecimal(cantidadDisponible)} $unidad';

  String get formattedFisica =>
      '${formatInventarioDecimal(cantidadFisica)} $unidad';

  String get dropdownLabel => '$nombre ($formattedDisponible disp.)';
}

class AlmacenExistenciasPage {
  const AlmacenExistenciasPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  factory AlmacenExistenciasPage.fromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException(
        'No pudimos interpretar las existencias del almacén.',
      );
    }
    final items = <AlmacenExistencia>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final item = AlmacenExistencia.fromJson(row);
      if (item.insumoId > 0) items.add(item);
    }
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final meta = map['meta'] is Map<String, dynamic>
        ? map['meta'] as Map<String, dynamic>
        : map;
    return AlmacenExistenciasPage(
      items: items,
      currentPage: _asInt(meta['current_page']) ?? 1,
      lastPage: _asInt(meta['last_page']) ?? 1,
    );
  }

  final List<AlmacenExistencia> items;
  final int currentPage;
  final int lastPage;
}

class InventarioMovimientoRecord {
  const InventarioMovimientoRecord({
    required this.id,
    required this.almacenId,
    required this.insumoId,
    required this.insumoNombre,
    required this.tipoNombre,
    required this.naturaleza,
    required this.fecha,
    required this.cantidad,
    this.unidad,
    this.saldoAnterior,
    this.saldoPosterior,
    this.destinoMotivo,
    this.referencia,
    this.observaciones,
    this.usuarioNombre,
    this.partida,
  });

  factory InventarioMovimientoRecord.fromJson(Object? json) {
    final row =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    if (row is! Map<String, dynamic>) {
      throw const ApiException('No pudimos interpretar el movimiento.');
    }
    final id = _asInt(row['almacen_movimientoid']) ?? 0;
    final insumoMap = row['insumo'] is Map<String, dynamic>
        ? row['insumo'] as Map<String, dynamic>
        : null;
    final tipoMap = row['tipo'] is Map<String, dynamic>
        ? row['tipo'] as Map<String, dynamic>
        : null;
    final userMap = row['usuario'] is Map<String, dynamic>
        ? row['usuario'] as Map<String, dynamic>
        : null;
    final firstName = _asText(userMap?['nombre']);
    final lastName = _asText(userMap?['apellido']);
    final userParts = [?firstName, ?lastName];
    return InventarioMovimientoRecord(
      id: id,
      almacenId: _asInt(row['almacenid']) ?? 0,
      insumoId: _asInt(row['insumoid']) ?? _asInt(insumoMap?['insumoid']) ?? 0,
      insumoNombre:
          _asText(insumoMap?['nombre']) ??
          'Producto #${_asInt(row['insumoid']) ?? 0}',
      tipoNombre: _asText(tipoMap?['nombre']) ?? 'Movimiento',
      naturaleza: (_asText(tipoMap?['naturaleza']) ?? '').toLowerCase(),
      fecha: _asText(row['fecha']) ?? 'Sin fecha',
      cantidad:
          _asText(row['cantidad_decimal']) ?? _asText(row['cantidad']) ?? '0',
      unidad: _asText(row['unidad']),
      saldoAnterior: _asText(row['saldo_anterior']),
      saldoPosterior: _asText(row['saldo_posterior']),
      destinoMotivo: _asText(row['destino_motivo']),
      referencia: _asText(row['referencia']),
      observaciones: _asText(row['observaciones']),
      usuarioNombre: userParts.isEmpty ? null : userParts.join(' '),
      partida: _asText(row['partida']),
    );
  }

  final int id;
  final int almacenId;
  final int insumoId;
  final String insumoNombre;
  final String tipoNombre;
  final String naturaleza;
  final String fecha;
  final String cantidad;
  final String? unidad;
  final String? saldoAnterior;
  final String? saldoPosterior;
  final String? destinoMotivo;
  final String? referencia;
  final String? observaciones;
  final String? usuarioNombre;
  final String? partida;

  bool get isIngreso => naturaleza == 'ingreso';
  bool get isSalida => naturaleza == 'salida';

  String get formattedQuantity {
    final qty = formatInventarioDecimal(cantidad);
    final sign = isSalida ? '-' : (isIngreso ? '+' : '');
    return unidad == null || unidad!.isEmpty
        ? '$sign$qty'
        : '$sign$qty $unidad';
  }

  String? get formattedSaldoPosterior {
    if (saldoPosterior == null) return null;
    final value = formatInventarioDecimal(saldoPosterior!);
    return unidad == null || unidad!.isEmpty ? value : '$value $unidad';
  }
}

class InventarioMovimientosPage {
  const InventarioMovimientosPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  factory InventarioMovimientosPage.fromJson(Object? json) {
    final rows = json is Map<String, dynamic> ? json['data'] : json;
    if (rows is! List) {
      throw const ApiException(
        'No pudimos interpretar los movimientos del almacén.',
      );
    }
    final items = <InventarioMovimientoRecord>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final item = InventarioMovimientoRecord.fromJson(row);
      if (item.id > 0) items.add(item);
    }
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final meta = map['meta'] is Map<String, dynamic>
        ? map['meta'] as Map<String, dynamic>
        : map;
    return InventarioMovimientosPage(
      items: items,
      currentPage: _asInt(meta['current_page']) ?? 1,
      lastPage: _asInt(meta['last_page']) ?? 1,
    );
  }

  final List<InventarioMovimientoRecord> items;
  final int currentPage;
  final int lastPage;
}

String formatInventarioDecimal(String raw) {
  final trimmed = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$').hasMatch(trimmed)) {
    return trimmed;
  }
  if (!trimmed.contains('.')) return trimmed;
  return trimmed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String? validateInventarioQuantity(
  String? raw, {
  double? maxDisponible,
  String? unitLabel,
  bool checkStock = false,
}) {
  final normalized = (raw ?? '').trim().replaceAll(',', '.');
  if (normalized.isEmpty) {
    return 'Indica la cantidad del movimiento.';
  }
  if (!RegExp(
    r'^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$',
  ).hasMatch(normalized)) {
    return 'Indica una cantidad positiva con hasta seis decimales.';
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) {
    return 'La cantidad debe ser mayor que cero.';
  }
  if (checkStock && maxDisponible != null && parsed > maxDisponible + 1e-9) {
    final disp = formatInventarioDecimal(maxDisponible.toStringAsFixed(6));
    final unit = unitLabel == null || unitLabel.isEmpty ? '' : ' $unitLabel';
    return 'No hay cantidad suficiente: disponible $disp$unit.';
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
