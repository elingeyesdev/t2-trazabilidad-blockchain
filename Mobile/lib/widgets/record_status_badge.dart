import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/module_palette.dart';

/// Sello de estado: color + ícono + palabra, para que nunca dependa sólo del
/// color (daltonismo, pantallas al sol).
class RecordStatusBadge extends StatelessWidget {
  const RecordStatusBadge({super.key, required this.status});

  final String status;

  static ({Color tone, Color ink, IconData icon}) styleFor(String status) {
    final value = status.toLowerCase();
    if (value.contains('no disponible')) {
      return (
        tone: const Color(0xFFE9E4D8),
        ink: AppTheme.inkSoft,
        icon: Icons.help_outline_rounded,
      );
    }
    if (value.startsWith('pendiente')) {
      return (
        tone: AppTheme.maizeSoft,
        ink: const Color(0xFF5F4100),
        icon: Icons.schedule_rounded,
      );
    }
    if (value.startsWith('planific')) {
      return (
        tone: AppTheme.skySoft,
        ink: AppTheme.sky,
        icon: Icons.event_note_rounded,
      );
    }
    if (value.startsWith('complet') ||
        value.startsWith('cosech') ||
        value.startsWith('finaliz') ||
        value.startsWith('certific')) {
      return (
        tone: AppTheme.field,
        ink: Colors.white,
        icon: Icons.check_circle_rounded,
      );
    }
    if (value.contains('cancel') || value.contains('rechaz')) {
      return (
        tone: AppTheme.claySoft,
        ink: AppTheme.clay,
        icon: Icons.cancel_rounded,
      );
    }
    return (
      tone: AppTheme.sprout,
      ink: AppTheme.fieldDeep,
      icon: Icons.spa_rounded,
    );
  }

  /// Color de la franja lateral de una tarjeta: el estado se reconoce antes
  /// de leer. El texto y el ícono del sello siguen diciéndolo con palabras.
  static Color accentFor(String status) {
    final value = status.toLowerCase();
    if (value.startsWith('pendiente')) return AppTheme.maize;
    if (value.startsWith('planific')) return AppTheme.sky;
    if (value.contains('cancel') || value.contains('rechaz')) {
      return AppTheme.clay;
    }
    if (value.startsWith('complet') ||
        value.startsWith('cosech') ||
        value.startsWith('finaliz') ||
        value.startsWith('certific')) {
      return AppTheme.field;
    }
    return AppTheme.sproutBorder;
  }

  /// Barra al pie de una tarjeta: fondo y tinta suaves del estado. Si el
  /// estado no tiene color propio, usa el del módulo.
  static ({Color bar, Color ink, Color stripe}) barFor(
    String status,
    ModuleLook look,
  ) {
    final value = status.toLowerCase();
    final stripe = accentFor(status);
    if (value.startsWith('pendiente')) {
      return (
        bar: AppTheme.maizeSoft,
        ink: const Color(0xFF5F4100),
        stripe: stripe,
      );
    }
    if (value.startsWith('planific')) {
      return (bar: AppTheme.skySoft, ink: AppTheme.sky, stripe: stripe);
    }
    if (value.contains('cancel') || value.contains('rechaz')) {
      return (bar: AppTheme.claySoft, ink: AppTheme.clay, stripe: stripe);
    }
    if (value.startsWith('complet') ||
        value.startsWith('cosech') ||
        value.startsWith('finaliz') ||
        value.startsWith('certific')) {
      return (bar: AppTheme.sprout, ink: AppTheme.fieldDeep, stripe: stripe);
    }
    return (bar: look.tone, ink: look.ink, stripe: stripe);
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(status);
    return Semantics(
      label: 'Estado:',
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
        decoration: BoxDecoration(
          color: style.tone,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: style.ink == Colors.white ? AppTheme.fieldDeep : style.ink,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 20, color: style.ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                status,
                style: TextStyle(
                  color: style.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
