abstract final class TrazabilidadCodigoParser {
  static final RegExp _validCodePattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]{2,63}$',
  );

  /// Extrae y normaliza un código de trazabilidad desde un código directo
  /// (`TRZ-PDV-...`, `TRZ-...`) o desde una URL pública
  /// (`https://.../trazabilidad/TRZ-PDV-...`).
  static String? extract(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final candidate = _extractRawCandidate(trimmed);
    if (candidate == null) return null;

    final normalized = candidate.trim().toUpperCase();
    if (!_validCodePattern.hasMatch(normalized)) return null;
    return normalized;
  }

  static String? _extractRawCandidate(String input) {
    final looksLikeUrlOrPath =
        input.contains('://') || input.contains('/') || input.contains('?');
    if (!looksLikeUrlOrPath) {
      return input;
    }

    final uri = Uri.tryParse(input);
    if (uri == null) return null;

    final fromQuery =
        uri.queryParameters['codigo'] ?? uri.queryParameters['code'];
    if (fromQuery != null && fromQuery.trim().isNotEmpty) {
      return fromQuery.trim();
    }

    final segments = uri.pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();

    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].toLowerCase() == 'trazabilidad') {
        try {
          return Uri.decodeComponent(segments[i + 1]);
        } catch (_) {
          return segments[i + 1];
        }
      }
    }

    return null;
  }
}

class TrazabilidadMapaPunto {
  const TrazabilidadMapaPunto({
    required this.lat,
    required this.lng,
    required this.orden,
    required this.label,
  });

  factory TrazabilidadMapaPunto.fromJson(
    Map<String, dynamic> json, {
    int fallbackOrden = 1,
  }) {
    return TrazabilidadMapaPunto(
      lat: _asDouble(json['lat'] ?? json['latitud']) ?? 0,
      lng: _asDouble(json['lng'] ?? json['longitud']) ?? 0,
      orden: _asInt(json['orden']) ?? fallbackOrden,
      label:
          _asText(json['label'] ?? json['nombre']) ?? 'Parada $fallbackOrden',
    );
  }

  final double lat;
  final double lng;
  final int orden;
  final String label;

  bool get isValid => lat != 0 || lng != 0;
}

class TrazabilidadCertificacion {
  const TrazabilidadCertificacion({
    required this.nombre,
    this.entidad,
    this.codigo,
    this.estado,
    this.fecha,
    this.blockchainEstado,
    this.txHash,
    this.red,
    this.archivoUrl,
  });

  factory TrazabilidadCertificacion.fromJson(Map<String, dynamic> json) {
    final blockchain = json['blockchain'] is Map<String, dynamic>
        ? json['blockchain'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return TrazabilidadCertificacion(
      nombre:
          _asText(json['nombre'] ?? json['tipo'] ?? json['titulo']) ??
          'Certificación',
      entidad: _asText(json['entidad'] ?? json['emisor'] ?? json['organismo']),
      codigo: _asText(json['codigo'] ?? json['numero']),
      estado: _asText(json['estado']),
      fecha: _asText(
        json['fecha_fmt'] ?? json['fecha_emision'] ?? json['fecha'],
      ),
      blockchainEstado: _asText(
        json['blockchain_status'] ??
            json['estado_blockchain'] ??
            blockchain['estado'] ??
            blockchain['status'],
      ),
      txHash: _asText(
        json['tx_hash'] ??
            json['blockchain_tx_hash'] ??
            json['hash'] ??
            blockchain['tx_hash'] ??
            blockchain['hash'],
      ),
      red: _asText(
        json['blockchain_network'] ??
            json['red'] ??
            blockchain['red'] ??
            blockchain['network'],
      ),
      archivoUrl: _asText(json['archivo_url'] ?? json['url']),
    );
  }

  final String nombre;
  final String? entidad;
  final String? codigo;
  final String? estado;
  final String? fecha;
  final String? blockchainEstado;
  final String? txHash;
  final String? red;
  final String? archivoUrl;

  bool get tieneHashBlockchain => txHash != null && txHash!.isNotEmpty;

  bool get blockchainConfirmado {
    final status = (blockchainEstado ?? '').toLowerCase();
    if (status.contains('confirm') ||
        status.contains('verific') ||
        status.contains('registr') ||
        status.contains('ok')) {
      return true;
    }
    return tieneHashBlockchain;
  }
}

class TrazabilidadEvento {
  const TrazabilidadEvento({
    required this.paso,
    required this.etapa,
    required this.etapaLabel,
    required this.titulo,
    this.fechaFmt,
    this.descripcion,
    this.descripcionLineas = const [],
    this.ubicacion,
    this.referencia,
    this.evidenciaUrl,
    this.evidenciaTipo,
    this.evidenciaFotoUrl,
    this.mapaRuta = const [],
  });

