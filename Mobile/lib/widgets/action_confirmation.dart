import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppNoticeTone { info, success, warning, error }

class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    this.title,
    this.tone = AppNoticeTone.info,
    this.action,
  });

  final String? title;
  final String message;
  final AppNoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, border, icon) = switch (tone) {
      AppNoticeTone.info => (
        AppTheme.sage,
        AppTheme.forest,
        AppTheme.line,
        Icons.info_outline_rounded,
      ),
      AppNoticeTone.success => (
        AppTheme.sage,
        AppTheme.forest,
        AppTheme.forest.withValues(alpha: .22),
        Icons.check_circle_outline_rounded,
      ),
      AppNoticeTone.warning => (
        AppTheme.ochre.withValues(alpha: .28),
        AppTheme.ink,
        AppTheme.ochre,
        Icons.warning_amber_rounded,
      ),
      AppNoticeTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        scheme.error.withValues(alpha: .35),
        Icons.error_outline_rounded,
      ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null) ...[
                        Text(
                          title!,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        message,
                        style: TextStyle(
                          color: foreground,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: action!),
            ],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmImportantAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancelar',
  List<String> details = const [],
  IconData? icon,
  bool destructive = false,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final accent = destructive ? theme.colorScheme.error : AppTheme.forest;
      return AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: destructive
                      ? theme.colorScheme.errorContainer
                      : AppTheme.sage,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message, style: theme.textTheme.bodyLarge),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.sage,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < details.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        Text(
                          details[i],
                          style: const TextStyle(
                            color: AppTheme.forest,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(cancelLabel),
                  ),
                  FilledButton(
                    style: destructive
                        ? FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          )
                        : null,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}
