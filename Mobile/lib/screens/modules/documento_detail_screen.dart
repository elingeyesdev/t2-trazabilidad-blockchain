import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
import 'module_access_denied.dart';

class DocumentoDetailScreen extends StatefulWidget {
  const DocumentoDetailScreen({
    super.key,
    required this.documentoId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.externalLauncher,
  });

  final int documentoId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final Future<bool> Function(Uri uri)? externalLauncher;

  @override
  State<DocumentoDetailScreen> createState() => _DocumentoDetailScreenState();
}

class _DocumentoDetailScreenState extends State<DocumentoDetailScreen> {
  DocumentoEntregaDetailRecord? _record;
  bool _loading = true;
  bool _downloading = false;
  String? _error;
  int? _errorStatus;
  String? _downloadError;
  Uint8List? _downloadedBytes;

  bool get _canView => widget.user.permissions.contains('documentos.view');

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
      final result = await widget.service.loadDocumentoEntregaDetail(
        widget.user,
        widget.documentoId,
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
        _error = 'No se pudo consultar el detalle del documento.';
      });
    }
  }

  Future<void> _downloadFile(DocumentoEntregaDetailRecord record) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadError = null;
    });
    try {
      final bytes = await widget.service.downloadDocumentoEntregaArchivo(
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
        _downloadError = 'No se pudo descargar el documento de entrega.';
      });
    }
  }

  Future<void> _openInBrowser(DocumentoEntregaDetailRecord record) async {
    final uri = widget.service.resolvePublicStorageUri(record.archivoPath);
    if (uri == null) return;
    try {
      final ok = widget.externalLauncher != null
          ? await widget.externalLauncher!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el documento en el navegador.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el documento en el navegador.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView || (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Detalle de documento',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de documento'),
        actions: [
          IconButton(
            key: const ValueKey('documento.actualizar'),
            tooltip: 'Actualizar documento',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando documento...')
            : _errorStatus == 404
            ? const AppEmptyState(
                icon: Icons.description_outlined,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Documento no encontrado',
                message:
                    'No encontramos el documento solicitado o no tienes acceso a este registro.',
              )
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _buildContent(context, _record!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a documentos'),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    DocumentoEntregaDetailRecord record,
  ) {
    final theme = Theme.of(context);
    final look = AppModule.documentos.look;
    final storageUri = widget.service.resolvePublicStorageUri(
      record.archivoPath,
    );

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
                              Icons.description_outlined,
                              color: look.ink,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.titulo,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  record.tipoDocumento,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      if (record.originalName != null)
                        _metaRow(context, 'Archivo', record.originalName!),
                      if (record.sizeLabel != null)
                        _metaRow(context, 'Tamaño', record.sizeLabel!),
                      if (record.pedidoId != null)
                        _metaRow(context, 'Pedido', '#${record.pedidoId}'),
                      if (record.externoEnvioId != null)
                        _metaRow(
                          context,
                          'Envío vinculado',
                          record.externoEnvioId!,
                        ),
                      if (record.subidoPorNombre != null)
                        _metaRow(
                          context,
                          'Subido por',
                          record.subidoPorNombre!,
                        ),
                      if (record.createdAt != null)
                        _metaRow(context, 'Fecha', record.createdAt!),
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
                  if (record.isImage)
                    ClipRRect(
                      key: const ValueKey('documento.imagen_preview'),
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _downloadedBytes!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Container(
                          padding: const EdgeInsets.all(16),
                          color: AppTheme.sprout,
                          child: Text(
                            'Imagen descargada (${(_downloadedBytes!.length / 1024).toStringAsFixed(1)} KB).',
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      key: const ValueKey('documento.descarga_confirmada'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.sprout,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.sproutBorder),
                      ),
                      child: Text(
                        'Documento verificado y descargado (${(_downloadedBytes!.length / 1024).toStringAsFixed(1)} KB): ${record.originalName ?? record.titulo}',
                        style: const TextStyle(
                          color: AppTheme.fieldDeep,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  key: const ValueKey('documento.abrir_archivo'),
                  onPressed: _downloading ? null : () => _downloadFile(record),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    _downloading
                        ? 'Descargando documento...'
                        : 'Descargar respaldo',
                  ),
                ),
                if (storageUri != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('documento.abrir_navegador'),
                    onPressed: () => unawaited(_openInBrowser(record)),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Abrir en navegador'),
                  ),
                ],
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
