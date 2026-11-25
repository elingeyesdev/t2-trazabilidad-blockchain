import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/usuario_admin_models.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/record_status_badge.dart';
import 'module_access_denied.dart';

class UsuarioDetailScreen extends StatefulWidget {
  const UsuarioDetailScreen({
    super.key,
    required this.usuarioId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.onUsuarioUpdated,
  });

  final int usuarioId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final VoidCallback? onUsuarioUpdated;

  @override
  State<UsuarioDetailScreen> createState() => _UsuarioDetailScreenState();
}

class _UsuarioDetailScreenState extends State<UsuarioDetailScreen> {
  static const _flotas = <(String, String)>[
    ('agricola', 'Flota agrícola'),
    ('planta', 'Flota de planta'),
    ('mayorista', 'Flota mayorista'),
  ];

  UsuarioAdminRecord? _record;
  bool _loading = true;
  bool _acting = false;
  String? _ambitoFlota;
  String? _error;
  int? _errorStatus;
  String? _actionError;
  String? _notice;

  bool get _canAdmin => widget.user.permissions.contains('usuarios.admin');

  @override
  void initState() {
    super.initState();
    if (_canAdmin) {
      unawaited(_load());
    } else {
      _loading = false;
      _errorStatus = 403;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = null;
    });
    try {
      final result = await widget.service.loadUsuarioAdminDetail(
        widget.user,
        widget.usuarioId,
      );
      if (!mounted) return;
      setState(() {
        _record = result;
        _loading = false;
        _actionError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
        _errorStatus = error.statusCode;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo consultar el detalle del usuario.';
      });
    }
  }

  Future<void> _aprobar(UsuarioAdminRecord record) async {
    if (_acting) return;
    if (record.rolEfectivo == 'transportista' && _ambitoFlota == null) {
      setState(() {
        _actionError =
            'Selecciona la flota del transportista antes de aprobar.';
      });
      return;
    }

    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.how_to_reg_rounded,
      title: '¿Aprobar solicitud de registro?',
      message: 'El usuario podrá iniciar sesión con el rol asignado.',
      details: [
        'Nombre: ${record.nombreCompleto}',
        'Correo: ${record.email}',
        'Rol: ${record.rolLabel}',
      ],
      cancelLabel: 'Cancelar',
      confirmLabel: 'Aprobar solicitud',
    );
    if (!mounted || !confirmed) return;

    setState(() {
      _acting = true;
      _actionError = null;
      _notice = null;
    });
    try {
      final updated = await widget.service.aprobarUsuarioAdmin(
        widget.user,
        record.id,
        ambitoFlota: _ambitoFlota,
      );
      if (!mounted) return;
      widget.onUsuarioUpdated?.call();
      setState(() {
        _record = updated;
        _acting = false;
        _notice = 'Solicitud de ${updated.nombreCompleto} aprobada.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _actionError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _actionError = 'No se pudo aprobar la solicitud por un error de red.';
      });
    }
  }

  Future<void> _rechazar(UsuarioAdminRecord record) async {
    if (_acting) return;
    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.person_remove_outlined,
      title: '¿Rechazar esta solicitud?',
      message:
          'La solicitud pendiente se rechazará y se eliminará del sistema.',
      details: ['Nombre: ${record.nombreCompleto}', 'Correo: ${record.email}'],
      cancelLabel: 'Cancelar',
      confirmLabel: 'Rechazar solicitud',
    );
    if (!mounted || !confirmed) return;

    setState(() {
      _acting = true;
      _actionError = null;
      _notice = null;
    });
    try {
      await widget.service.rechazarUsuarioAdmin(widget.user, record.id);
      if (!mounted) return;
      widget.onUsuarioUpdated?.call();
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _actionError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _actionError = 'No se pudo rechazar la solicitud por un error de red.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAdmin || (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Detalle de usuario',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de usuario'),
        actions: [
          IconButton(
            key: const ValueKey('usuario.actualizar'),
            tooltip: 'Actualizar usuario',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(
                message: 'Cargando usuario...',
                shape: LoadingShape.detail,
              )
            : _errorStatus == 404
            ? const AppEmptyState(
                icon: Icons.person_off_outlined,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Usuario no encontrado',
                message:
                    'Es posible que esta solicitud ya haya sido eliminada.',
              )
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _content(context, _record!),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver a usuarios'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, UsuarioAdminRecord record) {
    final look = AppModule.usuarios.look;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: look.tone,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppTheme.ink, width: 2),
                    boxShadow: AppTheme.stamp(5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.rolLabel,
                        style: TextStyle(
                          color: look.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        record.nombreCompleto,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      RecordStatusBadge(
                        key: const ValueKey('usuario.estado_badge'),
                        status: record.estadoLabel,
                      ),
                    ],
                  ),
                ),
                if (_notice case final notice?) ...[
                  const SizedBox(height: 16),
                  AppNotice(tone: AppNoticeTone.success, message: notice),
                ],
                if (_actionError case final actionError?) ...[
                  const SizedBox(height: 16),
                  AppNotice(tone: AppNoticeTone.error, message: actionError),
                ],
                const SizedBox(height: 24),
                SectionTitle(
                  record.isPending
                      ? 'Datos de la solicitud'
                      : 'Datos de la cuenta',
                  color: look.tone,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.ink, width: 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DetailField(
                        label: record.isPending ? 'Rol solicitado' : 'Rol',
                        value: record.rolLabel,
                      ),
                      if (record.nombreUsuario != null) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: 'Usuario',
                          value: '@${record.nombreUsuario}',
                        ),
                      ],
                      const Divider(height: 1),
                      DetailField(label: 'Correo', value: record.email),
                      const Divider(height: 1),
                      DetailField(
                        label: 'Teléfono',
                        value: record.telefono ?? 'No registrado',
                      ),
                      if (record.ciNit != null) ...[
                        const Divider(height: 1),
                        DetailField(label: 'CI/NIT', value: record.ciNit!),
                      ],
                      if (record.tipoLicencia != null) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: 'Tipo de licencia',
                          value: record.tipoLicencia!,
                        ),
                      ],
                      if (record.informacionAdicional != null) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: 'Información adicional',
                          value: record.informacionAdicional!,
                        ),
                      ],
                      if (record.cartaMotivacion != null) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: 'Carta de motivación',
                          value: record.cartaMotivacion!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (record.isPending) ...[
                  const SizedBox(height: 24),
                  SectionTitle('Resolución de solicitud', color: look.tone),
                  const SizedBox(height: 12),
                  if (record.rolEfectivo == 'transportista') ...[
                    DropdownButtonFormField<String>(
                      key: const ValueKey('usuario.ambito_flota'),
                      initialValue: _ambitoFlota,
                      decoration: const InputDecoration(
                        labelText: 'Flota del transportista',
                      ),
                      items: [
                        for (final (value, label) in _flotas)
                          DropdownMenuItem(value: value, child: Text(label)),
                      ],
                      onChanged: _acting
                          ? null
                          : (value) => setState(() => _ambitoFlota = value),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('usuario.aprobar'),
                          onPressed: _acting ? null : () => _aprobar(record),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Aprobar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('usuario.rechazar'),
                          onPressed: _acting ? null : () => _rechazar(record),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Rechazar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
