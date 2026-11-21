import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/inventario_models.dart';
import '../../services/module_service.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/form_validation.dart';
import 'module_access_denied.dart';

class MovimientoFormResult {
  const MovimientoFormResult({required this.movimiento});

  final InventarioMovimientoRecord movimiento;
}

class InventarioMovimientoFormScreen extends StatefulWidget {
  const InventarioMovimientoFormScreen({
    super.key,
    required this.almacenId,
    required this.almacenName,
    required this.mode,
    required this.existencias,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.initialInsumoId,
  });

  final int almacenId;
  final String almacenName;
  final MovimientoFormMode mode;
  final List<AlmacenExistencia> existencias;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final int? initialInsumoId;

  @override
  State<InventarioMovimientoFormScreen> createState() =>
      _InventarioMovimientoFormScreenState();
}

class _InventarioMovimientoFormScreenState
    extends State<InventarioMovimientoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();
  final _fechaController = TextEditingController(text: _todayIso());
  final _motivoController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _obsController = TextEditingController();

  late final List<MovimientoTipoOption> _tipos = MovimientoTipoOption.forMode(
    widget.mode,
    allowIngreso: InventarioPermissions.canRegisterIngreso(widget.user),
    allowSalida: InventarioPermissions.canRegisterSalida(widget.user),
  );

  int? _tipoId;
  int? _insumoId;
  String? _partidaKey;
  bool _submitting = false;
  ApiException? _submitError;

  static String _todayIso() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  bool get _canOpen => switch (widget.mode) {
    MovimientoFormMode.ingreso => InventarioPermissions.canRegisterIngreso(
      widget.user,
    ),
    MovimientoFormMode.salida => InventarioPermissions.canRegisterSalida(
      widget.user,
    ),
    MovimientoFormMode.ajuste => InventarioPermissions.canRegisterAjuste(
      widget.user,
    ),
  };

  String get _title => switch (widget.mode) {
    MovimientoFormMode.ingreso => 'Registrar entrada',
    MovimientoFormMode.salida => 'Registrar salida',
    MovimientoFormMode.ajuste => 'Registrar ajuste',
  };

  MovimientoTipoOption? get _selectedTipo {
    for (final item in _tipos) {
      if (item.id == _tipoId) return item;
    }
    return null;
  }

  AlmacenExistencia? get _selectedInsumo {
    for (final item in widget.existencias) {
      if (item.insumoId == _insumoId) return item;
    }
    return null;
  }

  bool get _isSalida => _selectedTipo?.isSalida ?? false;
  bool get _isAjuste =>
      widget.mode == MovimientoFormMode.ajuste ||
      (_selectedTipo?.isAjuste ?? false);

  @override
  void initState() {
    super.initState();
    _tipoId = _tipos.firstOrNull?.id;
    _insumoId =
        widget.initialInsumoId ??
        (widget.existencias.length == 1
            ? widget.existencias.first.insumoId
            : null);
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _fechaController.dispose();
    _motivoController.dispose();
    _referenciaController.dispose();
    _obsController.dispose();
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

  bool get _hasUnsavedChanges =>
      _cantidadController.text.trim().isNotEmpty ||
      _motivoController.text.trim().isNotEmpty ||
      _referenciaController.text.trim().isNotEmpty ||
      _obsController.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    if (_submitting) return;
    final now = DateTime.now();
    final initial = DateTime.tryParse(_fechaController.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (!mounted || picked == null) return;
    final month = picked.month.toString().padLeft(2, '0');
    final day = picked.day.toString().padLeft(2, '0');
    setState(() {
      _fechaController.text = '${picked.year}-$month-$day';
    });
    _clearError(field: 'fecha');
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    if (_hasUnsavedChanges) {
      final discard = await confirmImportantAction(
        context,
        icon: Icons.warning_amber_rounded,
        title: '¿Descartar movimiento?',
        message:
            'Tienes datos sin enviar. Si sales ahora, no se modificará el inventario.',
        cancelLabel: 'Seguir editando',
        confirmLabel: 'Descartar',
        destructive: true,
      );
      if (!mounted || !discard) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_submitting || !validateForm(_formKey)) return;
    final tipo = _selectedTipo;
    final insumo = _selectedInsumo;
    if (tipo == null || insumo == null) return;

    final cantidad = _cantidadController.text.trim().replaceAll(',', '.');
    final fecha = _fechaController.text.trim();
    final motivo = _motivoController.text.trim();
    final referencia = _referenciaController.text.trim();
    final obs = _obsController.text.trim();

    final confirmed = await confirmImportantAction(
      context,
      icon: _isSalida
          ? Icons.outbox_rounded
          : (_isAjuste ? Icons.tune_rounded : Icons.move_to_inbox_rounded),
      title: '¿Confirmar ${tipo.name.toLowerCase()}?',
      message:
          'Se actualizarán las existencias del almacén "${widget.almacenName}" y quedará registrado en el historial.',
      details: [
        'Almacén: ${widget.almacenName}',
        'Tipo: ${tipo.name}',
        'Producto: ${insumo.nombre}',
        'Cantidad: $cantidad ${insumo.unidad}',
        'Fecha: $fecha',
        if (motivo.isNotEmpty) 'Motivo: $motivo',
      ],
      confirmLabel: 'Confirmar movimiento',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final created = await widget.service.registerAlmacenMovimiento(
        widget.user,
        naturaleza: tipo.naturaleza,
        almacenId: widget.almacenId,
        insumoId: insumo.insumoId,
        tipoMovimientoId: tipo.id,
        fecha: fecha,
        cantidad: cantidad,
        destinoMotivo: motivo.isEmpty ? null : motivo,
        referencia: referencia.isEmpty ? null : referencia,
        observaciones: obs.isEmpty ? null : obs,
        partida: _partidaKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(MovimientoFormResult(movimiento: created));
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
          'No se pudo registrar el movimiento. Revisa tu conexión e intenta de nuevo.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canOpen || _tipos.isEmpty) {
      return ModuleAccessDenied(
        title: _title,
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    final scrollPadding = formScrollPadding(context);
    final insumo = _selectedInsumo;
    final parsedCantidad = double.tryParse(
      _cantidadController.text.trim().replaceAll(',', '.'),
    );
    final exceedsStock =
        _isSalida &&
        insumo != null &&
        parsedCantidad != null &&
        parsedCantidad > insumo.disponibleValue + 1e-9;

    const mappedFields = {
      'tipo_movimiento_almacenid',
      'insumoid',
      'partida',
      'cantidad',
      'fecha',
      'destino_motivo',
      'referencia',
      'observaciones',
    };
    final error = _submitError;
    final generalError =
        error != null &&
            (error.validationErrors.isEmpty ||
                error.validationErrors.keys.any(
                  (field) => !mappedFields.contains(field),
                ))
        ? error.message
        : null;

    final partidaItems = <DropdownMenuItem<String>>[];
    if (insumo != null && insumo.partidas.isNotEmpty) {
      for (final p in insumo.partidas) {
        final key = p.partidaKey;
        if (key == null) continue;
        if (_isSalida && !_isAjuste && !p.utilizable) continue;
        partidaItems.add(
          DropdownMenuItem(
            value: key,
            child: Text(
              p.displayLabel(insumo.unidad),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
      if (insumo.sinPartidaValue > 0) {
        partidaItems.add(
          DropdownMenuItem(
            value: '0',
            child: Text(
              'Saldo sin partida (${formatInventarioDecimal(insumo.cantidadSinPartida)} ${insumo.unidad})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }

    return PopScope(
      canPop: !_submitting && !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_submitting) {
          unawaited(_cancel());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Volver',
            onPressed: _submitting ? null : _cancel,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(_title),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: formContentPadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.almacenName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isAjuste
                            ? 'Selecciona el tipo de ajuste, el producto, la cantidad y describe el motivo obligatorio.'
                            : (_isSalida
                                  ? 'Selecciona el producto y la cantidad a retirar del almacén.'
                                  : 'Selecciona el producto y la cantidad que ingresa al almacén.'),
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<int>(
                        key: const ValueKey('movimiento.tipo'),
                        initialValue: _tipos.any((t) => t.id == _tipoId)
                            ? _tipoId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de movimiento',
                          prefixIcon: Icon(Icons.swap_horiz_rounded),
                        ),
                        forceErrorText: _fieldError(
                          'tipo_movimiento_almacenid',
                        ),
                        items: [
                          for (final tipo in _tipos)
                            DropdownMenuItem(
                              value: tipo.id,
                              child: Text(tipo.name),
                            ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) {
                                setState(() {
                                  _tipoId = value;
                                  _partidaKey = null;
                                });
                                _clearError(field: 'tipo_movimiento_almacenid');
                              },
                        validator: (value) => value == null
                            ? 'Selecciona el tipo de movimiento.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        key: const ValueKey('movimiento.insumo'),
                        initialValue:
                            widget.existencias.any(
                              (e) => e.insumoId == _insumoId,
                            )
                            ? _insumoId
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Producto / insumo',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        forceErrorText: _fieldError('insumoid'),
                        items: [
                          for (final item in widget.existencias)
                            DropdownMenuItem(
                              value: item.insumoId,
                              child: Text(
                                item.dropdownLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) {
                                setState(() {
                                  _insumoId = value;
                                  _partidaKey = null;
                                });
                                _clearError(field: 'insumoid');
                              },
                        validator: (value) =>
                            value == null ? 'Selecciona un producto.' : null,
                      ),
                      if (partidaItems.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('movimiento.partida'),
                          initialValue:
                              partidaItems.any((i) => i.value == _partidaKey)
                              ? _partidaKey
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Partida / lote de origen',
                            prefixIcon: Icon(Icons.layers_outlined),
                          ),
                          forceErrorText: _fieldError('partida'),
                          items: partidaItems,
                          onChanged: _submitting
                              ? null
                              : (value) {
                                  setState(() => _partidaKey = value);
                                  _clearError(field: 'partida');
                                },
                          validator: (value) => _isSalida && value == null
                              ? 'Selecciona la partida de origen.'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('movimiento.cantidad'),
                        controller: _cantidadController,
                        scrollPadding: scrollPadding,
                        enabled: !_submitting,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        forceErrorText: _fieldError('cantidad'),
                        decoration: InputDecoration(
                          labelText: 'Cantidad',
                          hintText: 'Ej. 10.5',
                          prefixIcon: const Icon(Icons.scale_outlined),
                          suffixText: insumo?.unidad,
                        ),
                        validator: (value) => validateInventarioQuantity(
                          value,
                          maxDisponible: insumo?.disponibleValue,
                          unitLabel: insumo?.unidad,
                          checkStock: _isSalida,
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _clearError(field: 'cantidad');
                        },
                      ),
                      if (insumo != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Disponible actual: ${insumo.formattedDisponible}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (exceedsStock) ...[
                          const SizedBox(height: 8),
                          AppNotice(
                            tone: AppNoticeTone.error,
                            message:
                                'No hay cantidad suficiente: disponible ${insumo.formattedDisponible}. Corrige la cantidad.',
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('movimiento.fecha'),
                        controller: _fechaController,
                        scrollPadding: scrollPadding,
                        enabled: !_submitting,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        forceErrorText: _fieldError('fecha'),
                        decoration: InputDecoration(
                          labelText: 'Fecha del movimiento',
                          hintText: 'AAAA-MM-DD',
                          prefixIcon: const Icon(Icons.event_outlined),
                          suffixIcon: IconButton(
                            tooltip: 'Elegir fecha',
                            onPressed: _submitting ? null : _pickDate,
                            icon: const Icon(Icons.calendar_today_rounded),
                          ),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) {
                            return 'Indica la fecha del movimiento.';
                          }
                          final parsed = DateTime.tryParse(text);
                          if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
                              parsed == null) {
                            return 'Usa el formato AAAA-MM-DD.';
                          }
                          final today = DateTime.now();
                          final todayDate = DateTime(
                            today.year,
                            today.month,
                            today.day,
                          );
                          if (parsed.isAfter(todayDate)) {
                            return 'La fecha del movimiento no puede ser futura.';
                          }
                          return null;
                        },
                        onChanged: (_) => _clearError(field: 'fecha'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('movimiento.motivo'),
                        controller: _motivoController,
                        scrollPadding: scrollPadding,
                        enabled: !_submitting,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        maxLength: 150,
                        textCapitalization: TextCapitalization.sentences,
                        forceErrorText: _fieldError('destino_motivo'),
                        decoration: InputDecoration(
                          labelText: _isAjuste
                              ? 'Motivo del ajuste (obligatorio)'
                              : 'Motivo o destino (opcional)',
                          hintText: _isAjuste
                              ? 'Ej. Diferencia detectada en conteo físico'
                              : 'Ej. Compra a proveedor o entrega a campo',
                          prefixIcon: const Icon(Icons.description_outlined),
                        ),
                        validator: (value) {
                          if (_isAjuste && (value?.trim().isEmpty ?? true)) {
                            return 'Describe el motivo obligatorio del ajuste.';
                          }
                          return null;
                        },
                        onChanged: (_) => _clearError(field: 'destino_motivo'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('movimiento.referencia'),
                        controller: _referenciaController,
                        scrollPadding: scrollPadding,
                        enabled: !_submitting,
                        maxLength: 100,
                        forceErrorText: _fieldError('referencia'),
                        decoration: const InputDecoration(
                          labelText: 'Referencia (opcional)',
                          hintText: 'Ej. Factura #104 o Guía #12',
                          prefixIcon: Icon(Icons.tag_rounded),
                        ),
                        onChanged: (_) => _clearError(field: 'referencia'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('movimiento.observaciones'),
                        controller: _obsController,
                        scrollPadding: scrollPadding,
                        enabled: !_submitting,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        forceErrorText: _fieldError('observaciones'),
                        decoration: const InputDecoration(
                          labelText: 'Observaciones (opcional)',
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                        onChanged: (_) => _clearError(field: 'observaciones'),
                      ),
                      if (generalError != null) ...[
                        const SizedBox(height: 20),
                        AppNotice(
                          tone: AppNoticeTone.error,
                          message: generalError,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline_rounded),
                        label: Text(_submitting ? 'Guardando...' : _title),
                      ),
                      TextButton(
                        onPressed: _submitting ? null : _cancel,
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
