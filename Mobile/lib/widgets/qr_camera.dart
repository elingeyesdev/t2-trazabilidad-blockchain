import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';

enum QrCameraIssue { permissionDenied, unavailable }

/// Cámara alternativa (para pruebas): recibe cómo informar un código leído o
/// un problema de cámara.
typedef QrCameraBuilder =
    Widget Function(
      BuildContext context,
      ValueChanged<String> onCodeDetected,
      ValueChanged<QrCameraIssue> onCameraIssue,
    );

/// Cámara de lectura de QR compartida por el lector de envíos y la consulta
/// pública de trazabilidad. Abre el escáner, entrega cada código leído y, si
/// la cámara falla, muestra el aviso con salida al ingreso manual.
class QrCameraView extends StatefulWidget {
  const QrCameraView({
    super.key,
    required this.onCode,
    required this.onManual,
    this.cameraBuilder,
    this.cardKey,
    this.buttonKey,
    this.subject = 'código QR',
  });

  final ValueChanged<String> onCode;

  /// Se llama al pulsar "Ingresar código manualmente" en el aviso de cámara.
  final VoidCallback onManual;
  final QrCameraBuilder? cameraBuilder;
  final Key? cardKey;
  final Key? buttonKey;

  /// Cómo llamar a lo que se escanea en los avisos ("código QR", "código").
  final String subject;

  @override
  State<QrCameraView> createState() => _QrCameraViewState();
}

class _QrCameraViewState extends State<QrCameraView> {
  MobileScannerController? _controller;
  QrCameraIssue? _issue;

  @override
  void initState() {
    super.initState();
    if (widget.cameraBuilder == null) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  // El recuadro de la cámara tiene alto fijo: el aviso se desplaza si no cabe.
  Widget _issueCard(QrCameraIssue issue) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(6),
      child: QrCameraIssueCard(
        key: widget.cardKey,
        issue: issue,
        onManual: widget.onManual,
        buttonKey: widget.buttonKey,
        subject: widget.subject,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    if (issue != null) return _issueCard(issue);
    final custom = widget.cameraBuilder;
    if (custom != null) {
      return custom(
        context,
        widget.onCode,
        (issue) => setState(() => _issue = issue),
      );
    }
    return MobileScanner(
      controller: _controller!,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.trim().isNotEmpty) {
            widget.onCode(value);
            break;
          }
        }
      },
      errorBuilder: (context, error) => _issueCard(
        error.errorCode == MobileScannerErrorCode.permissionDenied
            ? QrCameraIssue.permissionDenied
            : QrCameraIssue.unavailable,
      ),
    );
  }
}

/// Aviso cuando la cámara no se puede usar, con salida al ingreso manual.
class QrCameraIssueCard extends StatelessWidget {
  const QrCameraIssueCard({
    super.key,
    required this.issue,
    required this.onManual,
    this.buttonKey,
    this.subject = 'código QR',
  });

  final String subject;
  final QrCameraIssue issue;
  final VoidCallback onManual;
  final Key? buttonKey;

  static const _ink = Color(0xFF5F4100);

  @override
  Widget build(BuildContext context) {
    final denied = issue == QrCameraIssue.permissionDenied;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.maizeSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC58C1F)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            denied
                ? Icons.no_photography_outlined
                : Icons.videocam_off_outlined,
            size: 28,
            color: _ink,
          ),
          const SizedBox(height: 6),
          Text(
            denied ? 'Permiso de cámara denegado' : 'Cámara no disponible',
            textAlign: TextAlign.center,
            style: theme.titleMedium?.copyWith(color: _ink),
          ),
          const SizedBox(height: 4),
          Text(
            denied
                ? 'Habilita el permiso de cámara en los ajustes del dispositivo para escanear, o ingresa el $subject manualmente.'
                : 'No se pudo iniciar la cámara en este dispositivo. Puedes ingresar el $subject manualmente para continuar.',
            textAlign: TextAlign.center,
            style: theme.bodyMedium?.copyWith(color: _ink),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: buttonKey,
            onPressed: onManual,
            icon: const Icon(Icons.keyboard_rounded),
            label: const Text('Ingresar código manualmente'),
          ),
        ],
      ),
    );
  }
}
