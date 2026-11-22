import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/inventario_models.dart';
import '../../models/pedido_models.dart';
import '../../models/qr_envio_models.dart';
import '../../navigation/app_module.dart';
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
    this.signatureExporter,
    this.onRecepcionConfirmed,
  });

  final EnvioTipo tipo;
  final int envioId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final QrResolucionResult? initialResolution;
  final Future<String?> Function()? signatureExporter;
  final VoidCallback? onRecepcionConfirmed;

  @override
  State<EnvioQrDetailScreen> createState() => _EnvioQrDetailScreenState();
}

class _EnvioQrDetailScreenState extends State<EnvioQrDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<int, TextEditingController> _qtyControllers = {};
  final Map<int, TextEditingController> _motivoControllers = {};
  final _signatureController = SignaturePadController();

  EnvioResumen? _envio;
  RecepcionEnvioComprobante? _comprobante;
  List<PedidoRecord> _updatedPedidos = const [];
  List<(String almacenNombre, AlmacenExistencia item)> _updatedExistencias =
      const [];
  bool _alreadyUsed = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  int? _errorStatus;
  String? _submitError;
  String? _signatureError;
  String? _notice;

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
      _alreadyUsed = initial.utilizado;
      _loading = false;
      if (initial.utilizado && initial.recepcionId > 0) {
        unawaited(_loadComprobante(initial.recepcionId));
      }
    } else {
      unawaited(_load());
    }
  }

  Future<void> _loadComprobante(int recepcionId) async {
    try {
      final result = await widget.service.loadRecepcionEnvioComprobante(
        widget.user,
        recepcionId,
      );
      if (!mounted) return;
      setState(() => _comprobante = result);
    } catch (_) {
      // Si el comprobante aún no está disponible, se mantiene el detalle del envío.
    }
  }

  Future<void> _refreshRelatedPedidos(EnvioResumen envio) async {
    if (envio.tipo == EnvioTipo.traslado) return;
    final pedidoTipo = envio.tipo == EnvioTipo.agricola
        ? PedidoTipo.agricola
        : PedidoTipo.distribucion;
    final canViewPedido = pedidoTipo == PedidoTipo.agricola
        ? PedidoPermissions.canViewAgricola(widget.user)
        : PedidoPermissions.canViewDistribucion(widget.user);
    if (!canViewPedido) return;

    final ids = envio.lineas
        .map((l) => l.pedidoId)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    if (ids.isEmpty) return;

    final loaded = <PedidoRecord>[];
    for (final pedidoId in ids) {
      try {
        final pedido = await widget.service.loadPedidoMovilDetail(
          widget.user,
          tipo: pedidoTipo,
          id: pedidoId,
        );
        loaded.add(pedido);
      } catch (_) {
        // Ignora pedidos no accesibles individualmente sin romper el comprobante.
      }
    }
    if (!mounted) return;
    setState(() => _updatedPedidos = loaded);
  }

  Future<void> _refreshAffectedExistencias(EnvioResumen envio) async {
    if (!InventarioPermissions.canViewExistencias(widget.user)) return;
    try {
      final almacenes = await widget.service.loadAuthorizedAlmacenes(
        widget.user,
      );
      if (almacenes.isEmpty) return;

      final destinoIds = envio.destinos
          .map((d) => d.id)
          .whereType<int>()
          .toSet();
      final targets = almacenes
          .where((a) => destinoIds.contains(a.id))
          .toList();
      final selected = targets.isNotEmpty
          ? targets
          : almacenes.take(3).toList();
      final productNames = envio.lineas
          .map((l) => l.producto.trim().toLowerCase())
          .toSet();

      final results = <(String, AlmacenExistencia)>[];
      for (final almacen in selected) {
        try {
          final page = await widget.service.loadAlmacenExistencias(
            widget.user,
            almacen.id,
          );
          final matched = page.items
              .where(
                (item) =>
                    productNames.isEmpty ||
                    productNames.contains(item.nombre.trim().toLowerCase()),
              )
              .toList();
          final toAdd = matched.isNotEmpty ? matched : page.items.take(3);
          for (final item in toAdd) {
            results.add((almacen.name, item));
          }
        } catch (_) {
          // Ignora almacenes sin existencias accesibles.
        }
      }
      if (!mounted) return;
      setState(() => _updatedExistencias = results);
    } catch (_) {
      // No interrumpe el comprobante si no se pudo consultar existencias.
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
      final comprobanteId =
          _comprobante?.id ??
          (widget.initialResolution?.utilizado == true
              ? widget.initialResolution?.recepcionId
              : null);
      if (comprobanteId != null && comprobanteId > 0) {
        unawaited(_loadComprobante(comprobanteId));
        unawaited(_refreshRelatedPedidos(result));
        unawaited(_refreshAffectedExistencias(result));
      }
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

  Future<void> _confirmarRecepcion(
    EnvioResumen envio,
    QrResolucionResult resolution,
  ) async {
    if (_submitting || _comprobante != null) return;
    final validForm = validateForm(_formKey);
    if (!_signatureController.hasSignature) {
      setState(() {
        _signatureError = 'Añade tu firma antes de confirmar la recepción.';
      });
      return;
    }
    if (!validForm) return;

    final lineasPayload = <Map<String, dynamic>>[];
    final summary = <String>['Envío: ${envio.referencia}'];
    for (final linea in envio.lineas) {
      final qty = _qtyControllerFor(linea).text.trim().replaceAll(',', '.');
      final motivo = _motivoControllerFor(linea).text.trim();
      lineasPayload.add({
        'id': linea.id,
        'cantidad_recibida': qty,
        if (envio.tipo == EnvioTipo.traslado && motivo.isNotEmpty)
          'motivo': motivo,
      });
      summary.add('${linea.title}: $qty ${linea.unidad}');
    }
    summary.add('Firma de conformidad adjunta');

    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.fact_check_rounded,
      title: '¿Confirmar recepción con firma?',
      message:
          'Se registrará la recepción definitiva y se consumirá el código QR.',
      details: summary,
      cancelLabel: 'Revisar datos',
      confirmLabel: 'Confirmar recepción',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
      _signatureError = null;
      _notice = null;
    });

    try {
      final exporter =
          widget.signatureExporter ?? _signatureController.exportPngDataUrl;
      final dataUrl = await exporter();
      if (dataUrl == null) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _signatureError = 'No se pudo generar la imagen de la firma.';
        });
        return;
      }
      final comprobante = await widget.service.confirmarRecepcionEnvio(
        widget.user,
        tipo: envio.tipo,
        envioId: envio.id,
        codigo: resolution.codigo,
        imagenFirma: dataUrl,
        lineas: lineasPayload,
      );
      if (!mounted) return;
      widget.onRecepcionConfirmed?.call();
      setState(() {
        _submitting = false;
        _comprobante = comprobante;
        _notice = 'Recepción #${comprobante.id} registrada correctamente.';
      });
      await _refreshRelatedPedidos(envio);
      await _refreshAffectedExistencias(envio);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409) {
        setState(() {
          _submitting = false;
          _alreadyUsed = true;
          _submitError = null;
        });
        if (resolution.recepcionId > 0) {
          unawaited(_loadComprobante(resolution.recepcionId));
        }
        return;
      }
      final recepcionErrors = error.validationErrors['recepcion'];
      final message = (recepcionErrors != null && recepcionErrors.isNotEmpty)
          ? recepcionErrors.join('\n')
          : error.message;
      setState(() {
        _submitting = false;
        _submitError = message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError =
            'No se pudo confirmar la recepción por un error de conexión. Tus cantidades y firma se conservaron para reintentar.';
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
        _comprobante == null &&
        !_alreadyUsed &&
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
                if (_alreadyUsed) ...[
                  const AppNotice(
                    key: ValueKey('recepcion_envio.ya_utilizado'),
                    tone: AppNoticeTone.warning,
                    message:
                        'Este código QR ya fue utilizado. Se muestra el resultado registrado y no es posible duplicar la recepción.',
                  ),
                  const SizedBox(height: 12),
                ] else if (_notice case final notice?) ...[
                  AppNotice(tone: AppNoticeTone.success, message: notice),
                  const SizedBox(height: 12),
                ] else
                  AppNotice(
                    tone: isRecepcionMode
                        ? AppNoticeTone.success
                        : AppNoticeTone.info,
                    message: isRecepcionMode
                        ? 'Código QR validado para recepción. Revisa los destinos y productos del envío.'
                        : 'Vista de consulta del envío asociado al código QR.',
                  ),
                if (_comprobante case final comprobante?) ...[
                  const SizedBox(height: 20),
                  const SectionTitle('Comprobante de recepción'),
                  const SizedBox(height: 12),
                  _comprobanteCard(context, comprobante),
                ],
                if (_updatedPedidos.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionTitle('Estado actualizado del pedido'),
                  const SizedBox(height: 12),
                  for (final pedido in _updatedPedidos) ...[
                    _updatedPedidoCard(context, pedido),
                    const SizedBox(height: 10),
                  ],
                ],
                if (_updatedExistencias.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionTitle('Existencias actualizadas'),
                  const SizedBox(height: 12),
                  Container(
                    key: const ValueKey('recepcion_envio.existencias'),
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
                        for (
                          var i = 0;
                          i < _updatedExistencias.length;
                          i++
                        ) ...[
                          if (i > 0) const Divider(height: 1),
                          DetailField(
                            label:
                                '${_updatedExistencias[i].$2.nombre} · ${_updatedExistencias[i].$1}',
                            value:
                                'Disponible: ${_updatedExistencias[i].$2.formattedDisponible}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
                        SignaturePad(
                          controller: _signatureController,
                          enabled: !_submitting,
                        ),
                        if (_signatureError case final sigError?) ...[
                          const SizedBox(height: 10),
                          AppNotice(
                            tone: AppNoticeTone.error,
                            message: sigError,
                          ),
                        ],
                        if (_submitError case final subError?) ...[
                          const SizedBox(height: 12),
                          AppNotice(
                            key: const ValueKey('recepcion_envio.submit_error'),
                            tone: AppNoticeTone.error,
                            message: subError,
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          key: const ValueKey('recepcion_envio.confirmar'),
                          onPressed: _submitting
                              ? null
                              : () => _confirmarRecepcion(
                                  envio,
                                  widget.initialResolution!,
                                ),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.fact_check_rounded),
                          label: Text(
                            _submitting
                                ? 'Confirmando recepción...'
                                : 'Registrar recepción con firma',
                          ),
                        ),
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
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: DetailField(
                                    label:
                                        'Recepción #${envio.recepciones[i].id}',
                                    value:
                                        envio.recepciones[i].fecha ??
                                        'Registrada en el servidor',
                                  ),
                                ),
                                TextButton.icon(
                                  key: ValueKey(
                                    'envio_qr.ver_comprobante.${envio.recepciones[i].id}',
                                  ),
                                  onPressed: () => unawaited(
                                    _loadComprobante(envio.recepciones[i].id),
                                  ),
                                  icon: const Icon(
                                    Icons.receipt_long_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Ver comprobante'),
                                ),
                              ],
                            ),
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

  Widget _comprobanteCard(
    BuildContext context,
    RecepcionEnvioComprobante comprobante,
  ) {
    return Container(
      key: const ValueKey('recepcion_envio.comprobante'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailField(
            label: 'Comprobante',
            value: 'Recepción #${comprobante.id}',
          ),
          if (comprobante.firmanteNombre != null) ...[
            const Divider(height: 1),
            DetailField(label: 'Firmante', value: comprobante.firmanteNombre!),
          ],
          if (comprobante.fecha != null) ...[
            const Divider(height: 1),
            DetailField(
              label: 'Fecha de confirmación',
              value: comprobante.fecha!,
            ),
          ],
          if (comprobante.firmaUrl != null) ...[
            const Divider(height: 1),
            const DetailField(
              label: 'Firma digitalizada',
              value: 'Registrada y verificada',
            ),
          ],
          if (comprobante.comprobanteUrl != null) ...[
            const Divider(height: 1),
            const DetailField(
              label: 'Comprobante oficial',
              value: 'Disponible en el servidor',
            ),
          ],
          for (final linea in comprobante.lineas) ...[
            const Divider(height: 1),
            DetailField(
              label: linea.producto,
              value:
                  'Recibido: ${linea.formattedRecibida} (enviado: ${linea.formattedEnviada})',
            ),
          ],
        ],
      ),
    );
  }

  Widget _updatedPedidoCard(BuildContext context, PedidoRecord pedido) {
    return Container(
      key: ValueKey('recepcion_envio.pedido_actualizado.${pedido.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pedido.numeroSolicitud,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              RecordStatusBadge(status: pedido.estadoLabel),
            ],
          ),
          if (pedido.fechaRecepcion != null) ...[
            const SizedBox(height: 8),
            DetailField(
              label: 'Fecha de recepción',
              value: pedido.fechaRecepcion!,
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: ValueKey('recepcion_envio.ver_pedido.${pedido.id}'),
              onPressed: () => Navigator.of(context).pushNamed(
                '${AppModule.pedidos.route}/${pedido.tipo.value}/${pedido.id}',
              ),
              icon: const Icon(Icons.history_rounded),
              label: const Text('Ver historial del pedido'),
            ),
          ),
        ],
      ),
    );
  }
}
