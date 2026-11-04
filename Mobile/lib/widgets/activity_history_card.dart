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
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              activity.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: RecordStatusBadge(
                status: status ?? 'Estado no disponible',
              ),
            ),
            const SizedBox(height: 20),
            _information(
              context,
              Icons.calendar_today_outlined,
              'Inicio: ${fields['Inicio'] ?? 'Sin registrar'}',
            ),
            if (status == 'Completada') ...[
              const SizedBox(height: 12),
              _information(
                context,
                Icons.event_available_outlined,
                'Finalización: ${fields['Finalización'] ?? 'Sin registrar'}',
              ),
            ],
            const SizedBox(height: 16),
            Text('Responsable', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              fields['Responsable'] ?? 'No disponible',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const Divider(height: 32, color: AppTheme.line),
            Text(
              'Observaciones',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              fields['Observaciones'] ?? 'No disponible',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _information(BuildContext context, IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: AppTheme.muted),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
    ],
  );
}
