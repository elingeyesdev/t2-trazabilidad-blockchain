import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/qr_envio_models.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/form_validation.dart';
import '../../widgets/record_status_badge.dart';
import '../../widgets/signature_pad.dart';
import 'module_access_denied.dart';

class EnvioQrDetailScreen extends StatefulWidget {
  const EnvioQrDetailScreen({
    super.key,
    required this.tipo,
    required this.envioId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.initialResolution,
  });

  final EnvioTipo tipo;
  final int envioId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final QrResolucionResult? initialResolution;

  @override
  State<EnvioQrDetailScreen> createState() => _EnvioQrDetailScreenState();
}

class _EnvioQrDetailScreenState extends State<EnvioQrDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<int, TextEditingController> _qtyControllers = {};
  final Map<int, TextEditingController> _motivoControllers = {};
  final _signatureController = SignaturePadController();

  EnvioResumen? _envio;
  bool _loading = true;
  String? _error;
  int? _errorStatus;

  TextEditingController _qtyControllerFor(EnvioLinea linea) =>
      _qtyControllers.putIfAbsent(linea.id, () {
        final normalized = linea.cantidadEnviada.trim().replaceAll(',', '.');
        final clean = normalized.contains('.')
            ? normalized.replaceFirst(RegExp(r'\.?0+$'), '')
            : normalized;
        return TextEditingController(text: clean);
      });

  TextEditingController _motivoControllerFor(EnvioLinea linea) =>
      _motivoControllers.putIfAbsent(linea.id, TextEditingController.new);

  @override
  void dispose() {
    _signatureController.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    for (final c in _motivoControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!QrPermissions.canUseQr(widget.user)) {
      _loading = false;
      _errorStatus = 403;
      return;
    }
    final initial = widget.initialResolution;
    if (initial != null &&
        initial.envio.id == widget.envioId &&
        initial.envio.tipo == widget.tipo) {
      _envio = initial.envio;
      _loading = false;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = null;
    });
    try {
      final result = await widget.service.loadEnvioMovilDetail(
        widget.user,
        tipo: widget.tipo,
        id: widget.envioId,
      );
      if (!mounted) return;
      setState(() {
        _envio = result;
        _loading = false;
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
        _error = 'No se pudo consultar el envío.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!QrPermissions.canUseQr(widget.user) ||
        (!_loading && _errorStatus == 403)) {
      return ModuleAccessDenied(
        title: 'Consulta de envío',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    final resolution = widget.initialResolution;
    final isRecepcionMode =
        resolution != null &&
        !resolution.utilizado &&
        resolution.puedeConfirmar;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isRecepcionMode ? 'Recepción de envío' : 'Consulta de envío',
        ),
        actions: [
          IconButton(
            key: const ValueKey('envio_qr.actualizar'),
            tooltip: 'Actualizar envío',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(message: 'Cargando envío...')
            : _errorStatus == 404
            ? const AppEmptyState(
                icon: Icons.search_off_rounded,
                tone: AppTheme.maizeSoft,
                ink: Color(0xFF5F4100),
                title: 'Envío no disponible',
                message:
                    'El envío no existe o tu cuenta no tiene acceso para consultarlo.',
              )
            : _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : _content(context, _envio!, isRecepcionMode),
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          key: const ValueKey('envio_qr.volver'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Volver'),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    EnvioResumen envio,
    bool isRecepcionMode,
  ) {
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
                    color: AppTheme.sprout,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppTheme.ink, width: 2),
                    boxShadow: AppTheme.stamp(5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        envio.tipo.label,
                        style: const TextStyle(
                          color: AppTheme.forest,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        envio.referencia,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      RecordStatusBadge(status: envio.estadoLabel),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppNotice(
                  tone: isRecepcionMode
                      ? AppNoticeTone.success
                      : AppNoticeTone.info,
                  message: isRecepcionMode
                      ? 'Código QR validado para recepción. Revisa los destinos y productos del envío.'
                      : 'Vista de consulta del envío asociado al código QR.',
                ),
                const SizedBox(height: 24),
                const SectionTitle('Destinos y fechas'),
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
                        label: 'Destinos',
                        value: envio.destinos.isEmpty
                            ? 'Sin destino registrado'
                            : envio.destinos.map((d) => d.label).join('\n'),
                      ),
                      if (envio.fechaSalida != null) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: 'Fecha de salida',
                          value: envio.fechaSalida!,
                        ),
                      ],
                      if (envio.llegadaConfirmada != null) ...[
                        const Divider(height: 1),
                        DetailField(
                          label: 'Llegada confirmada',
                          value: envio.llegadaConfirmada!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SectionTitle(
                  isRecepcionMode
                      ? 'Cantidades recibidas'
                      : 'Productos del envío',
                ),
                const SizedBox(height: 12),
                if (isRecepcionMode)
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final linea in envio.lineas) ...[
                          _editableLineCard(context, envio.tipo, linea),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 12),
                        const SectionTitle('Firma de conformidad'),
                        const SizedBox(height: 12),
                        SignaturePad(controller: _signatureController),
                      ],
                    ),
                  )
                else
                  for (final linea in envio.lineas) ...[
                    Container(
                      key: ValueKey('envio_qr.linea.${linea.id}'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: AppTheme.ink, width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            linea.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          DetailField(
                            label: 'Cantidad enviada',
                            value: linea.formattedEnviada,
                          ),
                          if (linea.pedido != null) ...[
                            const Divider(height: 1),
                            DetailField(label: 'Pedido', value: linea.pedido!),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                if (envio.recepciones.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionTitle('Recepciones registradas'),
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
                        for (var i = 0; i < envio.recepciones.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          DetailField(
                            label: 'Recepción #${envio.recepciones[i].id}',
                            value:
                                envio.recepciones[i].fecha ??
                                'Registrada en el servidor',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editableLineCard(
    BuildContext context,
    EnvioTipo tipo,
    EnvioLinea linea,
  ) {
    final enviadaValue =
        double.tryParse(linea.cantidadEnviada.trim().replaceAll(',', '.')) ?? 0;
    final scrollPadding = formScrollPadding(context);

    return Container(
      key: ValueKey('envio_qr.linea.${linea.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(linea.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          DetailField(label: 'Cantidad enviada', value: linea.formattedEnviada),
          if (linea.pedido != null) ...[
            const Divider(height: 1),
            DetailField(label: 'Pedido', value: linea.pedido!),
          ],
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('recepcion_envio.cantidad.${linea.id}'),
            controller: _qtyControllerFor(linea),
            scrollPadding: scrollPadding,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Cantidad recibida',
              suffixText: linea.unidad,
              prefixIcon: const Icon(Icons.scale_outlined),
            ),
            validator: (value) => validateEnvioRecepcionQuantity(
              value,
              tipo: tipo,
              enviada: enviadaValue,
              unidad: linea.unidad,
            ),
          ),
          if (tipo == EnvioTipo.traslado) ...[
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('recepcion_envio.motivo.${linea.id}'),
              controller: _motivoControllerFor(linea),
              scrollPadding: scrollPadding,
              decoration: const InputDecoration(
                labelText: 'Motivo de diferencia (si aplica)',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
