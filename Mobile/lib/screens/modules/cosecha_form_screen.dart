import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/actividad_models.dart';
import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/cosecha_models.dart';
import '../../models/module_page.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/form_validation.dart';
import 'module_access_denied.dart';

class CosechaFormResult {
  const CosechaFormResult({required this.record});

  final ModuleRecord record;
}

class CosechaFormScreen extends StatefulWidget {
  const CosechaFormScreen({
    super.key,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.initialLoteId,
    this.initialLoteName,
  });

  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final int? initialLoteId;
  final String? initialLoteName;

  @override
  State<CosechaFormScreen> createState() => _CosechaFormScreenState();
}

class _CosechaFormScreenState extends State<CosechaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();
  final _fechaController = TextEditingController(text: _todayIso());
  final _obsController = TextEditingController();

  List<LoteOption> _lotes = const [];
  List<CosechaUnidadOption> _unidades = const [];
  List<CosechaPresentacionOption> _presentaciones = const [];

  int? _loteId;
  int? _unidadId;
  int? _presentacionId;

  bool _loading = true;
  bool _loadingPresentaciones = false;
  bool _submitting = false;
  String? _loadError;
  String? _presentacionesError;
  ApiException? _submitError;

  static String _todayIso() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  @override
  void initState() {
    super.initState();
    _loteId = widget.initialLoteId;
    if (CosechaPermissions.canCreate(widget.user)) {
      unawaited(_loadCatalogs());
    }
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _fechaController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.service.loadLoteOptions(widget.user),
        widget.service.loadCosechaUnidades(widget.user),
      ]);
      if (!mounted) return;
      final lotes = List<LoteOption>.from(results[0] as List<LoteOption>);
      final unidades = results[1] as List<CosechaUnidadOption>;
      if (widget.initialLoteId != null &&
          !lotes.any((l) => l.id == widget.initialLoteId)) {
        lotes.insert(
          0,
          LoteOption(
            id: widget.initialLoteId!,
            name: widget.initialLoteName ?? 'Lote #${widget.initialLoteId}',
          ),
        );
      }
      final defaultLote =
          _loteId ?? (lotes.length == 1 ? lotes.first.id : null);
      final defaultUnit =
          unidades.where((u) => u.isKilogram).firstOrNull?.id ??
          unidades.firstOrNull?.id;
      setState(() {
        _lotes = lotes;
        _unidades = unidades;
        _loteId = defaultLote;
        _unidadId ??= defaultUnit;
        _loading = false;
      });
      if (defaultLote != null) {
        unawaited(_loadPresentaciones(defaultLote));
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'No se pudieron cargar los datos para registrar cosechas.';
      });
    }
  }

  Future<void> _loadPresentaciones(int loteId) async {
    setState(() {
      _loadingPresentaciones = true;
      _presentacionesError = null;
      _presentaciones = const [];
      _presentacionId = null;
    });
    try {
      final config = await widget.service.loadCosechaConfiguracion(
        widget.user,
        loteId,
      );
      if (!mounted || _loteId != loteId) return;
      final defaultPres =
          config.predeterminadaId ??
          (config.presentaciones.length == 1
              ? config.presentaciones.first.id
              : null);
      setState(() {
        _presentaciones = config.presentaciones;
        _presentacionId = defaultPres;
        _loadingPresentaciones = false;
      });
    } on ApiException catch (error) {
      if (!mounted || _loteId != loteId) return;
      setState(() {
        _loadingPresentaciones = false;
        _presentacionesError = error.message;
      });
    } catch (_) {
      if (!mounted || _loteId != loteId) return;
      setState(() {
        _loadingPresentaciones = false;
        _presentacionesError =
            'No se pudieron cargar las presentaciones configuradas para este lote.';
      });
    }
  }

  LoteOption? _selectedLote() {
    for (final item in _lotes) {
      if (item.id == _loteId) return item;
    }
    return null;
  }

  CosechaUnidadOption? _selectedUnidad() {
    for (final item in _unidades) {
      if (item.id == _unidadId) return item;
    }
    return null;
  }

  CosechaPresentacionOption? _selectedPresentacion() {
    for (final item in _presentaciones) {
      if (item.id == _presentacionId) return item;
    }
    return null;
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
      _obsController.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    if (_submitting) return;
    final initial =
        DateTime.tryParse(_fechaController.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted || picked == null) return;
    final month = picked.month.toString().padLeft(2, '0');
    final day = picked.day.toString().padLeft(2, '0');
    setState(() {
      _fechaController.text = '${picked.year}-$month-$day';
    });
    _clearError(field: 'fechacosecha');
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    if (_hasUnsavedChanges) {
      final discard = await confirmImportantAction(
        context,
        icon: Icons.warning_amber_rounded,
        title: '¿Descartar cosecha?',
        message:
            'Tienes datos ingresados sin guardar. Si sales ahora, no se registrará la cosecha.',
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
    final loteId = _loteId;
    final unidadId = _unidadId;
    if (loteId == null || unidadId == null) return;

    final cantidad = _cantidadController.text.trim().replaceAll(',', '.');
    final fecha = _fechaController.text.trim();
    final obs = _obsController.text.trim();
    final lote = _selectedLote();
    final unidad = _selectedUnidad();
    final presentacion = _selectedPresentacion();

    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.grass_rounded,
      title: '¿Registrar cosecha?',
      message:
          'Se registrará la cosecha en el sistema con las equivalencias calculadas por el servidor.',
      details: [
        'Lote: ${lote?.name ?? 'Lote #$loteId'}',
        if (presentacion != null) 'Presentación: ${presentacion.name}',
        'Cantidad: $cantidad ${unidad?.abbreviation ?? ''}'.trim(),
        if (fecha.isNotEmpty) 'Fecha: $fecha',
      ],
      confirmLabel: 'Confirmar registro',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final created = await widget.service.createCosecha(
        widget.user,
        loteId: loteId,
        cantidad: cantidad,
        unidadMedidaId: unidadId,
        catalogoTamanoConteoId: _presentacionId,
        fechaCosecha: fecha.isEmpty ? null : fecha,
        observaciones: obs.isEmpty ? null : obs,
      );
      if (!mounted) return;
      Navigator.of(context).pop(CosechaFormResult(record: created));
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
          'No se pudo registrar la cosecha. Revisa tu conexión e intenta de nuevo.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!CosechaPermissions.canCreate(widget.user)) {
      return ModuleAccessDenied(
        title: 'Registrar cosecha',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
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
          title: const Text('Registrar cosecha'),
        ),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const AppLoading(message: 'Cargando lotes y unidades...');
    }
    if (_loadError case final error?) {
      return AppErrorState(message: error, onRetry: _loadCatalogs);
    }

    final scrollPadding = formScrollPadding(context);
    const mappedFields = {
      'loteid',
      'catalogotamanoconteoid',
      'cantidad',
      'cantidadkg',
      'unidadmedidaid',
      'fechacosecha',
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

    return SingleChildScrollView(
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
                  'Nueva cosecha',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Selecciona el lote autorizado, indica la presentación, la cantidad y la fecha de cosecha.',
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<int>(
                  key: const ValueKey('cosecha.lote'),
                  initialValue: _lotes.any((l) => l.id == _loteId)
                      ? _loteId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Lote autorizado',
                    prefixIcon: Icon(Icons.landscape_outlined),
                  ),
                  forceErrorText: _fieldError('loteid'),
                  items: [
                    for (final lote in _lotes)
                      DropdownMenuItem(
                        value: lote.id,
                        child: Text(
                          lote.displayLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          setState(() => _loteId = value);
                          _clearError(field: 'loteid');
                          if (value != null) {
                            unawaited(_loadPresentaciones(value));
                          }
                        },
                  validator: (value) =>
                      value == null ? 'Selecciona un lote autorizado.' : null,
                ),
                const SizedBox(height: 16),
                if (_loadingPresentaciones)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Cargando presentaciones del lote...'),
                      ],
                    ),
                  )
                else if (_presentacionesError case final presError?) ...[
                  AppNotice(tone: AppNoticeTone.error, message: presError),
                  const SizedBox(height: 8),
                  if (_loteId != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _submitting
                            ? null
                            : () => _loadPresentaciones(_loteId!),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Reintentar presentaciones'),
                      ),
                    ),
                ] else if (_loteId != null && _presentaciones.isEmpty)
                  const AppNotice(
                    tone: AppNoticeTone.info,
                    message:
                        'Este lote no tiene presentaciones configuradas; se registrará con la cantidad y unidad indicadas.',
                  )
                else if (_presentaciones.isNotEmpty)
                  DropdownButtonFormField<int>(
                    key: const ValueKey('cosecha.presentacion'),
                    initialValue:
                        _presentaciones.any((p) => p.id == _presentacionId)
                        ? _presentacionId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Presentación / calibre',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    forceErrorText: _fieldError('catalogotamanoconteoid'),
                    items: [
                      for (final pres in _presentaciones)
                        DropdownMenuItem(
                          value: pres.id,
                          child: Text(
                            pres.displayLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            setState(() => _presentacionId = value);
                            _clearError(field: 'catalogotamanoconteoid');
                          },
                    validator: (value) => value == null
                        ? 'Selecciona la presentación de la cosecha.'
                        : null,
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('cosecha.cantidad'),
                  controller: _cantidadController,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  forceErrorText:
                      _fieldError('cantidad') ?? _fieldError('cantidadkg'),
                  decoration: InputDecoration(
                    labelText: 'Cantidad cosechada',
                    hintText: 'Ej. 125.5',
                    prefixIcon: const Icon(Icons.scale_outlined),
                    suffixText: _selectedUnidad()?.abbreviation,
                  ),
                  validator: validateCosechaQuantity,
                  onChanged: (_) {
                    _clearError(field: 'cantidad');
                    _clearError(field: 'cantidadkg');
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const ValueKey('cosecha.unidad'),
                  initialValue: _unidades.any((u) => u.id == _unidadId)
                      ? _unidadId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Unidad de medida',
                    prefixIcon: Icon(Icons.straighten_outlined),
                  ),
                  forceErrorText: _fieldError('unidadmedidaid'),
                  items: [
                    for (final unidad in _unidades)
                      DropdownMenuItem(
                        value: unidad.id,
                        child: Text(
                          unidad.displayLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          setState(() => _unidadId = value);
                          _clearError(field: 'unidadmedidaid');
                        },
                  validator: (value) =>
                      value == null ? 'Selecciona una unidad de medida.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('cosecha.fecha'),
                  controller: _fechaController,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('fechacosecha'),
                  decoration: InputDecoration(
                    labelText: 'Fecha de cosecha',
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
                      return 'Indica la fecha de cosecha.';
                    }
                    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
                        DateTime.tryParse(text) == null) {
                      return 'Usa el formato AAAA-MM-DD (ej. 2026-11-19).';
                    }
                    return null;
                  },
                  onChanged: (_) => _clearError(field: 'fechacosecha'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('cosecha.observaciones'),
                  controller: _obsController,
                  scrollPadding: scrollPadding,
                  enabled: !_submitting,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  forceErrorText: _fieldError('observaciones'),
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                    hintText: 'Notas sobre calidad o condiciones de cosecha',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                  onChanged: (_) => _clearError(field: 'observaciones'),
                ),
                if (generalError != null) ...[
                  const SizedBox(height: 20),
                  AppNotice(tone: AppNoticeTone.error, message: generalError),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.grass_rounded),
                  label: Text(
                    _submitting
                        ? 'Registrando cosecha...'
                        : 'Registrar cosecha',
                  ),
                ),
                TextButton(
                  onPressed: _submitting ? null : _cancel,
                  child: const Text('Cancelar'),
                ),
                const SizedBox(height: 12),
                const Divider(color: AppTheme.line),
                const SizedBox(height: 8),
                Text(
                  'Las equivalencias en kilogramos, empaques y unidades son calculadas por el servidor al guardar.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
