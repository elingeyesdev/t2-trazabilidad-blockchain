import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/auth_user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/information_section.dart';
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
        onSaved: () {
          setState(() => _editing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Perfil actualizado correctamente.')),
          );
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
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.forest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _ProfileAvatar(url: user.avatarUrl),
                          const Spacer(),
                          const Icon(
                            Icons.eco_outlined,
                            color: AppTheme.ochre,
                            size: 32,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        user.fullName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        user.username == null
                            ? 'Sin registrar'
                            : '@${user.username}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              color: AppTheme.ochre,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                user.roles.isEmpty
                                    ? 'Sin roles asignados'
                                    : user.roles.map(_roleLabel).join(' · '),
                                style: const TextStyle(
                                  color: Colors.white,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (user.canUpdateUsername || user.canUpdatePhoto) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.ochre,
                            foregroundColor: AppTheme.forest,
                          ),
                          onPressed: () {
                            widget.controller.clearError();
                            setState(() => _editing = true);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Editar perfil'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                InformationSection(
                  title: 'Datos de contacto',
                  icon: Icons.person_outline_rounded,
                  fields: {
                    'Correo electrónico': user.email,
                    'Teléfono': user.phone ?? 'Sin registrar',
                    'CI/NIT': user.identityDocument ?? 'Sin registrar',
                  },
                ),
                const SizedBox(height: 16),
                InformationSection(
                  title: 'Actividad de la cuenta',
                  icon: Icons.history_rounded,
                  fields: {
                    'Miembro desde':
                        _date(user.registeredAt) ?? 'Sin registrar',
                    'Última actualización':
                        _date(user.updatedAt, withTime: true) ??
                        'Sin registrar',
                    'Último acceso':
                        _date(user.lastLoginAt, withTime: true) ??
                        'Sin registrar',
                  },
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: widget.controller.isSubmitting
                      ? null
                      : widget.controller.logout,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ],
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
  const _ProfileAvatar({required this.url});

  final String? url;

  Widget _fallback(BuildContext context) => ColoredBox(
    color: AppTheme.sage,
    child: const Icon(Icons.person_outline, size: 40, color: AppTheme.forest),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox.square(dimension: 80, child: image),
      ),
    );
  }
}