  factory TrazabilidadEvento.fromJson(
    Map<String, dynamic> json, {
    int fallbackPaso = 1,
    String? fallbackEtapa,
    String? fallbackEtapaLabel,
  }) {
    final etapa = (_asText(json['etapa']) ?? fallbackEtapa ?? 'agricola')
        .toLowerCase();
    final etapaLabel =
        _asText(json['etapa_label']) ??
        fallbackEtapaLabel ??
        _stageLabelFor(etapa);

    final rawLineas = json['descripcion_lineas'];
    final lineas = <String>[];
    if (rawLineas is List) {
      for (final item in rawLineas) {
        final text = _asText(item);
        if (text != null) lineas.add(text);
      }
    }
    final descripcion = _asText(json['descripcion']);
    if (lineas.isEmpty && descripcion != null) {
      for (final line in descripcion.split('\n')) {
        final clean = line.trim();
        if (clean.isNotEmpty) lineas.add(clean);
      }
    }

    final mapaPuntos = <TrazabilidadMapaPunto>[];
    final rawMapa = json['mapa_ruta'];
    if (rawMapa is List) {
      for (var i = 0; i < rawMapa.length; i++) {
        final item = rawMapa[i];
        if (item is Map<String, dynamic>) {
          final point = TrazabilidadMapaPunto.fromJson(
            item,
            fallbackOrden: i + 1,
          );
          if (point.isValid) mapaPuntos.add(point);
        }
      }
    }

    return TrazabilidadEvento(
      paso: _asInt(json['paso']) ?? fallbackPaso,
      etapa: etapa,
      etapaLabel: etapaLabel,
      titulo: _asText(json['titulo']) ?? 'Evento',
      fechaFmt: _asText(json['fecha_fmt'] ?? json['fecha']),
      descripcion: descripcion,
      descripcionLineas: List.unmodifiable(lineas),
      ubicacion: _asText(json['ubicacion']),
      referencia: _asText(json['referencia']),
      evidenciaUrl: _asText(json['evidencia_url']),
      evidenciaTipo: _asText(json['evidencia_tipo']),
      evidenciaFotoUrl: _asText(json['evidencia_foto_url']),
      mapaRuta: List.unmodifiable(mapaPuntos),
    );
  }

  final int paso;
  final String etapa;
  final String etapaLabel;
  final String titulo;
  final String? fechaFmt;
  final String? descripcion;
  final List<String> descripcionLineas;
  final String? ubicacion;
  final String? referencia;
  final String? evidenciaUrl;
  final String? evidenciaTipo;
  final String? evidenciaFotoUrl;
  final List<TrazabilidadMapaPunto> mapaRuta;

  String? get primaryPhotoUrl {
    if (evidenciaFotoUrl != null) return evidenciaFotoUrl;
    if (evidenciaUrl != null && _looksLikeImage(evidenciaUrl!, evidenciaTipo)) {
      return evidenciaUrl;
    }
    return null;
  }

  bool get hasRouteMap => mapaRuta.isNotEmpty;

  bool matchesQuery(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      titulo,
      etapaLabel,
      ubicacion ?? '',
      referencia ?? '',
      fechaFmt ?? '',
      descripcion ?? '',
      ...descripcionLineas,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}

class TrazabilidadEtapaGrupo {
  const TrazabilidadEtapaGrupo({
    required this.key,
    required this.label,
    required this.eventos,
  });

