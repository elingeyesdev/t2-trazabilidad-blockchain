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
        _errorMessage = error.message;
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
                      tone: AppNoticeTone.error,
                      message: _errorMessage!,
                    ),
                  ],
                  if (_result case final result?) ...[
                    const SizedBox(height: 16),
                    AppNotice(
                      tone: AppNoticeTone.success,
                      message:
                          'Código leído correctamente: ${result.envio.referencia} (${result.envio.tipo.label}).',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
