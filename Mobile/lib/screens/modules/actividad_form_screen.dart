import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/actividad_models.dart';
import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/module_page.dart';
import '../../services/module_service.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/form_validation.dart';
import 'module_access_denied.dart';

class ActividadFormResult {
  const ActividadFormResult({required this.record});

  final ModuleRecord record;
}

class ActividadFormScreen extends StatefulWidget {
  const ActividadFormScreen({
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
  State<ActividadFormScreen> createState() => _ActividadFormScreenState();
}

class _ActividadFormScreenState extends State<ActividadFormScreen> {
  static const _irrigationOptions = {
    'goteo': 'Riego por goteo',
    'aspersion': 'Riego por aspersión',
    'gravedad': 'Riego por gravedad',
  };

  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _plannedDate = TextEditingController();
  final _observations = TextEditingController();

  List<LoteOption> _lotes = const [];
  List<ResponsableOption> _responsables = const [];
  List<ActividadTipoOption> _tipos = const [];
  List<PrioridadOption> _prioridades = const [];

  late int? _selectedLoteId = widget.initialLoteId;
  int? _initialResponsableId;
  int? _selectedResponsableId;
  int? _selectedTipoId;
  int? _selectedPrioridadId;
  String? _selectedIrrigationKey;

  bool _loadingCatalogs = true;
  bool _submitting = false;
  String? _catalogWarning;
  ApiException? _submitError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFormOptions());
  }

  @override
  void dispose() {
    _description.dispose();
    _plannedDate.dispose();
    _observations.dispose();
    super.dispose();
  }

  Future<void> _loadFormOptions() async {
    setState(() {
      _loadingCatalogs = true;
      _catalogWarning = null;
    });

    final warnings = <String>[];

    Future<List<LoteOption>> fetchLotes() async {
      try {
        return List<LoteOption>.from(
          await widget.service.loadLoteOptions(widget.user),
        );
      } on ApiException catch (error) {
        warnings.add(error.message);
      } catch (_) {
        warnings.add('No se pudieron cargar los lotes.');
      }
      return const [];
    }

    Future<List<ResponsableOption>> fetchResponsables() async {
      try {
        return await widget.service.loadResponsables(widget.user);
      } on ApiException catch (error) {
        warnings.add(error.message);
      } catch (_) {
        warnings.add('No se pudo cargar el equipo de campo.');
      }
      return const [];
    }

    Future<List<ActividadTipoOption>> fetchTipos() async {
      try {
        return await widget.service.loadActividadTipos(widget.user);
      } on ApiException catch (error) {
        warnings.add(error.message);
      } catch (_) {
        warnings.add('No se pudieron cargar los tipos de actividad.');
      }
      return const [];
    }

    Future<List<PrioridadOption>> fetchPrioridades() async {
      try {
        return await widget.service.loadPrioridades(widget.user);
      } on ApiException catch (error) {
        warnings.add(error.message);
      } catch (_) {
        warnings.add('No se pudieron cargar las prioridades.');
      }
      return const [];
    }

    final results = await Future.wait<Object>([
      fetchLotes(),
      fetchResponsables(),
      fetchTipos(),
      fetchPrioridades(),
    ]);

    var lotes = results[0] as List<LoteOption>;
    if (widget.initialLoteId != null &&
        !lotes.any((item) => item.id == widget.initialLoteId)) {
      lotes = [
        LoteOption(
          id: widget.initialLoteId!,
          name: widget.initialLoteName ?? 'Lote #${widget.initialLoteId}',
        ),
        ...lotes,
      ];
    }
    final responsables = results[1] as List<ResponsableOption>;
    final tipos = results[2] as List<ActividadTipoOption>;
    final prioridades = results[3] as List<PrioridadOption>;

    if (!mounted) return;
    setState(() {
      _lotes = lotes;
      _responsables = responsables;
      _tipos = tipos;
      _prioridades = prioridades;
      if (_selectedLoteId != null &&
          !_lotes.any((item) => item.id == _selectedLoteId)) {
        _selectedLoteId = null;
      }
      if (_selectedResponsableId == null && _responsables.length == 1) {
        _selectedResponsableId = _responsables.first.id;
        _initialResponsableId = _responsables.first.id;
      }
      _loadingCatalogs = false;
      _catalogWarning = warnings.isEmpty ? null : warnings.first;
    });
  }

  bool get _hasUnsavedChanges =>
      _selectedLoteId != widget.initialLoteId ||
      _selectedResponsableId != _initialResponsableId ||
      _selectedTipoId != null ||
      _selectedPrioridadId != null ||
      _selectedIrrigationKey != null ||
      _description.text.trim().isNotEmpty ||
      _plannedDate.text.trim().isNotEmpty ||
      _observations.text.trim().isNotEmpty;

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

