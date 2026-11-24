import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/trazabilidad_publica_models.dart';
import '../../theme/app_theme.dart';
import '../modules/qr_scanner_screen.dart';

class TrazabilidadLookupScreen extends StatefulWidget {
  const TrazabilidadLookupScreen({
    super.key,
    this.cameraBuilder,
    this.onCodeSelected,
  });

  final QrCameraBuilder? cameraBuilder;
  final ValueChanged<String>? onCodeSelected;

  @override
  State<TrazabilidadLookupScreen> createState() =>
      _TrazabilidadLookupScreenState();
}

class _TrazabilidadLookupScreenState extends State<TrazabilidadLookupScreen> {
  final _manualFormKey = GlobalKey<FormState>();
  final _manualCtrl = TextEditingController();
  MobileScannerController? _scannerController;

  bool _manualMode = false;
  QrCameraIssue? _cameraIssue;
  String? _detectedCode;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    if (widget.cameraBuilder == null) {
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

  void _handleInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    final extracted = TrazabilidadCodigoParser.extract(trimmed);
    if (extracted == null) {
      setState(() {
        _detectedCode = null;
        _parseError =
            'El código o enlace QR no corresponde a un código de trazabilidad válido.';
      });
      return;
    }

    setState(() {
      _parseError = null;
      _detectedCode = extracted;
    });
    widget.onCodeSelected?.call(extracted);
  }

  void _submitManual() {
    if (!(_manualFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    _handleInput(_manualCtrl.text);
  }

  void _resetLookup() {
    setState(() {
      _detectedCode = null;
      _parseError = null;
    });
  }

  Widget _defaultCamera(BuildContext context) {
    final controller = _scannerController!;
    return MobileScanner(
      controller: controller,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.trim().isNotEmpty) {
            _handleInput(value);
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.maizeSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC58C1F)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDenied
                ? Icons.no_photography_outlined
                : Icons.videocam_off_outlined,
            size: 36,
            color: const Color(0xFF5F4100),
          ),
          const SizedBox(height: 10),
          Text(
            isDenied ? 'Permiso de cámara denegado' : 'Cámara no disponible',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF5F4100),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isDenied
                ? 'Habilita el acceso a la cámara en los ajustes del dispositivo o ingresa el código manualmente.'
                : 'No se pudo iniciar la cámara en este dispositivo. Puedes escribir el código de trazabilidad.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5F4100)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('trazabilidad.cambiar_a_manual'),
            onPressed: () => setState(() {
              _manualMode = true;
              _cameraIssue = null;
            }),
            icon: const Icon(Icons.keyboard_rounded),
            label: const Text('Ingresar código manualmente'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Consultar trazabilidad')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.sprout,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.qr_code_scanner_rounded,
                                color: AppTheme.fieldDeep,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Consulta pública de producto',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Escanea el QR del envase o escribe el código (TRZ-PDV-... o TRZ-...) para conocer el recorrido del producto.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<bool>(
                          key: const ValueKey('trazabilidad.modo_selector'),
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.qr_code_scanner_rounded),
                              label: Text('Escanear QR'),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.keyboard_rounded),
                              label: Text('Ingresar código'),
                            ),
                          ],
                          selected: {_manualMode},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _manualMode = selection.first;
                              if (!_manualMode) _cameraIssue = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!_manualMode)
                    _buildCameraSection(context)
                  else
                    _buildManualSection(context),
                  if (_parseError != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      key: const ValueKey('trazabilidad.error_parseo'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.claySoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.clay),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppTheme.clay,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _parseError!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppTheme.clay,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar aviso',
                            onPressed: _resetLookup,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppTheme.clay,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_detectedCode != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      key: const ValueKey('trazabilidad.codigo_detectado'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.sprout,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.sproutBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_outlined,
                            color: AppTheme.fieldDeep,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Código listo para consultar',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: AppTheme.fieldDeep,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _detectedCode!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Limpiar',
                            onPressed: _resetLookup,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
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

  Widget _buildCameraSection(BuildContext context) {
    if (_cameraIssue != null) {
      return _cameraIssueCard(context, _cameraIssue!);
    }

    final camera = widget.cameraBuilder != null
        ? widget.cameraBuilder!(
            context,
            _handleInput,
            (issue) => setState(() => _cameraIssue = issue),
          )
        : _defaultCamera(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 260,
              child: ColoredBox(color: const Color(0xFF152019), child: camera),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Apunta al código QR impreso en la etiqueta del producto.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildManualSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Form(
        key: _manualFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const ValueKey('trazabilidad.codigo_input'),
              controller: _manualCtrl,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código de trazabilidad o enlace QR',
                hintText: 'Ej. TRZ-PDV-20261124-ABC123 o TRZ-...',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa un código de trazabilidad o pega el enlace del QR.';
                }
                if (TrazabilidadCodigoParser.extract(value) == null) {
                  return 'El código o enlace QR no corresponde a un código de trazabilidad válido.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submitManual(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('trazabilidad.consultar_btn'),
              onPressed: _submitManual,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Consultar producto'),
            ),
          ],
        ),
      ),
    );
  }
}
