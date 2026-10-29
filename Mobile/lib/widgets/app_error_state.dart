import 'package:flutter/material.dart';
import 'app_empty_state.dart';

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No pudimos cargar la información',
        message: message,
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        ),
      ),
    );
  }
}