  final String key;
  final String label;
  final List<TrazabilidadEvento> eventos;

  int get total => eventos.length;
}

class TrazabilidadPublicaReporte {
  const TrazabilidadPublicaReporte({
    required this.codigo,
    required this.producto,
    this.stockActual,
    this.unidad,
    this.puntoVenta,
    this.minorista,
    this.loteAgricola,
    this.loteCodigo,
    this.pedido,
    this.urlPublica,
    this.totalEventos = 0,
    this.progreso = 0,
    this.certificaciones = const [],
    this.blockchainVerificado = false,
    this.blockchainEstado,
    this.blockchainHash,
    this.blockchainRed,
    this.etapas = const [],
    this.eventos = const [],
    this.rawData = const <String, dynamic>{},
  });

  factory TrazabilidadPublicaReporte.fromJson(
    Object? json, {
    required String fallbackCode,
  }) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};

    final etapas = <TrazabilidadEtapaGrupo>[];
    final flatEvents = <TrazabilidadEvento>[];

    final rawAgrupados = root['eventos_agrupados'];
    if (rawAgrupados is List && rawAgrupados.isNotEmpty) {
      var stepCounter = 1;
      for (final group in rawAgrupados) {
        if (group is! Map<String, dynamic>) continue;
        final key = (_asText(group['key']) ?? 'agricola').toLowerCase();
        final label = _asText(group['label']) ?? _stageLabelFor(key);
        final rawItems = group['eventos'];
        final items = <TrazabilidadEvento>[];
        if (rawItems is List) {
          for (final item in rawItems) {
            if (item is Map<String, dynamic>) {
              final event = TrazabilidadEvento.fromJson(
                item,
                fallbackPaso: stepCounter++,
                fallbackEtapa: key,
                fallbackEtapaLabel: label,
              );
              items.add(event);
              flatEvents.add(event);
            }
          }
        }
        if (items.isNotEmpty) {
          etapas.add(
            TrazabilidadEtapaGrupo(
              key: key,
              label: label,
              eventos: List.unmodifiable(items),
            ),
          );
        }
      }
    }

    if (flatEvents.isEmpty && root['eventos'] is List) {
      final rawEvents = root['eventos'] as List;
      for (var i = 0; i < rawEvents.length; i++) {
        final item = rawEvents[i];
        if (item is Map<String, dynamic>) {
          flatEvents.add(
            TrazabilidadEvento.fromJson(item, fallbackPaso: i + 1),
          );
        }
      }
      const order = ['agricola', 'planta', 'mayorista', 'distribucion', 'pdv'];
      final byKey = <String, List<TrazabilidadEvento>>{};
      for (final event in flatEvents) {
        byKey.putIfAbsent(event.etapa, () => <TrazabilidadEvento>[]).add(event);
      }
      for (final key in order) {
        final list = byKey.remove(key);
        if (list != null && list.isNotEmpty) {
          etapas.add(
            TrazabilidadEtapaGrupo(
              key: key,
              label: _stageLabelFor(key),
              eventos: List.unmodifiable(list),
            ),
          );
        }
      }
      for (final entry in byKey.entries) {
        etapas.add(
          TrazabilidadEtapaGrupo(
            key: entry.key,
            label: entry.value.first.etapaLabel,
            eventos: List.unmodifiable(entry.value),
          ),
        );
      }
    }

    final certificaciones = <TrazabilidadCertificacion>[];
    final rawCerts = root['certificaciones'];
    if (rawCerts is List) {
      for (final item in rawCerts) {
        if (item is Map<String, dynamic>) {
          certificaciones.add(TrazabilidadCertificacion.fromJson(item));
        }
      }
    }

