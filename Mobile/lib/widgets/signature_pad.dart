import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];

  List<List<Offset>> get strokes => List.unmodifiable(_strokes);

  bool get isEmpty => _strokes.isEmpty;
  bool get hasSignature => _strokes.isNotEmpty;

  void startStroke(Offset point) {
    _strokes.add([point]);
    notifyListeners();
  }

  void addPoint(Offset point) {
    if (_strokes.isEmpty) {
      _strokes.add([point]);
    } else {
      _strokes.last.add(point);
    }
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _strokes.clear();
    notifyListeners();
  }

  Future<String?> exportPngDataUrl({
    Size canvasSize = const Size(600, 220),
  }) async {
    if (_strokes.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
      bgPaint,
    );
    final inkPaint = Paint()
      ..color = AppTheme.ink
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in _strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.8, inkPaint);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, inkPaint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      canvasSize.width.round(),
      canvasSize.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }
}

class SignaturePad extends StatelessWidget {
  const SignaturePad({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final SignaturePadController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasSignature = controller.hasSignature;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.ink, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasSignature
                          ? 'Firma lista para confirmar'
                          : 'Traza tu firma en el recuadro',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: hasSignature ? AppTheme.forest : AppTheme.ink,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('recepcion_envio.limpiar_firma'),
                    onPressed: enabled && hasSignature
                        ? controller.clear
                        : null,
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 18,
                    ),
                    label: const Text('Limpiar firma'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                key: const ValueKey('recepcion_envio.firma_pad'),
                height: 180,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border, width: 1.5),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: enabled
                      ? (details) =>
                            controller.startStroke(details.localPosition)
                      : null,
                  onPanUpdate: enabled
                      ? (details) => controller.addPoint(details.localPosition)
                      : null,
                  child: CustomPaint(
                    painter: _SignaturePainter(controller.strokes),
                    size: Size.infinite,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.ink
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.8, paint);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
