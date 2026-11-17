import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.inverse = false});

  final bool inverse;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: inverse ? AppTheme.ochre : AppTheme.forest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.eco_outlined,
          color: inverse ? AppTheme.forest : Colors.white,
          size: 26,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AgroFusion',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -.8,
                color: inverse ? Colors.white : AppTheme.ink,
              ),
            ),
            Text(
              'Trazabilidad agrícola',
              style: TextStyle(
                fontSize: 12,
                color: inverse ? Colors.white70 : AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The furrows are a brand motif, never a representation of a real lot.
class FieldLines extends CustomPainter {
  const FieldLines();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.ochre.withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 9; i++) {
      final offset = i * size.width / 7;
      canvas.drawPath(
        Path()
          ..moveTo(offset - size.width * .6, size.height)
          ..cubicTo(
            offset - size.width * .3,
            size.height * .55,
            offset + size.width * .6,
            size.height * .9,
            offset + size.width * .25,
            0,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FieldLines oldDelegate) => false;
}
