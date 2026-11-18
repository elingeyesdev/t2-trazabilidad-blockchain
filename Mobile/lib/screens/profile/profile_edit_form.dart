import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/api_exception.dart';
import '../../models/profile_photo.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_kit.dart';

class ProfileEditForm extends StatefulWidget {
  const ProfileEditForm({
    super.key,
    required this.controller,
    required this.onCancel,
    required this.onSaved,
    required this.onReload,
    this.selectFile,
  });

  final AuthController controller;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final VoidCallback onReload;
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

  Future<void> _save() async {
    final auth = widget.controller;
    if (auth.isSubmitting || _needsReload || !_form.currentState!.validate()) {
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
    setState(() => _notice = null);
    final saved = await auth.updateProfile(username: username, photo: photo);
    if (!saved && auth.error?.statusCode == 403) {
      await auth.refreshProfile(keepError: true);
    }
    if (!mounted) return;
    if (saved) {
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.controller;
    final user = auth.user;
    final busy = auth.isSubmitting;
    final error = auth.error;
    final theme = Theme.of(context).textTheme;
    String? fieldError(String field) =>
        error?.validationErrors[field]?.join('\n');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
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
                    enabled: !busy && !_needsReload,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'Nombre de usuario',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      helperText: 'Solo puedes cambiarlo una vez.',
                      helperMaxLines: 2,
                      errorText: fieldError('nombreusuario'),
                      errorMaxLines: 3,
                    ),
                    autocorrect: false,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Ingresa un nombre de usuario.'
                        : null,
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.line, width: 2),
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
                      border: Border.all(color: AppTheme.ink, width: 2),
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
                                height: 160,
                                fit: BoxFit.contain,
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
                          onPressed: busy || _needsReload ? null : _selectPhoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Seleccionar foto'),
                        ),
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
                if (_notice ?? error?.message case final message?) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _notice != null
                            ? AppTheme.maizeSoft
                            : AppTheme.claySoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _notice != null
                              ? const Color(0xFF5F4100)
                              : AppTheme.clay,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _notice != null
                                ? Icons.info_outline_rounded
                                : Icons.error_outline_rounded,
                            color: _notice != null
                                ? const Color(0xFF5F4100)
                                : AppTheme.clay,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                color: _notice != null
                                    ? const Color(0xFF5F4100)
                                    : const Color(0xFF5E1D0E),
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_needsReload) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.maizeSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF5F4100),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'No se pudo confirmar el guardado. Consulta el perfil para comprobar si el cambio se aplicó antes de volver a guardar.',
                          style: TextStyle(
                            color: Color(0xFF5F4100),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: busy ? null : widget.onReload,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Consultar perfil'),
                        ),
                      ],
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
                  onPressed: busy ? null : widget.onCancel,
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
