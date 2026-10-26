import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/auth_user.dart';
import '../../widgets/app_loading.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loaded = false;

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
    final user = auth.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          IconButton(
            tooltip: 'Actualizar perfil',
            onPressed: auth.isSubmitting ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: !_loaded || auth.isLoadingProfile
            ? const AppLoading(message: 'Cargando perfil...')
            : user == null
            ? const SizedBox.shrink()
            : _profile(context, user),
      ),
    );
  }

  Widget _profile(BuildContext context, AuthUser user) {
    final theme = Theme.of(context);
    Widget information(IconData icon, String label, String? value) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: SelectableText(value ?? 'Sin registrar'),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _ProfileAvatar(url: user.avatarUrl)),
                const SizedBox(height: 16),
                Text(
                  user.fullName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      information(
                        Icons.alternate_email,
                        'Nombre de usuario',
                        user.username == null ? null : '@${user.username}',
                      ),
                      information(
                        Icons.mail_outline,
                        'Correo electrónico',
                        user.email,
                      ),
                      information(Icons.phone_outlined, 'Teléfono', user.phone),
                      information(
                        Icons.badge_outlined,
                        'CI/NIT',
                        user.identityDocument,
                      ),
                      information(
                        Icons.shield_outlined,
                        'Roles',
                        user.roles.isEmpty
                            ? 'Sin roles asignados'
                            : user.roles.map(_roleLabel).join(' · '),
                      ),
                      information(
                        Icons.calendar_today_outlined,
                        'Miembro desde',
                        _date(user.registeredAt),
                      ),
                      information(
                        Icons.update,
                        'Última actualización',
                        _date(user.updatedAt, withTime: true),
                      ),
                      information(
                        Icons.login,
                        'Último acceso',
                        _date(user.lastLoginAt, withTime: true),
                      ),
                    ],
                  ),
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
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: const Icon(Icons.person_outline, size: 52),
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
      child: ClipOval(child: SizedBox.square(dimension: 96, child: image)),
    );
  }
}
