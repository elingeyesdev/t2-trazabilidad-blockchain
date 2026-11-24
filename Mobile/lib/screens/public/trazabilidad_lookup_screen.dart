import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/api_exception.dart';
import '../../models/trazabilidad_publica_models.dart';
import '../../services/trazabilidad_publica_service.dart';
import '../../theme/app_theme.dart';
import '../modules/qr_scanner_screen.dart';

class TrazabilidadLookupScreen extends StatefulWidget {
  const TrazabilidadLookupScreen({
    super.key,
    required this.service,
    this.cameraBuilder,
    this.onCodeSelected,
    this.onResolved,
  });

  final TrazabilidadPublicaService service;
  final QrCameraBuilder? cameraBuilder;
  final ValueChanged<String>? onCodeSelected;
  final ValueChanged<TrazabilidadPublicaResumen>? onResolved;

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
  bool _loading = false;
  String? _lastCode;
  String? _parseError;
  bool _notFound = false;
  String? _connectionError;
  TrazabilidadPublicaResumen? _result;

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

  Future<void> _handleInput(String raw, {bool fromCamera = true}) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || _loading) return;

    final extracted = TrazabilidadCodigoParser.extract(trimmed);
    if (extracted == null) {
      setState(() {
        _lastCode = null;
        _result = null;
        _notFound = false;
        _connectionError = null;
        _parseError =
            'El código o enlace QR no corresponde a un código de trazabilidad válido.';
      });
      return;
    }

    if (fromCamera &&
        _lastCode == extracted &&
        (_result != null || _notFound || _connectionError != null)) {
      return;
    }

    widget.onCodeSelected?.call(extracted);
    await _lookupCode(extracted);
  }

  Future<void> _lookupCode(String codigo) async {
    setState(() {
      _loading = true;
      _lastCode = codigo;
      _parseError = null;
      _notFound = false;
      _connectionError = null;
      _result = null;
    });

    try {
      final result = await widget.service.consultarPorCodigo(codigo);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = result;
      });
      widget.onResolved?.call(result);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 404) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      setState(() {
        _loading = false;
        _connectionError = error.message.trim().isNotEmpty
            ? error.message
            : 'No se pudo consultar la trazabilidad. Intenta nuevamente.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _connectionError =
            'No se pudo conectar con el servidor. Revisa tu conexión e intenta nuevamente.';
      });
    }
  }

  Future<void> _retryLastCode() async {
    final codigo = _lastCode;
    if (codigo == null || _loading) return;
    await _lookupCode(codigo);
  }

  Future<void> _submitManual() async {
    if (!(_manualFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await _handleInput(_manualCtrl.text, fromCamera: false);
  }

  void _resetLookup({bool clearInput = false}) {
    setState(() {
      _lastCode = null;
      _parseError = null;
      _notFound = false;
      _connectionError = null;
      _result = null;
      if (clearInput) {
        _manualCtrl.clear();
      }
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
            unawaited(_handleInput(value));
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
      key: const ValueKey('trazabilidad.error_camara'),
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
                          onSelectionChanged: _loading
                              ? null
                              : (selection) {
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
                  if (_loading) ...[
                    const SizedBox(height: 18),
                    _buildLoadingCard(context),
                  ],
                  if (_parseError != null) ...[
                    const SizedBox(height: 18),
                    _buildParseErrorCard(context),
                  ],
                  if (_notFound) ...[
                    const SizedBox(height: 18),
                    _buildNotFoundCard(context),
                  ],
                  if (_connectionError != null) ...[
                    const SizedBox(height: 18),
                    _buildConnectionErrorCard(context),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 18),
                    _buildResultSummaryCard(context, _result!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('trazabilidad.cargando'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Consultando trazabilidad...',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_lastCode != null) ...[
                  const SizedBox(height: 2),
                  Text(_lastCode!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParseErrorCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
          const Icon(Icons.error_outline_rounded, color: AppTheme.clay),
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
            icon: const Icon(Icons.close_rounded, color: AppTheme.clay),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('trazabilidad.no_encontrado'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.maizeSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC58C1F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.search_off_rounded,
                color: Color(0xFF5F4100),
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Código no encontrado',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF5F4100),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No encontramos un producto registrado con el código ${_lastCode ?? ''}. Verifica la etiqueta e intenta con otro código.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF5F4100),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const ValueKey('trazabilidad.intentar_otro'),
            onPressed: () => _resetLookup(clearInput: true),
            icon: const Icon(Icons.qr_code_rounded),
            label: const Text('Consultar otro código'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionErrorCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('trazabilidad.error_conexion'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.claySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.clay),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: AppTheme.clay,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Error al consultar trazabilidad',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.clay,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _connectionError!,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.clay),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('trazabilidad.reintentar'),
                onPressed: _retryLastCode,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
              OutlinedButton(
                onPressed: () => _resetLookup(clearInput: false),
                child: const Text('Cambiar código'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultSummaryCard(
    BuildContext context,
    TrazabilidadPublicaResumen result,
  ) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('trazabilidad.resultado_resumen'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.sprout,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.sproutBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                color: AppTheme.fieldDeep,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.producto,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.fieldDeep,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      result.codigo,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppTheme.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (result.loteAgricola != null)
            Text('Origen agrícola: ${result.loteAgricola}'),
          if (result.puntoVenta != null)
            Text('Punto de venta: ${result.puntoVenta}'),
          Text(
            '${result.totalEventos} ${result.totalEventos == 1 ? 'evento registrado' : 'eventos registrados'} en el recorrido',
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const ValueKey('trazabilidad.otro_codigo'),
            onPressed: () => _resetLookup(clearInput: true),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Consultar otro producto'),
          ),
        ],
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
            (code) => unawaited(_handleInput(code)),
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
              enabled: !_loading,
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
              onFieldSubmitted: (_) => unawaited(_submitManual()),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('trazabilidad.consultar_btn'),
              onPressed: _loading ? null : _submitManual,
              icon: const Icon(Icons.search_rounded),
              label: Text(_loading ? 'Consultando...' : 'Consultar producto'),
            ),
          ],
        ),
      ),
    );
  }
}
