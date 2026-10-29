import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RecordStatusBadge extends StatelessWidget {
  const RecordStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color:
          status == 'Pendiente' ||
              status == 'Planificado' ||
              status == 'Planificación'
          ? AppTheme.ochre
          : AppTheme.sage,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      status,
      style: const TextStyle(
        color: AppTheme.forest,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