  Future<void> _pickPlannedDate() async {
    if (_submitting) return;
    final now = DateTime.now();
    final initial = DateTime.tryParse(_plannedDate.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Fecha planificada',
      cancelText: 'Cancelar',
      confirmText: 'Seleccionar',
    );
    if (!mounted || picked == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    setState(() {
      _plannedDate.text =
          '${picked.year}-${two(picked.month)}-${two(picked.day)}';
    });
    _clearError(field: 'fecha_planificada');
  }

  String? _validateDate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      return 'Usa el formato AAAA-MM-DD, por ejemplo 2026-12-01.';
    }
    final parts = text.split('-').map(int.parse).toList();
    final parsed = DateTime(parts[0], parts[1], parts[2]);
    if (parsed.year != parts[0] ||
        parsed.month != parts[1] ||
        parsed.day != parts[2]) {
      return 'Ingresa una fecha válida en el calendario.';
    }
    return null;
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    if (_hasUnsavedChanges) {
      final discard = await confirmImportantAction(
        context,
        icon: Icons.warning_amber_rounded,
        title: '¿Descartar asignación?',
        message:
            'Tienes datos sin guardar en la asignación. Si sales ahora, no se registrará la actividad.',
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

    final loteId = _selectedLoteId;
    final responsableId = _selectedResponsableId;
    final tipoId = _selectedTipoId;
    if (loteId == null || responsableId == null || tipoId == null) {
      revealFormErrors(_formKey);
      return;
    }

    final selectedTipo = _tipos.where((item) => item.id == tipoId).firstOrNull;
    String? detailJson;
    if (selectedTipo != null &&
        selectedTipo.isIrrigation &&
        _selectedIrrigationKey != null) {
      detailJson = jsonEncode({
        'riego': {
          'key': _selectedIrrigationKey,
          'label': _irrigationOptions[_selectedIrrigationKey],
        },
      });
    }

    final loteLabel = _lotes
        .where((item) => item.id == loteId)
        .map((item) => item.name)
        .firstOrNull;
    final responsableLabel = _responsables
        .where((item) => item.id == responsableId)
        .map((item) => item.name)
        .firstOrNull;
    final prioridadLabel = _prioridades
        .where((item) => item.id == _selectedPrioridadId)
        .map((item) => item.name)
        .firstOrNull;

    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.assignment_turned_in_outlined,
      title: '¿Asignar actividad?',
      message: 'Confirma los datos de la tarea antes de enviarla al equipo.',
      details: [
        if (loteLabel != null) 'Lote: $loteLabel',
        if (selectedTipo != null) 'Actividad: ${selectedTipo.name}',
        if (responsableLabel != null) 'Responsable: $responsableLabel',
        if (prioridadLabel != null) 'Prioridad: $prioridadLabel',
        if (_plannedDate.text.trim().isNotEmpty)
          'Fecha planificada: ${_plannedDate.text.trim()}',
      ],
      confirmLabel: 'Confirmar asignación',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final created = await widget.service.createActividad(
        widget.user,
        loteId: loteId,
        responsableId: responsableId,
        tipoActividadId: tipoId,
        prioridadId: _selectedPrioridadId,
        description: _description.text.trim(),
        plannedDate: _plannedDate.text.trim(),
        observations: _observations.text.trim(),
        detailJson: detailJson,
      );
      if (!mounted) return;
      Navigator.of(context).pop(ActividadFormResult(record: created));
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
          'No se pudo asignar la actividad. Revisa tu conexión e intenta de nuevo.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ActividadPermissions.canAssign(widget.user)) {
      return ModuleAccessDenied(
        title: 'Asignar actividad',
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
          title: const Text('Asignar actividad'),
        ),
        body: SafeArea(
          child: _loadingCatalogs
              ? const AppLoading(message: 'Cargando opciones de asignación...')
              : _form(context),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final scrollPadding = formScrollPadding(context);
    final selectedTipo = _tipos
        .where((item) => item.id == _selectedTipoId)
        .firstOrNull;
    final showIrrigation = selectedTipo?.isIrrigation == true;
    const mappedFields = {
      'loteid',
      'tipoactividadid',
      'usuarioid',
      'prioridadid',
      'fecha_planificada',
      'descripcion',
      'observaciones',
      'detalle_actividad_json',
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
    final detailError = _fieldError('detalle_actividad_json');

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
                  'Nueva asignación',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Selecciona el lote, el tipo de trabajo, el trabajador responsable, la prioridad y la fecha planificada.',
                ),
                if (_catalogWarning case final warning?) ...[
                  const SizedBox(height: 16),
                  AppNotice(
                    tone: AppNoticeTone.warning,
                    message: warning,
                    action: TextButton.icon(
                      onPressed: _submitting ? null : _loadFormOptions,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Reintentar'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                DropdownButtonFormField<int>(
                  key: const ValueKey('actividad.lote'),
                  initialValue: _selectedLoteId,
                  isExpanded: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('loteid'),
                  decoration: const InputDecoration(
                    labelText: 'Lote',
                    prefixIcon: Icon(Icons.landscape_outlined),
                  ),
                  hint: const Text('Selecciona un lote'),
                  items: [
                    for (final lote in _lotes)
                      DropdownMenuItem<int>(
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
                          setState(() => _selectedLoteId = value);
                          _clearError(field: 'loteid');
                        },
                  validator: (value) =>
                      value == null ? 'Selecciona un lote.' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const ValueKey('actividad.tipo'),
                  initialValue: _selectedTipoId,
                  isExpanded: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('tipoactividadid'),
                  decoration: const InputDecoration(
                    labelText: 'Tipo de actividad',
                    prefixIcon: Icon(Icons.event_note_outlined),
                  ),
                  hint: const Text('Selecciona el tipo de actividad'),
                  items: [
                    for (final tipo in _tipos)
                      DropdownMenuItem<int>(
                        value: tipo.id,
                        child: Text(tipo.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          setState(() {
                            _selectedTipoId = value;
                            _selectedIrrigationKey = null;
                          });
                          _clearError(field: 'tipoactividadid');
                          _clearError(field: 'detalle_actividad_json');
                        },
                  validator: (value) =>
                      value == null ? 'Selecciona un tipo de actividad.' : null,
                ),
                if (showIrrigation) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('actividad.riego'),
                    initialValue: _selectedIrrigationKey,
                    isExpanded: true,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    forceErrorText: detailError,
                    decoration: const InputDecoration(
                      labelText: 'Método de riego',
                      prefixIcon: Icon(Icons.water_drop_outlined),
                    ),
                    hint: const Text('Selecciona el método de riego'),
                    items: [
                      for (final entry in _irrigationOptions.entries)
                        DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) {
                            setState(() => _selectedIrrigationKey = value);
                            _clearError(field: 'detalle_actividad_json');
                          },
                    validator: (value) =>
                        value == null ? 'Selecciona el método de riego.' : null,
                  ),
                ] else if (detailError != null) ...[
                  const SizedBox(height: 12),
                  AppNotice(tone: AppNoticeTone.error, message: detailError),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const ValueKey('actividad.responsable'),
                  initialValue: _selectedResponsableId,
                  isExpanded: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('usuarioid'),
                  decoration: const InputDecoration(
                    labelText: 'Responsable',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  hint: const Text('Selecciona el responsable'),
                  items: [
                    for (final person in _responsables)
                      DropdownMenuItem<int>(
                        value: person.id,
                        child: Text(
                          person.displayLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          setState(() => _selectedResponsableId = value);
                          _clearError(field: 'usuarioid');
                        },
                  validator: (value) =>
                      value == null ? 'Selecciona un responsable.' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const ValueKey('actividad.prioridad'),
                  initialValue: _selectedPrioridadId,
                  isExpanded: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('prioridadid'),
                  decoration: const InputDecoration(
                    labelText: 'Prioridad (opcional)',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  hint: const Text('Selecciona la prioridad'),
                  items: [
                    for (final item in _prioridades)
                      DropdownMenuItem<int>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          setState(() => _selectedPrioridadId = value);
                          _clearError(field: 'prioridadid');
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('actividad.fecha_planificada'),
                  controller: _plannedDate,
                  scrollPadding: scrollPadding,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('fecha_planificada'),
                  enabled: !_submitting,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Fecha planificada (opcional)',
                    hintText: 'AAAA-MM-DD',
                    prefixIcon: const Icon(Icons.event_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Elegir fecha',
                      onPressed: _submitting ? null : _pickPlannedDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                  validator: _validateDate,
                  onChanged: (_) => _clearError(field: 'fecha_planificada'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('actividad.descripcion'),
                  controller: _description,
                  scrollPadding: scrollPadding,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('descripcion'),
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    hintText: 'Ej. Preparar surcos del sector norte',
                    prefixIcon: Icon(Icons.assignment_outlined),
                    counterText: '',
                  ),
                  onChanged: (_) => _clearError(field: 'descripcion'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('actividad.observaciones'),
                  controller: _observations,
                  scrollPadding: scrollPadding,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('observaciones'),
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  maxLength: 250,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                    hintText: 'Indicaciones para el trabajador en campo',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  onChanged: (_) => _clearError(field: 'observaciones'),
                ),
                if (generalError != null) ...[
                  const SizedBox(height: 20),
                  AppNotice(tone: AppNoticeTone.error, message: generalError),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(
                    _submitting ? 'Asignando...' : 'Asignar actividad',
                  ),
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
    );
  }
}
