import 'package:flutter/material.dart';
import '../theme/app_glyphs.dart';

import '../navigation/app_module.dart';
import '../theme/app_theme.dart';
import '../theme/module_palette.dart';
import 'field_kit.dart';
import 'record_status_badge.dart';

/// Una línea de datos de una tarjeta. Con [label] vacío se muestra solo el
/// valor, en destacado.
typedef RecordFact = (String label, String value);

/// Tarjeta de registro común a todos los listados (lotes, actividades,
/// cosechas, tareas de planta, pedidos, entregas...).
///
/// Siempre se lee igual: marca del módulo y título arriba, estado debajo,
/// datos en el medio y una barra al pie que lleva el color del estado, la
/// misma que acompaña la franja lateral.
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.module,
    required this.title,
    this.status,
    this.eyebrow,
    this.facts = const [],
    this.onTap,
    this.footer = 'Ver detalle',
  });

  final AppModule module;
  final String title;
  final String? status;

  /// Dato corto sobre el título (por ejemplo "Etapa 2").
  final String? eyebrow;
  final List<RecordFact> facts;
  final VoidCallback? onTap;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final look = module.look;
    final tone = status == null
        ? (
            bar: look.tone,
            ink: look.ink,
            stripe: look.ink.withValues(alpha: .5),
          )
        : RecordStatusBadge.barFor(status!, look);
    final theme = Theme.of(context).textTheme;
    final large = MediaQuery.textScalerOf(context).scale(16) > 24;
    return PressableCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: tone.stripe, width: 6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!large) ...[
                    ModuleMark(module, size: 44),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null)
                          Text(
                            eyebrow!,
                            style: theme.bodySmall?.copyWith(
                              color: look.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(title, style: theme.titleLarge),
                        if (status != null) ...[
                          const SizedBox(height: 8),
                          RecordStatusBadge(status: status!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (facts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, fact) in facts.indexed) ...[
                      if (i > 0) const SizedBox(height: 6),
                      _fact(theme, fact),
                    ],
                  ],
                ),
              )
            else
              const SizedBox(height: 10),
            if (onTap != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: BoxDecoration(
                  color: tone.bar,
                  border: Border(
                    top: BorderSide(color: tone.ink.withValues(alpha: .18)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        footer,
                        style: TextStyle(
                          color: tone.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(AppIcons.caretRight, color: tone.ink, size: 20),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fact(TextTheme theme, RecordFact fact) {
    final (label, value) = fact;
    final missing = value == 'Sin registrar' || value == 'No disponible';
    return Text.rich(
      TextSpan(
        children: [
          if (label.isNotEmpty)
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: AppTheme.inkSoft),
            ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: missing ? FontWeight.w400 : FontWeight.w700,
              fontStyle: missing ? FontStyle.italic : null,
              color: missing ? AppTheme.inkSoft : AppTheme.ink,
            ),
          ),
        ],
      ),
      style: theme.bodyLarge,
    );
  }
}
