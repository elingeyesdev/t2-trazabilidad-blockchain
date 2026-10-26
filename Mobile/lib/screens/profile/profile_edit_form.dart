import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/api_exception.dart';
import '../../models/profile_photo.dart';

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
                const SizedBox(height: 24),
                if (user?.canUpdateUsername == true)
                  TextFormField(
                    controller: _username,
                    enabled: !busy && !_needsReload,
                    decoration: InputDecoration(
                      labelText: 'Nombre de usuario',
                      prefixText: '@',
                      helperText: 'Solo puedes cambiarlo una vez.',
                      helperMaxLines: 2,
                      errorText: fieldError('nombreusuario'),
                      errorMaxLines: 3,
                      border: const OutlineInputBorder(),
                    ),
                    autocorrect: false,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Ingresa un nombre de usuario.'
                        : null,
                  )
                else
                  Text(
                    'Nombre de usuario: @${user?.username ?? ''}\nEl cambio de nombre no está disponible.',
                  ),
                if (user?.canUpdatePhoto == true) ...[
                  const SizedBox(height: 24),
                  if (_photo case final photo?) ...[
                    Image.memory(
                      photo.bytes,
                      height: 160,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined, size: 64),
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
                  const Text('JPG, PNG, WEBP o GIF, hasta 2 MB.'),
                  if (fieldError('imagen') case final message?)
                    Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
                if (_notice ?? error?.message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Semantics(liveRegion: true, child: Text(message)),
                  ),
                if (_needsReload) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'No se pudo confirmar el guardado. Consulta el perfil para comprobar si el cambio se aplicó antes de volver a guardar.',
                  ),
                  TextButton(
                    onPressed: busy ? null : widget.onReload,
                    child: const Text('Consultar perfil'),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy || _needsReload ? null : _save,
                  child: Text(
                    auth.isSavingProfile ? 'Guardando...' : 'Guardar cambios',
                  ),
                ),
                TextButton(
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