    final blockchainMap = root['blockchain'] is Map<String, dynamic>
        ? root['blockchain'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final firstCertWithHash = certificaciones
        .where((c) => c.tieneHashBlockchain)
        .firstOrNull;
    final blockchainHash =
        _asText(
          blockchainMap['tx_hash'] ??
              blockchainMap['hash'] ??
              root['blockchain_tx_hash'],
        ) ??
        firstCertWithHash?.txHash;
    final blockchainEstado =
        _asText(
          blockchainMap['estado'] ??
              blockchainMap['status'] ??
              root['blockchain_status'],
        ) ??
        firstCertWithHash?.blockchainEstado;
    final blockchainRed =
        _asText(
          blockchainMap['red'] ??
              blockchainMap['network'] ??
              root['blockchain_network'],
        ) ??
        firstCertWithHash?.red;
    final blockchainVerificado =
        blockchainMap['verificado'] == true ||
        blockchainMap['verified'] == true ||
        (blockchainHash != null && blockchainHash.isNotEmpty) ||
        certificaciones.any((c) => c.blockchainConfirmado);

    final totalFromField = _asInt(root['total_eventos']);
    final totalEventos = totalFromField ?? flatEvents.length;

    return TrazabilidadPublicaReporte(
      codigo: _asText(root['codigo']) ?? fallbackCode,
      producto:
          _asText(root['producto']) ??
          _asText(root['lote_agricola']) ??
          'Producto trazado',
      stockActual: _asDouble(root['stock_actual']),
      unidad: _asText(root['unidad']),
      puntoVenta: _asText(root['punto_venta']),
      minorista: _asText(root['minorista']),
      loteAgricola: _asText(root['lote_agricola']),
      loteCodigo: _asText(root['lote_codigo']),
      pedido: _asText(root['pedido']),
      urlPublica: _asText(root['url_publica'] ?? root['trazabilidad_url']),
      totalEventos: totalEventos,
      progreso: _asInt(root['progreso']) ?? 0,
      certificaciones: List.unmodifiable(certificaciones),
      blockchainVerificado: blockchainVerificado,
      blockchainEstado: blockchainEstado,
      blockchainHash: blockchainHash,
      blockchainRed: blockchainRed,
      etapas: List.unmodifiable(etapas),
      eventos: List.unmodifiable(flatEvents),
      rawData: Map<String, dynamic>.unmodifiable(root),
    );
  }

  final String codigo;
  final String producto;
  final double? stockActual;
  final String? unidad;
  final String? puntoVenta;
  final String? minorista;
  final String? loteAgricola;
  final String? loteCodigo;
  final String? pedido;
  final String? urlPublica;
  final int totalEventos;
  final int progreso;
  final List<TrazabilidadCertificacion> certificaciones;
  final bool blockchainVerificado;
  final String? blockchainEstado;
  final String? blockchainHash;
  final String? blockchainRed;
  final List<TrazabilidadEtapaGrupo> etapas;
  final List<TrazabilidadEvento> eventos;
  final Map<String, dynamic> rawData;

  bool get tieneCertificaciones => certificaciones.isNotEmpty;

  String get estadoCertificacionLabel {
    if (blockchainVerificado) {
      return 'Verificado en blockchain';
    }
    if (tieneCertificaciones) {
      return 'Certificado registrado';
    }
    return 'Sin certificación blockchain registrada';
  }
}

typedef TrazabilidadPublicaResumen = TrazabilidadPublicaReporte;

String _stageLabelFor(String key) => switch (key.toLowerCase()) {
  'agricola' => 'Producción agrícola',
  'planta' => 'Planta procesadora',
  'mayorista' => 'Centro mayorista',
  'distribucion' => 'Distribución al PDV',
  'pdv' => 'Punto de venta',
  _ => 'Etapa del recorrido',
};

bool _looksLikeImage(String url, String? tipo) {
  final lowerTipo = (tipo ?? '').toLowerCase();
  if (lowerTipo.contains('imagen') ||
      lowerTipo.contains('foto') ||
      lowerTipo.startsWith('image/')) {
    return true;
  }
  final lowerUrl = url.toLowerCase();
  return lowerUrl.endsWith('.jpg') ||
      lowerUrl.endsWith('.jpeg') ||
      lowerUrl.endsWith('.png') ||
      lowerUrl.endsWith('.webp');
}

String? _asText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty || text == '—' ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
  return null;
}
