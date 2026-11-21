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
  final _manualFormKey = GlobalKey<FormState>();
  final _manualCtrl = TextEditingController();
  MobileScannerController? _scannerController;

  bool _manualMode = false;
  QrCameraIssue? _cameraIssue;
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
    _manualCtrl.dispose();
    unawaited(_scannerController?.dispose());
    super.dispose();
  }

  Future<void> _submitManual() async {
    if (!(_manualFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await _handleCode(_manualCtrl.text, fromCamera: false);
  }

  Future<void> _handleCode(String rawCode, {bool fromCamera = true}) async {
    final code = rawCode.trim();
    if (code.isEmpty || _processing) return;
    if (fromCamera &&
        _lastCode == code &&
        (_result != null || _errorMessage != null)) {
      return;
    }

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
        final issue = error.errorCode == MobileScannerErrorCode.permissionDenied
            ? QrCameraIssue.permissionDenied
            : QrCameraIssue.unavailable;
        return _cameraIssueCard(context, issue);
      },
    );
  }

  Widget _cameraIssueCard(BuildContext context, QrCameraIssue issue) {
    final isDenied = issue == QrCameraIssue.permissionDenied;
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('qr.camera_issue_card'),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 36,
              color: AppTheme.ink,
            ),
            const SizedBox(height: 10),
            Text(
              isDenied ? 'Permiso de cámara denegado' : 'Cámara no disponible',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isDenied
                  ? 'Habilita el permiso de cámara en los ajustes del dispositivo para escanear, o ingresa el código QR manualmente.'
                  : 'No se pudo iniciar la cámara en este dispositivo. Puedes ingresar el código QR manualmente para continuar.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('qr.usar_manual_btn'),
              onPressed: () => setState(() => _manualMode = true),
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Ingresar código manualmente'),
            ),
          ],
        ),
      ),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('qr.modo_camara'),
                        label: const Text('Cámara'),
                        selected: !_manualMode,
                        selectedColor: AppTheme.maize,
                        backgroundColor: AppTheme.surface,
                        side: const BorderSide(color: AppTheme.ink, width: 1.5),
                        onSelected: (_) => setState(() => _manualMode = false),
                      ),
                      ChoiceChip(
                        key: const ValueKey('qr.modo_manual'),
                        label: const Text('Ingreso manual'),
                        selected: _manualMode,
                        selectedColor: AppTheme.maize,
                        backgroundColor: AppTheme.surface,
                        side: const BorderSide(color: AppTheme.ink, width: 1.5),
                        onSelected: (_) => setState(() => _manualMode = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!_manualMode) ...[
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
                      child: _cameraIssue != null
                          ? _cameraIssueCard(context, _cameraIssue!)
                          : widget.cameraBuilder != null
                          ? widget.cameraBuilder!(
                              context,
                              (code) => unawaited(_handleCode(code)),
                              (issue) => setState(() => _cameraIssue = issue),
                            )
                          : _defaultCamera(context),
                    ),
                  ] else ...[
                    const SectionTitle('Ingreso manual del código'),
                    const SizedBox(height: 12),
                    Form(
                      key: _manualFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            key: const ValueKey('qr.manual_input'),
                            controller: _manualCtrl,
                            enabled: !_processing,
                            decoration: const InputDecoration(
                              labelText: 'Código QR o enlace de recepción',
                              prefixIcon: Icon(Icons.qr_code_2_rounded),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Introduce o pega el código QR para validarlo.';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => unawaited(_submitManual()),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const ValueKey('qr.manual_submit'),
                            onPressed: _processing
                                ? null
                                : () => unawaited(_submitManual()),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('Validar código'),
                          ),
                        ],
                      ),
                    ),
                  ],
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
        FilledButton.icon(
          key: const ValueKey('qr.abrir_destino'),
          onPressed: _processing
              ? null
              : () => Navigator.of(context).pushNamed(
                  '/modules/envios/${result.envio.tipo.value}/${result.envio.id}',
                  arguments: result,
                ),
          icon: Icon(
            result.puedeConfirmar && !result.utilizado
                ? Icons.fact_check_outlined
                : Icons.visibility_outlined,
          ),
          label: Text(
            result.puedeConfirmar && !result.utilizado
                ? 'Abrir recepción del envío'
                : 'Abrir consulta del envío',
          ),
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
    );
  }
}
