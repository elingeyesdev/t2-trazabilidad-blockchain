import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'action_confirmation.dart';

class CameraPermissionException implements Exception {
  const CameraPermissionException([
    this.message =
        'El teléfono no permitió usar la cámara. Habilita el permiso en los ajustes del dispositivo o continúa con las alternativas disponibles.',
  ]);

  final String message;

  static bool isPermissionError(Object error) {
    if (error is CameraPermissionException) return true;
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      return code.contains('permission') ||
          code.contains('camera_access_denied') ||
          code.contains('access_denied') ||
          code.contains('denied');
    }
    return false;
  }

  static String messageFor(Object error) {
    if (error is CameraPermissionException) return error.message;
    return 'El teléfono no permitió usar la cámara. Habilita el permiso en los ajustes del dispositivo o continúa con las alternativas disponibles.';
  }
}

class CameraPermissionNotice extends StatelessWidget {
  const CameraPermissionNotice({
    super.key,
    required this.message,
    required this.alternativeLabel,
    required this.onUseAlternative,
    this.title = 'Permiso de cámara denegado',
    this.secondaryLabel,
    this.onSecondaryAction,
  });

  final String title;
  final String message;
  final String alternativeLabel;
  final VoidCallback? onUseAlternative;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return AppNotice(
      tone: AppNoticeTone.warning,
      title: title,
      message: message,
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onUseAlternative,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: Text(alternativeLabel),
          ),
          if (secondaryLabel != null && onSecondaryAction != null)
            TextButton(
              onPressed: onSecondaryAction,
              child: Text(secondaryLabel!),
            ),
        ],
      ),
    );
  }
}
