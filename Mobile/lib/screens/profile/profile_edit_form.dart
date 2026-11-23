import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/api_exception.dart';
import '../../models/profile_photo.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/camera_permission_notice.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/form_validation.dart';

class ProfileEditForm extends StatefulWidget {
  const ProfileEditForm({
    super.key,
    required this.controller,
    required this.onCancel,
    required this.onSaved,
    required this.onReload,
    this.onResult,
    this.selectFile,
    this.capturePhoto,
  });

  final AuthController controller;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final VoidCallback onReload;
  final ValueChanged<String>? onResult;
  final Future<XFile?> Function()? selectFile;
  final Future<XFile?> Function()? capturePhoto;

  @override
  State<ProfileEditForm> createState() => _ProfileEditFormState();
}

class _ProfileEditFormState extends State<ProfileEditForm> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(
    text: widget.controller.user?.username ?? '',
  );
  ProfilePhoto? _photo;
  String? _notice;
  String? _cameraPermissionMessage;
  bool get _needsReload => widget.controller.profileUpdateNeedsRefresh;

  @override
  void didUpdateWidget(covariant ProfileEditForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final user = widget.controller.user;
    if (user != null && !user.canUpdateUsername) {
      _username.text = user.username ?? '';
    }
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<ProfilePhoto?> _readPhoto(XFile? file) async {
    if (file == null) return null;
    if (await file.length() > ProfilePhoto.maxBytes) {
      throw const ApiException('Selecciona una imagen de hasta 2 MB.');
    }
    return ProfilePhoto(await file.readAsBytes(), name: file.name);
  }

  Future<void> _selectPhoto() async {
    setState(() => _notice = null);
    final photo = await widget.controller.selectProfilePhoto(() async {
      final file =
          await (widget.selectFile?.call() ??
              openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(
                    label: 'Fotografías',
                    extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
                    mimeTypes: [
                      'image/jpeg',
                      'image/png',
                      'image/webp',
                      'image/gif',
                    ],
                    uniformTypeIdentifiers: [
                      'public.jpeg',
                      'public.png',
                      'org.webmproject.webp',
                      'com.compuserve.gif',
                    ],
                  ),
                ],
              ));
      return _readPhoto(file);
    });
    if (mounted && photo != null) {
      setState(() {
        _photo = photo;
        _notice = null;
        _cameraPermissionMessage = null;
      });
    }
  }

  Future<void> _capturePhoto() async {
    setState(() => _notice = null);
    String? deniedMessage;
    final photo = await widget.controller.selectProfilePhoto(() async {
      try {
        final capture = widget.capturePhoto ?? captureCameraPhoto;
        return await _readPhoto(await capture());
      } catch (error) {
        if (CameraPermissionException.isPermissionError(error)) {
          deniedMessage = CameraPermissionException.messageFor(error);
          return null;
        }
        rethrow;
      }
    });
    if (!mounted) return;
    if (deniedMessage != null) {
      setState(() => _cameraPermissionMessage = deniedMessage);
    } else if (photo != null) {
      setState(() {
        _photo = photo;
        _notice = null;
        _cameraPermissionMessage = null;
      });
    }
  }

  bool get _hasUnsavedChanges {
    final user = widget.controller.user;
    if (user == null) return false;
    final name = _username.text.trim();
    final usernameChanged =
        user.canUpdateUsername && name != (user.username ?? '');
    final photoSelected = user.canUpdatePhoto && _photo != null;
    return usernameChanged || photoSelected;
  }

  Future<void> _cancel() async {
    if (widget.controller.isSubmitting) return;
    if (_hasUnsavedChanges && !_needsReload) {
      final discard = await confirmImportantAction(
        context,
        icon: Icons.warning_amber_rounded,
        title: '¿Descartar cambios?',
        message:
            'Tienes cambios sin guardar en tu perfil. Si sales ahora, no se aplicarán.',
        cancelLabel: 'Seguir editando',
        confirmLabel: 'Descartar cambios',
        destructive: true,
      );
      if (!mounted || !discard) return;
    }
    widget.controller.clearError();
    widget.onCancel();
  }

  Future<void> _save() async {
    final auth = widget.controller;
    if (auth.isSubmitting || _needsReload || !validateForm(_form)) {
      return;
    }
    final user = auth.user;
    if (user == null) return;
    final name = _username.text.trim();
    final username = user.canUpdateUsername && name != user.username
        ? name
        : null;
    final photo = user.canUpdatePhoto ? _photo : null;
    if (username == null && photo == null) {
      setState(() => _notice = 'No hay cambios para guardar.');
      return;
    }
    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.verified_user_outlined,
      title: '¿Guardar cambios del perfil?',
      message: username != null
          ? 'Revisa los datos antes de continuar. El nombre de usuario solo se puede modificar una vez.'
          : 'Se actualizará la fotografía visible en tu cuenta.',
      details: [
        if (username != null) 'Nuevo usuario: @$username',
        if (photo != null) 'Nueva fotografía: ${photo.filename}',
      ],
      confirmLabel: 'Confirmar cambios',
    );
    if (!mounted || !confirmed) return;
    setState(() => _notice = null);
    final saved = await auth.updateProfile(username: username, photo: photo);
    if (!saved && auth.error?.statusCode == 403) {
      await auth.refreshProfile(keepError: true);
    }
    if (!mounted) return;
    if (saved) {
      final detail = switch ((username != null, photo != null)) {
        (true, true) =>
          'Se guardaron tu usuario @$username y tu nueva fotografía.',
        (true, false) =>
          'Tu nombre de usuario quedó registrado como @$username.',
        _ => 'Se actualizó tu fotografía de perfil.',
      };
      widget.onResult?.call(detail);
      widget.onSaved();
    } else {
      revealFormErrors(_form);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.controller;
    final user = auth.user;
    final busy = auth.isSubmitting;
    final error = auth.error;
    final message =
        _notice ??
        (error != null &&
                (error.validationErrors.isEmpty ||
                    error.validationErrors.keys.any(
                      (field) => field != 'nombreusuario' && field != 'imagen',
                    ))
            ? error.message
            : null);
    String? fieldError(String field) =>
        error?.validationErrors[field]?.join('\n');
    final theme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: formContentPadding(context, base: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text('Editar perfil', style: theme.headlineSmall),
                ),
                const SizedBox(height: 6),
                Text(
                  'Actualiza tu nombre de usuario o tu fotografía.',
                  style: theme.bodyLarge?.copyWith(color: AppTheme.inkSoft),
                ),
                const SizedBox(height: 24),
                const SectionTitle('Nombre de usuario'),
                const SizedBox(height: 12),
                if (user?.canUpdateUsername == true)
                  TextFormField(
                    controller: _username,
                    scrollPadding: formScrollPadding(context),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    forceErrorText: fieldError('nombreusuario'),
                    enabled: !busy && !_needsReload,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                      labelText: 'Nombre de usuario',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                      helperText: 'Solo puedes cambiarlo una vez.',
                      helperMaxLines: 2,
                      errorMaxLines: 3,
                    ),
                    autocorrect: false,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Ingresa un nombre de usuario.'
                        : null,
                    onChanged: (_) {
                      if (_notice != null) setState(() => _notice = null);
                      auth.clearError(field: 'nombreusuario');
                    },
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.line, width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: AppTheme.inkSoft,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Nombre de usuario: @${user?.username ?? ''}\nEl cambio de nombre no está disponible.',
                            style: theme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (user?.canUpdatePhoto == true) ...[
                  const SizedBox(height: 28),
                  const SectionTitle('Fotografía', color: AppTheme.sprout),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.border, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_photo case final photo?) ...[
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                photo.bytes,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.broken_image_outlined,
                                  size: 64,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton.icon(
                              onPressed: busy || _needsReload
                                  ? null
                                  : () => setState(() => _photo = null),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Quitar selección'),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        OutlinedButton.icon(
                          onPressed: busy || _needsReload
                              ? null
                              : _capturePhoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Tomar foto'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: busy || _needsReload ? null : _selectPhoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Seleccionar foto'),
                        ),
                        if (_cameraPermissionMessage
                            case final cameraMessage?) ...[
                          const SizedBox(height: 16),
                          CameraPermissionNotice(
                            message: cameraMessage,
                            alternativeLabel: 'Elegir imagen del dispositivo',
                            onUseAlternative: busy || _needsReload
                                ? null
                                : _selectPhoto,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'JPG, PNG, WEBP o GIF, hasta 2 MB.',
                          textAlign: TextAlign.center,
                          style: theme.bodyMedium,
                        ),
                        if (fieldError('imagen') case final message?) ...[
                          const SizedBox(height: 10),
                          Text(
                            message,
                            style: const TextStyle(
                              color: AppTheme.clay,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 20),
                  AppNotice(
                    tone: _notice != null
                        ? AppNoticeTone.info
                        : AppNoticeTone.error,
                    message: message,
                  ),
                ],
                if (_needsReload) ...[
                  const SizedBox(height: 16),
                  AppNotice(
                    tone: AppNoticeTone.warning,
                    message:
                        'No se pudo confirmar el guardado. Consulta el perfil para comprobar si el cambio se aplicó antes de volver a guardar.',
                    action: TextButton(
                      onPressed: busy ? null : widget.onReload,
                      child: const Text('Consultar perfil'),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: busy || _needsReload ? null : _save,
                  icon: auth.isSavingProfile
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppTheme.inkSoft,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    auth.isSavingProfile ? 'Guardando...' : 'Guardar cambios',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy ? null : _cancel,
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
