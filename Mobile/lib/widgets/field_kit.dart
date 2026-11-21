import 'package:flutter/material.dart';

import '../navigation/app_module.dart';
import '../theme/app_theme.dart';
import '../theme/module_palette.dart';

/// Tarjeta tocable con borde firme y sombra de sello que "se hunde" al
/// presionarla, para que se entienda sin dudas que es un botón.
class PressableCard extends StatefulWidget {
  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.color = AppTheme.surface,
    this.borderColor = AppTheme.border,
    this.padding = const EdgeInsets.all(18),
    this.radius = AppTheme.radius,
    this.depth = 4,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double depth;
  final String? semanticLabel;

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final radius = BorderRadius.circular(widget.radius);
    final borderColor = enabled ? widget.borderColor : AppTheme.line;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: enabled && !_down && widget.depth > 0
            ? AppTheme.stamp(widget.depth)
            : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Material(
        color: widget.color,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: enabled
              ? (value) => setState(() => _down = value)
              : null,
          splashColor: AppTheme.field.withValues(alpha: .08),
          highlightColor: AppTheme.field.withValues(alpha: .05),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
    if (widget.semanticLabel == null) {
      return enabled ? MergeSemantics(child: card) : card;
    }
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: card,
    );
  }
}

/// Cuadro de color con el ícono del módulo.
class ModuleMark extends StatelessWidget {
  const ModuleMark(
    this.module, {
    super.key,
    this.size = 56,
    this.solid = false,
  });

  final AppModule module;
  final double size;

  /// Fondo oscuro con ícono claro, para usar sobre fondos del mismo tono.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final look = module.look;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: solid ? look.ink : look.tone,
          borderRadius: BorderRadius.circular(size * .3),
          border: Border.all(
            color: look.ink.withValues(alpha: solid ? .45 : .25),
            width: 1,
          ),
        ),
        child: Icon(
          module.icon,
          color: solid ? look.tone : look.ink,
          size: size * .54,
        ),
      ),
    );
  }
}

/// Medallón redondo para estados vacíos, errores y confirmaciones.
class IconMedallion extends StatelessWidget {
  const IconMedallion({
    super.key,
    required this.icon,
    this.tone = AppTheme.sprout,
    this.ink = AppTheme.fieldDeep,
    this.size = 96,
  });

  final IconData icon;
  final Color tone;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone,
        shape: BoxShape.circle,
        border: Border.all(color: ink.withValues(alpha: .35), width: 1),
        boxShadow: AppTheme.stamp(4, ink),
      ),
      child: Icon(icon, size: size * .46, color: ink),
    ),
  );
}

/// Línea "Etiqueta: valor" con ícono. El texto completo forma un único
/// [Text] para que los lectores de pantalla lo anuncien de corrido.
class InfoLine extends StatelessWidget {
  const InfoLine({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  static IconData iconFor(String label) => switch (label) {
    'Cultivo' => Icons.grass_rounded,
    'Responsable' => Icons.person_rounded,
    'Siembra' || 'Fecha de siembra' => Icons.event_rounded,
    'Pendientes' || 'Actividades pendientes' => Icons.pending_actions_rounded,
    'Lote' => Icons.landscape_rounded,
    'Fecha planificada' => Icons.event_note_rounded,
    'Inicio' => Icons.play_circle_outline_rounded,
    'Finalización' => Icons.flag_rounded,
    'Ubicación' => Icons.place_rounded,
    'Superficie' => Icons.straighten_rounded,
    'Estado' => Icons.info_outline_rounded,
    'Cantidad' || 'Stock' || 'Capacidad' => Icons.scale_rounded,
    'Planta' => Icons.factory_rounded,
    'Tipo de actividad' || 'Tipo' => Icons.category_rounded,
    'Prioridad' => Icons.priority_high_rounded,
    'Observaciones' || 'Descripción' => Icons.notes_rounded,
    'Código de trazabilidad' => Icons.qr_code_2_rounded,
    'Correo' => Icons.mail_outline_rounded,
    _ when label.toLowerCase().contains('fecha') => Icons.event_rounded,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon ?? iconFor(label),
            size: 22,
            color: AppTheme.inkSoft,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(color: AppTheme.inkSoft),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
            style: style,
          ),
        ),
      ],
    );
  }
}

/// Bloque de detalle: etiqueta pequeña arriba y valor grande abajo.
class DetailField extends StatelessWidget {
  const DetailField({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final missing = value == 'Sin registrar' || value == 'No disponible';
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                InfoLine.iconFor(label),
                size: 22,
                color: AppTheme.inkSoft,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.titleMedium?.copyWith(
                      color: missing ? AppTheme.inkSoft : AppTheme.ink,
                      fontWeight: missing ? FontWeight.w500 : FontWeight.w700,
                      fontStyle: missing ? FontStyle.italic : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Título de sección con una marca de color a la izquierda.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.color = AppTheme.field});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
        Container(
          width: 5,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    ),
  );
}

/// Barra inferior con un solo botón grande ("Volver ...").
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).height < 420 ||
        MediaQuery.textScalerOf(context).scale(16) > 24;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 20,
            compact ? 8 : 12,
            compact ? 16 : 20,
            compact ? 10 : 14,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Paisaje de surcos, sol y cerros para cabeceras. Puramente decorativo.
class FurrowPainter extends CustomPainter {
  const FurrowPainter({
    this.sun = AppTheme.maize,
    this.far = const Color(0xFF4F7F4A),
    this.near = const Color(0xFF3A6B3E),
    this.rows = const Color(0xFF7FA466),
  });

  final Color sun;
  final Color far;
  final Color near;
  final Color rows;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Sol con rayos cortos.
    final sunCenter = Offset(w * .74, h * .26);
    final sunPaint = Paint()..color = sun;
    canvas.drawCircle(sunCenter, h * .12, sunPaint);
    final ray = Paint()
      ..color = sun
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final angle = i * 3.14159 / 4;
      final dir = Offset.fromDirection(angle);
      canvas.drawLine(
        sunCenter + dir * (h * .17),
        sunCenter + dir * (h * .22),
        ray,
      );
    }
    // Cerro lejano.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * .62)
        ..quadraticBezierTo(w * .35, h * .3, w * .7, h * .52)
        ..quadraticBezierTo(w * .88, h * .62, w, h * .5)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = far,
    );
    // Parcela cercana con surcos en perspectiva.
    final nearPath = Path()
      ..moveTo(0, h * .78)
      ..quadraticBezierTo(w * .5, h * .5, w, h * .68)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(nearPath, Paint()..color = near);
    canvas.save();
    canvas.clipPath(nearPath);
    final furrow = Paint()
      ..color = rows
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final vanish = Offset(w * .55, h * .5);
    for (var i = -6; i <= 12; i++) {
      canvas.drawLine(vanish, Offset(i * w / 7, h * 1.15), furrow);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FurrowPainter oldDelegate) =>
      oldDelegate.sun != sun ||
      oldDelegate.far != far ||
      oldDelegate.near != near ||
      oldDelegate.rows != rows;
}

/// Marca de la app: hoja dentro de un sello.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.maize,
        borderRadius: BorderRadius.circular(size * .32),
        border: Border.all(color: const Color(0xFFC58C1F), width: 1),
      ),
      child: Icon(Icons.eco_rounded, color: AppTheme.ink, size: size * .6),
    ),
  );
}
