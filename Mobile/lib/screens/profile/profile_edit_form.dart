import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/api_exception.dart';
import '../../models/profile_photo.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
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
  });

  final AuthController controller;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final VoidCallback onReload;
  final ValueChanged<String>? onResult;
  final Future<XFile?> Function()? selectFile;

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
      if (file == null) return null;
      if (await file.length() > ProfilePhoto.maxBytes) {
        throw const ApiException('Selecciona una imagen de hasta 2 MB.');
      }
      return ProfilePhoto(await file.readAsBytes(), name: file.name);
    });
    if (mounted && photo != null) {
      setState(() {
        _photo = photo;
        _notice = null;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Editar perfil',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('Personaliza cómo apareces en AgroFusion.'),
                const SizedBox(height: 24),
                if (user?.canUpdateUsername == true)
                  TextFormField(
                    controller: _username,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    forceErrorText: fieldError('nombreusuario'),
                    enabled: !busy && !_needsReload,
                    decoration: InputDecoration(
                      labelText: 'Nombre de usuario',
                      prefixText: '@',
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
                  Text(
                    'Nombre de usuario: @${user?.username ?? ''}\nEl cambio de nombre no está disponible.',
                  ),
                if (user?.canUpdatePhoto == true) ...[
                  const SizedBox(height: 24),
                  const Divider(color: AppTheme.line),
                  const SizedBox(height: 16),
                  Text(
                    'Fotografía',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Una imagen para reconocer tu cuenta.'),
                  const SizedBox(height: 16),
                  if (_photo case final photo?) ...[
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.memory(
                          photo.bytes,
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined, size: 64),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy || _needsReload
                          ? null
                          : () => setState(() => _photo = null),
                      child: const Text('Quitar selección'),
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: busy || _needsReload ? null : _selectPhoto,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Seleccionar foto'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'JPG, PNG, WEBP o GIF, hasta 2 MB.',
                    textAlign: TextAlign.center,
                  ),
                  if (fieldError('imagen') case final message?)
                    Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: AppNotice(
                      tone: _notice != null
                          ? AppNoticeTone.info
                          : AppNoticeTone.error,
                      message: message,
                    ),
                  ),
                if (_needsReload)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppNotice(
                      tone: AppNoticeTone.warning,
                      message:
                          'No se pudo confirmar el guardado. Consulta el perfil para comprobar si el cambio se aplicó antes de volver a guardar.',
                      action: TextButton(
                        onPressed: busy ? null : widget.onReload,
                        child: const Text('Consultar perfil'),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy || _needsReload ? null : _save,
                  child: Text(
                    auth.isSavingProfile ? 'Guardando...' : 'Guardar cambios',
                  ),
                ),
                TextButton(
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
