import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/pedido_models.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/module_palette.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/form_validation.dart';
import 'module_access_denied.dart';

class PedidoFormScreen extends StatefulWidget {
  const PedidoFormScreen({
    super.key,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.onPedidoCreated,
  });

  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final VoidCallback? onPedidoCreated;

  @override
  State<PedidoFormScreen> createState() => _PedidoFormScreenState();
}

class _DraftLineControllers {
  _DraftLineControllers()
    : producto = TextEditingController(),
      presentacion = TextEditingController(),
      cantidad = TextEditingController(),
      partida = TextEditingController();

  final TextEditingController producto;
  final TextEditingController presentacion;
  final TextEditingController cantidad;
  final TextEditingController partida;

  void dispose() {
    producto.dispose();
    presentacion.dispose();
    cantidad.dispose();
    partida.dispose();
  }
}

class _PedidoFormScreenState extends State<PedidoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late PedidoTipo _tipo;
  final _destinoCtrl = TextEditingController();
  final _destinoLatCtrl = TextEditingController();
  final _destinoLngCtrl = TextEditingController();
  final _origenAlmacenCtrl = TextEditingController();
  final _fechaEntregaCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final List<_DraftLineControllers> _lines = [_DraftLineControllers()];

  bool _submitting = false;
  ApiException? _submitError;

  List<PedidoTipo> get _allowedTipos => [
    if (PedidoPermissions.canCreateDistribucion(widget.user))
      PedidoTipo.distribucion,
    if (PedidoPermissions.canCreateAgricola(widget.user)) PedidoTipo.agricola,
  ];

  @override
  void initState() {
    super.initState();
    final allowed = _allowedTipos;
    _tipo = allowed.isNotEmpty ? allowed.first : PedidoTipo.distribucion;
  }

  @override
  void dispose() {
    _destinoCtrl.dispose();
    _destinoLatCtrl.dispose();
    _destinoLngCtrl.dispose();
    _origenAlmacenCtrl.dispose();
    _fechaEntregaCtrl.dispose();
    _observacionesCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String? _fieldError(String field) {
    final messages = _submitError?.validationErrors[field];
    return messages == null || messages.isEmpty ? null : messages.join('\n');
  }

  void _clearError({String? field}) {
    final error = _submitError;
    if (error == null) return;
    if (field != null && error.validationErrors.isNotEmpty) {
      if (!error.validationErrors.containsKey(field)) return;
      final remaining = Map.of(error.validationErrors)..remove(field);
      setState(() {
        _submitError = remaining.isEmpty
            ? null
            : ApiException(
                error.message,
                statusCode: error.statusCode,
                validationErrors: remaining,
              );
      });
    } else {
      setState(() => _submitError = null);
    }
  }

  Map<String, dynamic> _buildPayload() {
    if (_tipo == PedidoTipo.distribucion) {
      final detalles = <Map<String, dynamic>>[];
      for (final line in _lines) {
        final partida = int.tryParse(line.partida.text.trim());
        detalles.add({
          'insumoid': int.parse(line.producto.text.trim()),
          'insumo_presentacionid': int.parse(line.presentacion.text.trim()),
          'cantidad': line.cantidad.text.trim().replaceAll(',', '.'),
          if (partida != null && partida > 0)
            'inventario_presentacion_loteid': partida,
        });
      }
      final almacenOrigen = int.tryParse(_origenAlmacenCtrl.text.trim());
      return {
        'puntoventaid': int.parse(_destinoCtrl.text.trim()),
        'fecha_entrega_deseada': _fechaEntregaCtrl.text.trim(),
        if (almacenOrigen != null && almacenOrigen > 0)
          'almacen_mayorista_origenid': almacenOrigen,
        if (_observacionesCtrl.text.trim().isNotEmpty)
          'observaciones': _observacionesCtrl.text.trim(),
        'detalles': detalles,
      };
    }

    final detalles = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final calibre = int.tryParse(line.presentacion.text.trim());
      final partida = int.tryParse(line.partida.text.trim());
      detalles.add({
        'producto_ref': line.producto.text.trim(),
        'cantidad': line.cantidad.text.trim().replaceAll(',', '.'),
        if (calibre != null && calibre > 0) 'catalogotamanoconteoid': calibre,
        if (partida != null && partida > 0) 'materiaprimaloteid': partida,
      });
    }
    final almacenOrigen = int.tryParse(_origenAlmacenCtrl.text.trim());
    return {
      if (almacenOrigen != null && almacenOrigen > 0)
        'origen_almacenid': almacenOrigen,
      'direccion_texto': _destinoCtrl.text.trim(),
      if (_destinoLatCtrl.text.trim().isNotEmpty)
        'latitud': _destinoLatCtrl.text.trim().replaceAll(',', '.'),
      if (_destinoLngCtrl.text.trim().isNotEmpty)
        'longitud': _destinoLngCtrl.text.trim().replaceAll(',', '.'),
      'fechaEntregaDeseada': _fechaEntregaCtrl.text.trim(),
      if (_observacionesCtrl.text.trim().isNotEmpty)
        'observaciones': _observacionesCtrl.text.trim(),
      'detalles': detalles,
    };
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!validateForm(_formKey)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final created = await widget.service.createPedidoMovil(
        widget.user,
        tipo: _tipo,
        body: _buildPayload(),
      );
      if (!mounted) return;
      widget.onPedidoCreated?.call();
      Navigator.of(context).pushReplacementNamed(
        '${AppModule.pedidos.route}/${created.tipo.value}/${created.id}',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error;
      });
      revealFormErrors(_formKey);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = const ApiException(
          'No se pudo registrar el pedido. Tus datos se conservaron para reintentar.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PedidoPermissions.canCreateAny(widget.user)) {
      return ModuleAccessDenied(
        title: 'Nuevo pedido',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    final look = AppModule.pedidos.look;
    final allowed = _allowedTipos;
    final scrollPadding = formScrollPadding(context);
    final isDist = _tipo == PedidoTipo.distribucion;
    final generalError = _submitError?.message;
    final detallesError = _fieldError('detalles');

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo pedido')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (allowed.length > 1) ...[
                      SectionTitle('Tipo de pedido', color: look.tone),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final tipo in allowed)
                            ChoiceChip(
                              key: ValueKey('pedido.form.tipo.${tipo.value}'),
                              label: Text(tipo.label),
                              selected: _tipo == tipo,
                              selectedColor: AppTheme.maize,
                              backgroundColor: AppTheme.surface,
                              side: const BorderSide(
                                color: AppTheme.ink,
                                width: 1.5,
                              ),
                              onSelected: _submitting
                                  ? null
                                  : (_) => setState(() {
                                      _tipo = tipo;
                                      _submitError = null;
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    SectionTitle('Destino y entrega', color: look.tone),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('pedido.destino'),
                      controller: _destinoCtrl,
                      scrollPadding: scrollPadding,
                      enabled: !_submitting,
                      keyboardType: isDist
                          ? TextInputType.number
                          : TextInputType.text,
                      forceErrorText: _fieldError(
                        isDist ? 'puntoventaid' : 'direccion_texto',
                      ),
                      decoration: InputDecoration(
                        labelText: isDist
                            ? 'Punto de venta destino (ID)'
                            : 'Dirección de destino',
                        prefixIcon: const Icon(Icons.place_outlined),
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) {
                          return isDist
                              ? 'Indica el punto de venta destino.'
                              : 'Indica la dirección de destino.';
                        }
                        if (isDist && (int.tryParse(text) ?? 0) <= 0) {
                          return 'Indica un ID de punto de venta válido.';
                        }
                        return null;
                      },
                      onChanged: (_) => _clearError(
                        field: isDist ? 'puntoventaid' : 'direccion_texto',
                      ),
                    ),
                    if (!isDist) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const ValueKey('pedido.destino_lat'),
                              controller: _destinoLatCtrl,
                              scrollPadding: scrollPadding,
                              enabled: !_submitting,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Latitud destino',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              key: const ValueKey('pedido.destino_lng'),
                              controller: _destinoLngCtrl,
                              scrollPadding: scrollPadding,
                              enabled: !_submitting,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Longitud destino',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('pedido.fecha_entrega'),
                      controller: _fechaEntregaCtrl,
                      scrollPadding: scrollPadding,
                      enabled: !_submitting,
                      forceErrorText: _fieldError(
                        isDist
                            ? 'fecha_entrega_deseada'
                            : 'fechaEntregaDeseada',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Fecha de entrega deseada (AAAA-MM-DD)',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) {
                          return 'Indica la fecha de entrega deseada.';
                        }
                        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
                          return 'Usa el formato AAAA-MM-DD.';
                        }
                        return null;
                      },
                      onChanged: (_) => _clearError(
                        field: isDist
                            ? 'fecha_entrega_deseada'
                            : 'fechaEntregaDeseada',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('pedido.almacen_origen'),
                      controller: _origenAlmacenCtrl,
                      scrollPadding: scrollPadding,
                      enabled: !_submitting,
                      keyboardType: TextInputType.number,
                      forceErrorText: _fieldError(
                        isDist
                            ? 'almacen_mayorista_origenid'
                            : 'origen_almacenid',
                      ),
                      decoration: InputDecoration(
                        labelText: isDist
                            ? 'Almacén mayorista origen (ID opcional)'
                            : 'Almacén origen (ID opcional)',
                        prefixIcon: const Icon(Icons.warehouse_outlined),
                      ),
                      onChanged: (_) => _clearError(
                        field: isDist
                            ? 'almacen_mayorista_origenid'
                            : 'origen_almacenid',
                      ),
                    ),
                    const SizedBox(height: 24),
                    SectionTitle(
                      'Productos, presentaciones y cantidades',
                      color: look.tone,
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _lines.length; i++) ...[
                      _lineCard(i, isDist, scrollPadding),
                      const SizedBox(height: 12),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const ValueKey('pedido.agregar_linea'),
                        onPressed: _submitting
                            ? null
                            : () => setState(
                                () => _lines.add(_DraftLineControllers()),
                              ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Agregar producto'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('pedido.observaciones'),
                      controller: _observacionesCtrl,
                      scrollPadding: scrollPadding,
                      enabled: !_submitting,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones (opcional)',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                    if (detallesError != null) ...[
                      const SizedBox(height: 14),
                      AppNotice(
                        tone: AppNoticeTone.error,
                        message: detallesError,
                      ),
                    ] else if (generalError != null) ...[
                      const SizedBox(height: 14),
                      AppNotice(
                        tone: AppNoticeTone.error,
                        message: generalError,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const ValueKey('pedido.guardar'),
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _submitting ? 'Guardando pedido...' : 'Crear pedido',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lineCard(int index, bool isDist, EdgeInsets scrollPadding) {
    final line = _lines[index];
    return Container(
      key: ValueKey('pedido.linea.$index'),
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
              Text(
                'Producto #${index + 1}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (_lines.length > 1)
                IconButton(
                  tooltip: 'Quitar producto',
                  onPressed: _submitting
                      ? null
                      : () {
                          final removed = _lines.removeAt(index);
                          removed.dispose();
                          setState(() {});
                        },
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('pedido.linea.$index.producto'),
            controller: line.producto,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            keyboardType: isDist ? TextInputType.number : TextInputType.text,
            forceErrorText: _fieldError(
              isDist
                  ? 'detalles.$index.insumoid'
                  : 'detalles.$index.producto_ref',
            ),
            decoration: InputDecoration(
              labelText: isDist
                  ? 'Producto (ID de insumo)'
                  : 'Referencia de producto (ej. cosecha:12)',
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'Indica el producto.';
              if (isDist && (int.tryParse(text) ?? 0) <= 0) {
                return 'Indica un ID de producto válido.';
              }
              return null;
            },
            onChanged: (_) => _clearError(
              field: isDist
                  ? 'detalles.$index.insumoid'
                  : 'detalles.$index.producto_ref',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('pedido.linea.$index.presentacion'),
            controller: line.presentacion,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            forceErrorText: _fieldError(
              isDist
                  ? 'detalles.$index.insumo_presentacionid'
                  : 'detalles.$index.catalogotamanoconteoid',
            ),
            decoration: InputDecoration(
              labelText: isDist
                  ? 'Presentación (ID)'
                  : 'Presentación / calibre (ID opcional)',
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (isDist && text.isEmpty) {
                return 'Selecciona la presentación.';
              }
              if (text.isNotEmpty && (int.tryParse(text) ?? 0) <= 0) {
                return 'Indica un ID de presentación válido.';
              }
              return null;
            },
            onChanged: (_) => _clearError(
              field: isDist
                  ? 'detalles.$index.insumo_presentacionid'
                  : 'detalles.$index.catalogotamanoconteoid',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('pedido.linea.$index.cantidad'),
            controller: line.cantidad,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            forceErrorText: _fieldError('detalles.$index.cantidad'),
            decoration: InputDecoration(
              labelText: isDist ? 'Cantidad (envases)' : 'Cantidad (kg)',
              suffixText: isDist ? 'env.' : 'kg',
            ),
            validator: (value) => validatePedidoQuantity(
              value,
              unitLabel: isDist ? 'envases' : 'kg',
            ),
            onChanged: (_) => _clearError(field: 'detalles.$index.cantidad'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('pedido.linea.$index.partida'),
            controller: line.partida,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            forceErrorText: _fieldError(
              isDist
                  ? 'detalles.$index.inventario_presentacion_loteid'
                  : 'detalles.$index.materiaprimaloteid',
            ),
            decoration: const InputDecoration(
              labelText: 'Partida (ID opcional)',
            ),
            onChanged: (_) => _clearError(
              field: isDist
                  ? 'detalles.$index.inventario_presentacion_loteid'
                  : 'detalles.$index.materiaprimaloteid',
            ),
          ),
        ],
      ),
    );
  }
}
