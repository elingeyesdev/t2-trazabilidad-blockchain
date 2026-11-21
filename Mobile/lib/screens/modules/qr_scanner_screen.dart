import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/qr_envio_models.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/field_kit.dart';
import 'module_access_denied.dart';

enum QrCameraIssue { permissionDenied, unavailable }

typedef QrCameraBuilder =
    Widget Function(
      BuildContext context,
      ValueChanged<String> onCodeDetected,
      ValueChanged<QrCameraIssue> onCameraIssue,
    );

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({
    super.key,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.cameraBuilder,
  });

  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final QrCameraBuilder? cameraBuilder;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _scannerController;

  bool _processing = false;
  String? _lastCode;
  QrResolucionResult? _result;
  String? _errorMessage;

  void _resetScan() {
    setState(() {
      _lastCode = null;
      _result = null;
      _errorMessage = null;
    });
  }

  String _rejectionReason(ApiException error) {
    final codeErrors = error.validationErrors['codigo'];
    if (codeErrors != null && codeErrors.isNotEmpty) {
      return codeErrors.join('\n');
    }
    if (error.message.trim().isNotEmpty) {
      return error.message;
    }
    return switch (error.statusCode) {
      403 => 'Tu cuenta no tiene permiso para utilizar este código QR.',
      404 => 'El código QR no existe o no pertenece a un envío autorizado.',
      409 => 'Este código QR ya fue utilizado anteriormente.',
      _ => 'El código QR fue rechazado por el servidor.',
    };
  }

  @override
  void initState() {
    super.initState();
    if (widget.cameraBuilder == null && QrPermissions.canUseQr(widget.user)) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    unawaited(_scannerController?.dispose());
    super.dispose();
  }

  Future<void> _handleCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _processing) return;

    setState(() {
      _processing = true;
      _lastCode = code;
      _result = null;
      _errorMessage = null;
    });

    try {
      final resolved = await widget.service.resolveEnvioQr(widget.user, code);
      if (!mounted) return;
      setState(() {
        _processing = false;
        _result = resolved;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage = _rejectionReason(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage =
            'No se pudo validar el código QR. Verifica tu conexión e intenta nuevamente.';
      });
    }
  }

  Widget _defaultCamera(BuildContext context) {
    final controller = _scannerController!;
    return MobileScanner(
      controller: controller,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.trim().isNotEmpty) {
            unawaited(_handleCode(value));
            break;
          }
        }
      },
      errorBuilder: (context, error) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error.errorDetails?.message ??
                  'No se pudo inicializar la cámara para leer códigos QR.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!QrPermissions.canUseQr(widget.user)) {
      return ModuleAccessDenied(
        title: 'Lector de códigos QR',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Leer código QR')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('Escaneo con cámara'),
                  const SizedBox(height: 12),
                  Container(
                    key: const ValueKey('qr.camera_box'),
                    height: 260,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.ink, width: 2),
                    ),
                    child: widget.cameraBuilder != null
                        ? widget.cameraBuilder!(
                            context,
                            (code) => unawaited(_handleCode(code)),
                            (_) {},
                          )
                        : _defaultCamera(context),
                  ),
                  if (_lastCode != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      key: const ValueKey('qr.detected_code'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: AppTheme.ink, width: 1.5),
                      ),
                      child: DetailField(
                        label: 'Código leído',
                        value: _lastCode!,
                      ),
                    ),
                  ],
                  if (_processing) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Validando código QR con el servidor...'),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    AppNotice(
                      key: const ValueKey('qr.rechazo_notice'),
                      tone: AppNoticeTone.error,
                      message: _errorMessage!,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const ValueKey('qr.reintentar'),
                        onPressed: _processing ? null : _resetScan,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Leer otro código'),
                      ),
                    ),
                  ],
                  if (_result case final result?) ...[
                    const SizedBox(height: 16),
                    _resultCard(context, result),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultCard(BuildContext context, QrResolucionResult result) {
    final (AppNoticeTone tone, String statusMessage) = result.utilizado
        ? (
            AppNoticeTone.warning,
            'Este código QR ya fue utilizado. Puedes consultar la recepción registrada, pero no volver a confirmarla.',
          )
        : result.puedeConfirmar
        ? (
            AppNoticeTone.success,
            'Código válido y listo para registrar recepción.',
          )
        : (
            AppNoticeTone.info,
            'Código válido solo para consulta. Tu cuenta no está autorizada para confirmar esta recepción.',
          );

    return Column(
      key: const ValueKey('qr.resultado_card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppNotice(tone: tone, message: statusMessage),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.ink, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailField(label: 'Envío', value: result.envio.referencia),
              const Divider(height: 1),
              DetailField(label: 'Trayecto', value: result.envio.tipo.label),
              const Divider(height: 1),
              DetailField(label: 'Estado', value: result.envio.estadoLabel),
              if (result.envio.destinos.isNotEmpty) ...[
                const Divider(height: 1),
                DetailField(
                  label: 'Destino',
                  value: result.envio.destinos.map((d) => d.label).join(', '),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('qr.reintentar'),
            onPressed: _processing ? null : _resetScan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Leer otro código'),
          ),
        ),
      ],
    );
  }
}
