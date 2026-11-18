import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'field_kit.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.tone = AppTheme.sprout,
    this.ink = AppTheme.fieldDeep,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Color tone;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).height < 640 ||
        MediaQuery.textScalerOf(context).scale(16) > 22;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          compact ? 12 : 24,
          24,
          compact ? 16 : 28,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconMedallion(
                icon: icon,
                tone: tone,
                ink: ink,
                size: compact ? 64 : 88,
              ),
              SizedBox(height: compact ? 16 : 24),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppTheme.inkSoft),
              ),
              if (action != null) ...[
                SizedBox(height: compact ? 18 : 24),
                SizedBox(width: double.infinity, child: action!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
