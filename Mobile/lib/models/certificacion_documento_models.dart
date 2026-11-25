class CertificacionDetailRecord {
  const CertificacionDetailRecord({
    required this.id,
    required this.codigoCertificado,
    required this.resultado,
    required this.archivoDisponible,
    this.loteId,
    this.loteNombre,
    this.emisionUuid,
    this.observaciones,
    this.recomendaciones,
    this.fechaCertificacion,
    this.inspectorNombre,
    this.blockchainEstado,
    this.blockchainTxHash,
    this.blockchainRed,
  });

  factory CertificacionDetailRecord.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};

    final lote = root['lote'] is Map<String, dynamic>
        ? root['lote'] as Map<String, dynamic>
        : null;
    final usuario = root['usuario'] is Map<String, dynamic>
        ? root['usuario'] as Map<String, dynamic>
        : null;
    final blockchain = root['blockchain'] is Map<String, dynamic>
        ? root['blockchain'] as Map<String, dynamic>
        : null;

    final inspectorParts = [
      _asText(usuario?['nombre']),
      _asText(usuario?['apellido']),
    ].whereType<String>().toList();

    return CertificacionDetailRecord(
      id: _asInt(root['certificacionid'] ?? root['id']) ?? 0,
      codigoCertificado:
          _asText(root['codigo_certificado']) ??
          'CERT-#${_asInt(root['certificacionid'] ?? root['id']) ?? 0}',
      resultado: _asText(root['resultado']) ?? 'Sin resultado',
      archivoDisponible: root['archivo_disponible'] == true,
      loteId: _asInt(root['loteid'] ?? lote?['loteid']),
      loteNombre: _asText(lote?['nombre']),
      emisionUuid: _asText(root['emision_uuid']),
      observaciones: _asText(root['observaciones']),
      recomendaciones: _asText(root['recomendaciones']),
      fechaCertificacion: _asText(
        root['fecha_certificacion'] ?? root['fecha_evaluacion'],
      ),
      inspectorNombre: inspectorParts.isEmpty ? null : inspectorParts.join(' '),
      blockchainEstado: _asText(
        root['blockchain_estado'] ??
            root['blockchain_status'] ??
            blockchain?['estado'] ??
            blockchain?['status'],
      ),
      blockchainTxHash: _asText(
        root['blockchain_tx_hash'] ??
            root['tx_hash'] ??
            root['hash_blockchain'] ??
            blockchain?['tx_hash'] ??
            blockchain?['hash'],
      ),
      blockchainRed: _asText(
        root['blockchain_network'] ??
            root['blockchain_red'] ??
            blockchain?['red'] ??
            blockchain?['network'],
      ),
    );
  }

  final int id;
  final String codigoCertificado;
  final String resultado;
  final bool archivoDisponible;
  final int? loteId;
  final String? loteNombre;
  final String? emisionUuid;
  final String? observaciones;
  final String? recomendaciones;
  final String? fechaCertificacion;
  final String? inspectorNombre;
  final String? blockchainEstado;
  final String? blockchainTxHash;
  final String? blockchainRed;

  bool get tieneHashBlockchain =>
      blockchainTxHash != null && blockchainTxHash!.isNotEmpty;

  String get estadoBlockchainLabel {
    final estado = (blockchainEstado ?? '').toLowerCase();
    if (estado.contains('confirm') ||
        estado.contains('verific') ||
        estado.contains('registr') ||
        tieneHashBlockchain) {
      return 'Confirmado en blockchain';
    }
    if (estado.contains('pendiente') || estado.contains('proces')) {
      return 'Registro en blockchain pendiente';
    }
    if (estado.contains('error') || estado.contains('fall')) {
      return 'Error al registrar en blockchain';
    }
    return blockchainEstado ?? 'Sin registro en blockchain';
  }
}

class DocumentoEntregaDetailRecord {
  const DocumentoEntregaDetailRecord({
    required this.id,
    required this.titulo,
    required this.tipoDocumento,
    this.externoEnvioId,
    this.pedidoId,
    this.almacenId,
    this.archivoPath,
    this.originalName,
    this.mime,
    this.sizeBytes,
    this.subidoPorNombre,
    this.createdAt,
  });

  factory DocumentoEntregaDetailRecord.fromJson(Object? json) {
    final root =
        json is Map<String, dynamic> && json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json is Map<String, dynamic>
        ? json
        : const <String, dynamic>{};

    final metadata = root['metadata'] is Map<String, dynamic>
        ? root['metadata'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final usuario = root['usuario'] is Map<String, dynamic>
        ? root['usuario'] as Map<String, dynamic>
        : null;
    final userParts = [
      _asText(usuario?['nombre']),
      _asText(usuario?['apellido']),
    ].whereType<String>().toList();

    return DocumentoEntregaDetailRecord(
      id: _asInt(root['documentoentregaid'] ?? root['id']) ?? 0,
      titulo:
          _asText(root['titulo']) ??
          'Documento #${_asInt(root['documentoentregaid'] ?? root['id']) ?? 0}',
      tipoDocumento: _asText(root['tipo_documento']) ?? 'Documento',
      externoEnvioId: _asText(root['externo_envio_id']),
      pedidoId: _asInt(root['pedidoid']),
      almacenId: _asInt(root['almacenid']),
      archivoPath: _asText(root['archivo_path']),
      originalName: _asText(metadata['original_name']),
      mime: _asText(metadata['mime']),
      sizeBytes: _asInt(metadata['size']),
      subidoPorNombre: userParts.isEmpty ? null : userParts.join(' '),
      createdAt: _asText(root['created_at']),
    );
  }

  final int id;
  final String titulo;
  final String tipoDocumento;
  final String? externoEnvioId;
  final int? pedidoId;
  final int? almacenId;
  final String? archivoPath;
  final String? originalName;
  final String? mime;
  final int? sizeBytes;
  final String? subidoPorNombre;
  final String? createdAt;

  bool get isImage {
    final lowerMime = (mime ?? '').toLowerCase();
    if (lowerMime.startsWith('image/')) return true;
    final lowerName = (originalName ?? archivoPath ?? '').toLowerCase();
    return lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.webp');
  }

  String? get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(2)} MB';
  }
}

String? _asText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
