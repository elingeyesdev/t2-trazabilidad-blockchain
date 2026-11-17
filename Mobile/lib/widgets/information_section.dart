import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Related facts share a surface; long values and large text keep their space.
class InformationSection extends StatelessWidget {
  const InformationSection({
    super.key,
    required this.title,
    required this.fields,
    this.icon,
    this.columns = 1,
  });

  final String title;
  final Map<String, String> fields;
  final IconData? icon;
  final int columns;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.line),
    ),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: AppTheme.forest),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const Divider(height: 32, color: AppTheme.line),
        LayoutBuilder(
          builder: (context, constraints) {
            final paired =
                columns == 2 &&
                constraints.maxWidth >= 280 &&
                MediaQuery.textScalerOf(context).scale(16) <= 24;
            final width = paired
                ? (constraints.maxWidth - 24) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 24,
              runSpacing: 20,
              children: [
                for (final field in fields.entries)
                  SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.key,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          field.value,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
