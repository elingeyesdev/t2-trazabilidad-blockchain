import 'package:flutter/material.dart';

import '../models/module_page.dart';
import '../theme/app_theme.dart';
import 'record_status_badge.dart';

class ActivityHistoryCard extends StatelessWidget {
  const ActivityHistoryCard({super.key, required this.activity});

  final ModuleRecord activity;

  @override
  Widget build(BuildContext context) {
    final fields = activity.fieldInfo?.details ?? activity.details;
    final status = activity.fieldInfo?.status;
    final theme = Theme.of(context).textTheme;
    final notes = fields['Observaciones'] ?? 'No disponible';
    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.ink, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(activity.title, style: theme.titleLarge),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RecordStatusBadge(
                      status: status ?? 'Estado no disponible',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _dateLine(
                    Icons.play_circle_outline_rounded,
                    'Inicio: ${fields['Inicio'] ?? 'Sin registrar'}',
                    theme,
                  ),
                  if (status == 'Completada') ...[
                    const SizedBox(height: 8),
                    _dateLine(
                      Icons.flag_rounded,
                      'Finalización: ${fields['Finalización'] ?? 'Sin registrar'}',
                      theme,
                    ),
                  ],
                  const SizedBox(height: 12),
                  MergeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.person_rounded,
                            size: 20,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Responsable', style: theme.bodyMedium),
                              Text(
                                fields['Responsable'] ?? 'No disponible',
                                style: theme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Nota de campo: fondo de papel rayado suave.
            MergeSemantics(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F1DD),
                  border: Border(
                    top: BorderSide(color: AppTheme.line, width: 1.5),
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(AppTheme.radius - 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.edit_note_rounded,
                          size: 22,
                          color: AppTheme.inkSoft,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Observaciones', style: theme.bodyMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(notes, style: theme.bodyLarge),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateLine(IconData icon, String text, TextTheme theme) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 22, color: AppTheme.inkSoft),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: theme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}
