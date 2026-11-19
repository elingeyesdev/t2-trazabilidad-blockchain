import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
            width: 1.5,
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
