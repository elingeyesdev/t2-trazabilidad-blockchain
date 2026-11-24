import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/certificacion_documento_models.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

class CertificacionDetailScreen extends StatefulWidget {
  const CertificacionDetailScreen({
    super.key,
    required this.certificacionId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final int certificacionId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<CertificacionDetailScreen> createState() =>
      _CertificacionDetailScreenState();
}

class _CertificacionDetailScreenState extends State<CertificacionDetailScreen> {
  CertificacionDetailRecord? _record;
  bool _loading = true;
  bool _downloading = false;
  String? _error;
  int? _errorStatus;
  String? _downloadError;
  Uint8List? _downloadedBytes;

  bool get _canView => widget.user.permissions.contains('certificaciones.view');

  @override
  void initState() {
    super.initState();
    if (_canView) {
      unawaited(_load());
    } else {
      _loading = false;
      _errorStatus = 403;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = null;
    });
    try {
      final result = await widget.service.loadCertificacionDetail(
        widget.user,
        widget.certificacionId,
      );
      if (!mounted) return;
      setState(() {
        _record = result;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
        _errorStatus = error.statusCode;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo consultar el detalle de la certificación.';
      });
    }
  }

  Future<void> _downloadPdf(CertificacionDetailRecord record) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadError = null;
    });
    try {
      final bytes = await widget.service.downloadCertificacionArchivo(
        widget.user,
        record.id,
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadedBytes = bytes;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError =
            'No se pudo descargar el archivo PDF de la certificación.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView || (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Detalle de certificación',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de certificación'),
        actions: [
          IconButton(
            key: const ValueKey('certificacion.actualizar'),
            tooltip: 'Actualizar certificación',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando certificación...')
            : _errorStatus == 404
            ? const AppEmptyState(
                icon: Icons.verified_outlined,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Certificación no encontrada',
                message:
                    'No encontramos esta certificación o no corresponde a tu ámbito.',
              )
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _buildContent(context, _record!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a certificaciones'),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, CertificacionDetailRecord record) {
    final theme = Theme.of(context);
    final look = AppModule.certificaciones.look;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: look.tone,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.workspace_premium_outlined,
                              color: look.ink,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.codigoCertificado,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Certificación #${record.id}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      RecordStatusBadge(status: record.resultado),
                      const Divider(height: 24),
                      if (record.loteNombre != null)
                        _metaRow(
                          context,
                          'Lote certificado',
                          record.loteNombre!,
                        ),
                      if (record.inspectorNombre != null)
                        _metaRow(context, 'Inspector', record.inspectorNombre!),
                      if (record.fechaCertificacion != null)
                        _metaRow(
                          context,
                          'Fecha de emisión',
                          record.fechaCertificacion!,
                        ),
                      if (record.observaciones != null)
                        _metaRow(
                          context,
                          'Observaciones',
                          record.observaciones!,
                        ),
                      if (record.recomendaciones != null)
                        _metaRow(
                          context,
                          'Recomendaciones',
                          record.recomendaciones!,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  key: const ValueKey('certificacion.blockchain_card'),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: record.tieneHashBlockchain
                        ? AppTheme.sprout
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: record.tieneHashBlockchain
                          ? AppTheme.sproutBorder
                          : AppTheme.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            record.tieneHashBlockchain
                                ? Icons.verified_user_rounded
                                : Icons.link_outlined,
                            color: AppTheme.fieldDeep,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Respaldo blockchain',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: AppTheme.fieldDeep,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        record.estadoBlockchainLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (record.blockchainRed != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Red: ${record.blockchainRed}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (record.blockchainTxHash != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          record.blockchainTxHash!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: AppTheme.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_downloadError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.claySoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.clay),
                    ),
                    child: Text(
                      _downloadError!,
                      style: const TextStyle(
                        color: AppTheme.clay,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_downloadedBytes != null) ...[
                  Container(
                    key: const ValueKey('certificacion.descarga_confirmada'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.sprout,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.sproutBorder),
                    ),
                    child: Text(
                      'PDF verificado y descargado (${(_downloadedBytes!.length / 1024).toStringAsFixed(1)} KB): ${record.codigoCertificado}.pdf',
                      style: const TextStyle(
                        color: AppTheme.fieldDeep,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (record.archivoDisponible)
                  FilledButton.icon(
                    key: const ValueKey('certificacion.abrir_archivo'),
                    onPressed: _downloading ? null : () => _downloadPdf(record),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      _downloading
                          ? 'Descargando certificado...'
                          : 'Descargar certificado PDF',
                    ),
                  )
                else
                  Text(
                    'Esta certificación no tiene un archivo PDF adjunto disponible.',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.inkSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
