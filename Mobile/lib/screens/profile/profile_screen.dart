import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/auth_user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../theme/app_glyphs.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import 'profile_edit_form.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loaded = false;
  bool _editing = false;
  String? _resultDetail;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    await widget.controller.refreshProfile();
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.logout_rounded,
      title: '¿Cerrar sesión?',
      message:
          'Se cerrará tu sesión en este dispositivo y volverás al inicio de sesión.',
      confirmLabel: 'Confirmar cierre',
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    await widget.controller.logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.controller;
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _editing && !auth.isSubmitting) {
          setState(() => _editing = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mi perfil'),
          actions: [
            IconButton(
              tooltip: 'Actualizar perfil',
              onPressed: auth.isSubmitting || _editing ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(child: _content(context)),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final auth = widget.controller;
    if (_editing) {
      return ProfileEditForm(
        controller: auth,
        onCancel: () => setState(() => _editing = false),
        onResult: (detail) => _resultDetail = detail,
        onSaved: () {
          setState(() {
            _editing = false;
            _resultDetail ??= 'Los datos de tu perfil ya están al día.';
          });
        },
        onReload: () {
          setState(() => _editing = false);
          unawaited(_refresh());
        },
      );
    }
    if (!_loaded || auth.isLoadingProfile) {
      return const AppLoading(message: 'Cargando perfil...');
    }
    final user = auth.user;
    return user == null ? const SizedBox.shrink() : _profile(context, user);
  }

  Widget _profile(BuildContext context, AuthUser user) {
    final theme = Theme.of(context).textTheme;
    final roleText = user.roles.isEmpty
        ? 'Sin roles asignados'
        : user.roles.map(_roleLabel).join(' · ');
    final fields = [
      ('Correo electrónico', user.email),
      ('Teléfono', user.phone),
      ('Nombre de usuario', user.username == null ? null : '@${user.username}'),
      ('CI/NIT', user.identityDocument),
    ];
    final since = _date(user.registeredAt);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _ProfileAvatar(url: user.avatarUrl, name: user.fullName),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              user.fullName,
                              style: theme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            roleText,
                            style: theme.bodyLarge?.copyWith(
                              color: AppTheme.fieldDeep,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (since != null)
                            Text(
                              'En AgroFusion desde $since',
                              style: theme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (user.canUpdateUsername || user.canUpdatePhoto) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      widget.controller.clearError();
                      setState(() {
                        _resultDetail = null;
                        _editing = true;
                      });
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar perfil'),
                  ),
                ],
                if (_resultDetail case final detail?) ...[
                  const SizedBox(height: 20),
                  AppNotice(
                    tone: AppNoticeTone.success,
                    title: 'Perfil actualizado correctamente.',
                    message: detail,
                  ),
                ],
                const SizedBox(height: 28),
                const SectionTitle('Tus datos'),
                const SizedBox(height: 14),
                _dataCard(context, fields),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: widget.controller.isSubmitting
                      ? null
                      : _confirmLogout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.clay,
                    side: const BorderSide(color: AppTheme.clay, width: 1),
                  ),
                  icon: const Icon(AppIcons.signOut, size: 20),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Datos de contacto en un solo bloque: nombre del dato arriba, valor abajo.
  Widget _dataCard(BuildContext context, List<(String, String?)> fields) {
    final theme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (label, value)) in fields.indexed) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.bodySmall),
                    const SizedBox(height: 2),
                    SelectableText(
                      value ?? 'Sin registrar',
                      style: theme.titleMedium?.copyWith(
                        color: value == null ? AppTheme.inkSoft : AppTheme.ink,
                        fontWeight: value == null
                            ? FontWeight.w400
                            : FontWeight.w700,
                        fontStyle: value == null ? FontStyle.italic : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _date(DateTime? value, {bool withTime = false}) {
    if (value == null) return null;
    final local = value.toLocal();
    String padded(int part) => part.toString().padLeft(2, '0');
    final date = '${padded(local.day)}/${padded(local.month)}/${local.year}';
    return withTime
        ? '$date ${padded(local.hour)}:${padded(local.minute)}'
        : date;
  }

  String _roleLabel(String role) => switch (role) {
    'admin' => 'Administrador',
    'jefe_agricultor' => 'Jefe agrícola',
    'agricultor' => 'Agricultor',
    'jefe_planta' => 'Jefe de planta',
    'planta' => 'Operador de planta',
    'transportista' => 'Transportista',
    'minorista' => 'Minorista',
    'mayorista' => 'Mayorista',
    _ => role,
  };
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.url, required this.name});

  final String? url;
  final String name;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Widget _fallback(BuildContext context) => ColoredBox(
    color: AppTheme.fieldDeep,
    child: Center(
      child: Text(
        _initials,
        style: AppTheme.display(32, 1, 800, 0).copyWith(color: Colors.white),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url ?? '');
    Widget image = _fallback(context);
    if (uri != null) {
      if ((uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        image = Image.network(
          url!,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          errorBuilder: (_, _, _) => _fallback(context),
        );
      } else if (uri.scheme == 'data') {
        try {
          final data = UriData.fromUri(uri);
          if (const {
            'image/png',
            'image/jpeg',
            'image/webp',
            'image/gif',
          }.contains(data.mimeType)) {
            image = Image.memory(
              data.contentAsBytes(),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(context),
            );
          }
        } on FormatException {
          image = _fallback(context);
        }
      }
    }
    return Semantics(
      label: 'Foto de perfil',
      image: true,
      child: Container(
        width: 84,
        height: 84,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: ClipOval(child: image),
      ),
    );
  }
}
