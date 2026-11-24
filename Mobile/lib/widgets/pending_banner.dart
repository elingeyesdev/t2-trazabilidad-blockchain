import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/auth_user.dart';
import '../services/pending_queue.dart';
import 'action_confirmation.dart';

/// Avisa de lo que quedó guardado sin señal y permite enviarlo o descartarlo.
/// No ocupa lugar si no hay nada pendiente ni se está usando el caché.
class PendingBanner extends StatelessWidget {
  const PendingBanner({
    super.key,
    required this.user,
    required this.pending,
    required this.offlineData,
    required this.onSync,
  });

  final AuthUser user;
  final PendingQueue pending;
  final ValueListenable<bool> offlineData;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([pending, offlineData]),
    builder: (context, _) {
      final items = pending.forUser(user);
      final waiting = items.where((item) => item.error == null).length;
      final rejected = items.where((item) => item.error != null).toList();
      if (items.isEmpty && !offlineData.value) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (offlineData.value)
              const AppNotice(
                tone: AppNoticeTone.warning,
                title: 'Sin conexión',
                message:
                    'Estás viendo lo último que se consultó. Los cambios se guardan en el teléfono.',
              ),
            if (waiting > 0) ...[
              if (offlineData.value) const SizedBox(height: 10),
              AppNotice(
                tone: AppNoticeTone.info,
                title: waiting == 1
                    ? '1 registro por enviar'
                    : '$waiting registros por enviar',
                message: 'Se envían solos cuando vuelve la señal.',
                action: OutlinedButton.icon(
                  onPressed: pending.syncing ? null : onSync,
                  icon: pending.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(pending.syncing ? 'Enviando...' : 'Enviar ahora'),
                ),
              ),
            ],
            for (final item in rejected) ...[
              const SizedBox(height: 10),
              AppNotice(
                tone: AppNoticeTone.error,
                title: 'No se pudo enviar: ${item.label}',
                message: item.error!,
                action: OutlinedButton.icon(
                  onPressed: () => pending.discard(item),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Descartar'),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
