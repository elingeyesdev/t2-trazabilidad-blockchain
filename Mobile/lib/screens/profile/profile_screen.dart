import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/auth_user.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
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
    final theme = Theme.of(context);
    final roleText = user.roles.isEmpty
        ? 'Sin roles asignados'
        : user.roles.map(_roleLabel).join(' · ');
    final personalFields = [
      (
        icon: Icons.alternate_email_rounded,
        label: 'Nombre de usuario',
        value: user.username == null ? null : '@${user.username}',
      ),
      (
        icon: Icons.mail_outline_rounded,
        label: 'Correo electrónico',
        value: user.email,
      ),
      (icon: Icons.phone_outlined, label: 'Teléfono', value: user.phone),
      (
        icon: Icons.badge_outlined,
        label: 'CI/NIT',
        value: user.identityDocument,
      ),
      (icon: Icons.shield_outlined, label: 'Roles', value: roleText),
    ];
    final activityFields = [
      (
        icon: Icons.calendar_today_outlined,
        label: 'Miembro desde',
        value: _date(user.registeredAt),
      ),
      (
        icon: Icons.update_rounded,
        label: 'Última actualización',
        value: _date(user.updatedAt, withTime: true),
      ),
      (
        icon: Icons.login_rounded,
        label: 'Último acceso',
        value: _date(user.lastLoginAt, withTime: true),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _idCard(theme, user),
                if (user.canUpdateUsername || user.canUpdatePhoto) ...[
                  const SizedBox(height: 18),
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
                _infoCard(context, personalFields),
                const SizedBox(height: 28),
                const SectionTitle('Tu actividad', color: AppTheme.sprout),
                const SizedBox(height: 14),
                _infoCard(context, activityFields),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: widget.controller.isSubmitting
                      ? null
                      : _confirmLogout,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.clay,
                    side: const BorderSide(color: AppTheme.clay, width: 2),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _idCard(ThemeData theme, AuthUser user) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: AppTheme.sprout,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppTheme.ink, width: 2),
      boxShadow: AppTheme.stamp(5),
    ),
    child: Column(
      children: [
        _ProfileAvatar(url: user.avatarUrl),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            user.fullName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.ink, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: AppTheme.field,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Cuenta activa',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppTheme.fieldDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _infoCard(
    BuildContext context,
    List<({IconData icon, String label, String? value})> fields,
  ) {
    final theme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.paper,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.line, width: 1.5),
                    ),
                    child: Icon(
                      fields[i].icon,
                      size: 22,
                      color: AppTheme.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fields[i].label, style: theme.bodyMedium),
                        const SizedBox(height: 2),
                        SelectableText(
                          fields[i].value ?? 'Sin registrar',
                          style: theme.titleMedium?.copyWith(
                            color: fields[i].value == null
                                ? AppTheme.inkSoft
                                : AppTheme.ink,
                            fontWeight: fields[i].value == null
                                ? FontWeight.w500
                                : FontWeight.w700,
                            fontStyle: fields[i].value == null
                                ? FontStyle.italic
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
  const _ProfileAvatar({required this.url});

  final String? url;

  Widget _fallback(BuildContext context) => ColoredBox(
    color: AppTheme.maizeSoft,
    child: const Icon(Icons.person_outline, size: 52, color: AppTheme.ink),
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
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.ink, width: 3),
          boxShadow: AppTheme.stamp(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: ClipOval(child: image),
      ),
    );
  }
}
