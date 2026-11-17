import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/lote_models.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/form_validation.dart';
import '../../widgets/location_input_field.dart';
import 'module_access_denied.dart';

class LoteFormResult {
  const LoteFormResult({required this.record, required this.isEdit});

  final ModuleRecord record;
  final bool isEdit;
}

class LoteFormScreen extends StatefulWidget {
  const LoteFormScreen({
    super.key,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.loteId,
    this.initialData,
    this.requestLocation,
  });

  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final int? loteId;
  final LoteEditableData? initialData;
  final Future<DeviceLocation?> Function()? requestLocation;

  @override
  State<LoteFormScreen> createState() => _LoteFormScreenState();
}

class _LoteFormScreenState extends State<LoteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _surface = TextEditingController();
  final _plannedSeed = TextEditingController();
  final _location = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  LoteEditableData? _initial;
  List<SeedOption> _seeds = const [];
  int? _selectedSeedId;
  bool _loadingInitial = false;
  bool _loadingSeeds = true;
  bool _submitting = false;
  String? _loadError;
  String? _seedLoadError;
  String? _notice;
  ApiException? _submitError;

  bool get _isEdit => widget.loteId != null;

  @override
  void initState() {
    super.initState();
    _initial = widget.initialData;
    if (_initial != null) {
      _applyInitial(_initial!);
    }
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _name.dispose();
    _surface.dispose();
    _plannedSeed.dispose();
    _location.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _applyInitial(LoteEditableData data) {
    _name.text = data.name;
    _surface.text = data.superficie == null
        ? ''
        : _formatNumber(data.superficie!);
    _plannedSeed.text = data.cantidadSemillaPlanificada == null
        ? ''
        : _formatNumber(data.cantidadSemillaPlanificada!);
    _location.text = data.ubicacion ?? '';
    _latitude.text = data.latitud?.toString() ?? '';
    _longitude.text = data.longitud?.toString() ?? '';
    _selectedSeedId = data.insumoSemillaId;
  }

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  Future<void> _initialize() async {
    if (_isEdit && _initial == null) {
      setState(() {
        _loadingInitial = true;
        _loadError = null;
      });
      try {
        final record = await widget.service.loadDetail(
          AppModule.lotes,
          widget.user,
          widget.loteId!,
        );
        if (!mounted) return;
        final data = record.loteData;
        if (data == null) {
          setState(() {
            _loadingInitial = false;
            _loadError = 'No pudimos cargar los datos del lote.';
          });
          return;
        }
        _initial = data;
        _applyInitial(data);
        setState(() => _loadingInitial = false);
      } on ApiException catch (error) {
        if (!mounted) return;
        setState(() {
          _loadingInitial = false;
          _loadError = error.message;
        });
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loadingInitial = false;
          _loadError = 'No se pudo cargar la información del lote.';
        });
        return;
      }
    }
    await _loadSeeds();
  }

  Future<void> _loadSeeds() async {
    setState(() {
      _loadingSeeds = true;
      _seedLoadError = null;
    });
    try {
      final loaded = await widget.service.loadSeedOptions(widget.user);
      if (!mounted) return;
      final options = List<SeedOption>.from(loaded);
      final initialSeedId = _initial?.insumoSemillaId;
      if (initialSeedId != null &&
          !options.any((item) => item.id == initialSeedId)) {
        options.insert(
          0,
          SeedOption(
            id: initialSeedId,
            name: _initial?.insumoSemillaNombre ?? 'Semilla #$initialSeedId',
          ),
        );
      }
      setState(() {
        _seeds = options;
        _loadingSeeds = false;
        if (_selectedSeedId != null &&
            !_seeds.any((item) => item.id == _selectedSeedId)) {
          _selectedSeedId = null;
        }
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSeeds = false;
        _seedLoadError = error.message;
        _seeds = _fallbackSeedFromInitial();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSeeds = false;
        _seedLoadError = 'No se pudieron cargar las semillas disponibles.';
        _seeds = _fallbackSeedFromInitial();
      });
    }
  }

  List<SeedOption> _fallbackSeedFromInitial() {
    final seedId = _initial?.insumoSemillaId;
    if (seedId == null) return const [];
    return [
      SeedOption(
        id: seedId,
        name: _initial?.insumoSemillaNombre ?? 'Semilla #$seedId',
      ),
    ];
  }

  double? _parseDecimal(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  bool get _hasUnsavedChanges {
    final initial = _initial;
    if (initial == null) {
      return _name.text.trim().isNotEmpty ||
          _surface.text.trim().isNotEmpty ||
          _plannedSeed.text.trim().isNotEmpty ||
          _location.text.trim().isNotEmpty ||
          _latitude.text.trim().isNotEmpty ||
          _longitude.text.trim().isNotEmpty ||
          _selectedSeedId != null;
    }
    return _buildEditChanges(initial).isNotEmpty;
  }

  bool _sameDouble(double? a, double? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() < 0.000001;
  }

  Map<String, Object?> _buildEditChanges(LoteEditableData initial) {
    final changes = <String, Object?>{};
    final name = _name.text.trim();
    if (name != initial.name) {
      changes['nombre'] = name;
    }

    final surface = _parseDecimal(_surface.text);
    if (surface != null && !_sameDouble(surface, initial.superficie)) {
      changes['superficie'] = surface;
    }

    if (_selectedSeedId != null && _selectedSeedId != initial.insumoSemillaId) {
      changes['insumosemillaid'] = _selectedSeedId;
    }

    final planned = _parseDecimal(_plannedSeed.text);
    if (!_sameDouble(planned, initial.cantidadSemillaPlanificada)) {
      changes['cantidad_semilla_planificada'] = planned;
    }

    final location = _location.text.trim();
    final normalizedLocation = location.isEmpty ? null : location;
    if (normalizedLocation != initial.ubicacion) {
      changes['ubicacion'] = normalizedLocation;
    }

    final lat = _parseDecimal(_latitude.text);
    final lng = _parseDecimal(_longitude.text);
    if (!_sameDouble(lat, initial.latitud) ||
        !_sameDouble(lng, initial.longitud)) {
      changes['latitud'] = lat;
      changes['longitud'] = lng;
    }

    return changes;
  }

  String? _fieldError(String field) {
    final messages = _submitError?.validationErrors[field];
    return messages == null || messages.isEmpty ? null : messages.join('\n');
  }

  void _clearError({String? field}) {
    final error = _submitError;
    if (_notice == null && error == null) return;
    if (field != null && error != null && error.validationErrors.isNotEmpty) {
      if (!error.validationErrors.containsKey(field)) {
        if (_notice != null) setState(() => _notice = null);
        return;
      }
      final remaining = Map.of(error.validationErrors)..remove(field);
      setState(() {
        _notice = null;
        _submitError = remaining.isEmpty
            ? null
            : ApiException(
                error.message,
                statusCode: error.statusCode,
                validationErrors: remaining,
              );
      });
    } else {
      setState(() {
        _notice = null;
        _submitError = null;
      });
    }
  }

  Future<void> _cancel() async {
    if (_submitting) return;
    if (_hasUnsavedChanges) {
      final discard = await confirmImportantAction(
        context,
        icon: Icons.warning_amber_rounded,
        title: '¿Descartar cambios?',
        message:
            'Tienes datos sin guardar en el formulario del lote. Si sales ahora, se perderán.',
        cancelLabel: 'Seguir editando',
        confirmLabel: 'Descartar cambios',
        destructive: true,
      );
      if (!mounted || !discard) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_submitting || !validateForm(_formKey)) return;

    final seedId = _selectedSeedId;
    final surface = _parseDecimal(_surface.text);
    final planned = _parseDecimal(_plannedSeed.text);
    final location = _location.text.trim();
    final lat = _parseDecimal(_latitude.text);
    final lng = _parseDecimal(_longitude.text);

    if (!_isEdit && seedId == null) {
      revealFormErrors(_formKey);
      return;
    }
    if (surface == null || surface < 0.01) {
      revealFormErrors(_formKey);
      return;
    }

    Map<String, Object?>? editChanges;
    if (_isEdit) {
      editChanges = _buildEditChanges(_initial!);
      if (editChanges.isEmpty) {
        setState(() {
          _notice = 'No hay cambios para guardar.';
          _submitError = null;
        });
        return;
      }
    }

    final seedLabel = _seeds
        .where((item) => item.id == seedId)
        .map((item) => item.name)
        .firstOrNull;
    final confirmed = await confirmImportantAction(
      context,
      icon: _isEdit ? Icons.edit_note_rounded : Icons.landscape_outlined,
      title: _isEdit ? '¿Guardar cambios del lote?' : '¿Crear lote?',
      message: _isEdit
          ? 'Se actualizarán únicamente los datos modificados de este lote.'
          : 'Revisa los datos antes de registrar el lote en el sistema.',
      details: [
        'Nombre: ${_name.text.trim()}',
        if (seedLabel != null) 'Semilla: $seedLabel',
        'Superficie: ${_surface.text.trim()} ha',
        if (location.isNotEmpty) 'Ubicación: $location',
        if (lat != null && lng != null)
          'Coordenadas: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
      ],
      confirmLabel: _isEdit ? 'Confirmar cambios' : 'Confirmar registro',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _notice = null;
      _submitError = null;
    });

    try {
      final ModuleRecord saved;
      if (_isEdit) {
        saved = await widget.service.updateLote(
          widget.user,
          widget.loteId!,
          changes: editChanges!,
        );
      } else {
        saved = await widget.service.createLote(
          widget.user,
          name: _name.text.trim(),
          seedId: seedId!,
          surface: surface,
          location: location.isEmpty ? null : location,
          latitude: lat,
          longitude: lng,
          plannedSeedAmount: planned,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(LoteFormResult(record: saved, isEdit: _isEdit));
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
          'No se pudo guardar el lote. Revisa tu conexión e intenta de nuevo.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _isEdit
        ? LotePermissions.canEdit(widget.user)
        : LotePermissions.canCreate(widget.user);
    if (!allowed) {
      return ModuleAccessDenied(
        title: _isEdit ? 'Editar lote' : 'Nuevo lote',
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
          title: Text(_isEdit ? 'Editar lote' : 'Nuevo lote'),
        ),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loadingInitial) {
      return const AppLoading(message: 'Cargando datos del lote...');
    }
    if (_loadError case final error?) {
      return AppErrorState(message: error, onRetry: _initialize);
    }
    if (_isEdit && _initial?.isClosed == true) {
      return AppEmptyState(
        icon: Icons.lock_clock_outlined,
        title: 'Este lote no puede editarse',
        message: 'Este lote ya fue cosechado o cerró su ciclo productivo.',
        action: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver al lote'),
        ),
      );
    }

    final scrollPadding = formScrollPadding(context);
    final selectedSeed = _seeds
        .where((item) => item.id == _selectedSeedId)
        .firstOrNull;
    final plannedUnit = selectedSeed?.unit;
    const mappedFields = {
      'nombre',
      'insumosemillaid',
      'superficie',
      'cantidad_semilla_planificada',
      'ubicacion',
      'latitud',
      'longitud',
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
                  _isEdit ? 'Actualiza el lote' : 'Registra un nuevo lote',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _isEdit
                      ? 'Modifica únicamente los datos que necesites corregir; los demás permanecerán iguales.'
                      : 'Selecciona la semilla, indica la superficie en hectáreas y registra la ubicación del terreno.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('lote.nombre'),
                  controller: _name,
                  scrollPadding: scrollPadding,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('nombre'),
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del lote',
                    hintText: 'Ej. Parcela Los Pinos',
                    prefixIcon: Icon(Icons.landscape_outlined),
                    counterText: '',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Ingresa el nombre del lote.';
                    }
                    if (text.length > 100) {
                      return 'El nombre no puede superar 100 caracteres.';
                    }
                    return null;
                  },
                  onChanged: (_) => _clearError(field: 'nombre'),
                ),
                const SizedBox(height: 16),
                if (_loadingSeeds)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                DropdownButtonFormField<int>(
                  key: const ValueKey('lote.semilla'),
                  initialValue: _selectedSeedId,
                  isExpanded: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('insumosemillaid'),
                  decoration: const InputDecoration(
                    labelText: 'Semilla / material de siembra',
                    prefixIcon: Icon(Icons.eco_outlined),
                  ),
                  hint: Text(
                    _loadingSeeds
                        ? 'Cargando semillas...'
                        : 'Selecciona una semilla',
                  ),
                  items: [
                    for (final seed in _seeds)
                      DropdownMenuItem<int>(
                        value: seed.id,
                        child: Text(
                          seed.displayLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          setState(() => _selectedSeedId = value);
                          _clearError(field: 'insumosemillaid');
                        },
                  validator: (value) {
                    if (value == null) {
                      return 'Selecciona la semilla del lote.';
                    }
                    return null;
                  },
                ),
                if (_seedLoadError case final seedError?) ...[
                  const SizedBox(height: 12),
                  AppNotice(
                    tone: AppNoticeTone.warning,
                    message: seedError,
                    action: TextButton.icon(
                      onPressed: _loadingSeeds || _submitting
                          ? null
                          : _loadSeeds,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Reintentar semillas'),
                    ),
                  ),
                ] else if (!_loadingSeeds && _seeds.isEmpty) ...[
                  const SizedBox(height: 12),
                  AppNotice(
                    tone: AppNoticeTone.warning,
                    message:
                        'No hay semillas disponibles en tu inventario autorizado.',
                    action: TextButton.icon(
                      onPressed: _submitting ? null : _loadSeeds,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Actualizar semillas'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('lote.superficie'),
                  controller: _surface,
                  scrollPadding: scrollPadding,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('superficie'),
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Superficie',
                    hintText: 'Ej. 2.5',
                    suffixText: 'ha',
                    helperText: 'Expresa la superficie del lote en hectáreas.',
                    prefixIcon: Icon(Icons.square_foot_outlined),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Ingresa la superficie del lote.';
                    }
                    final parsed = _parseDecimal(text);
                    if (parsed == null || parsed < 0.01) {
                      return 'Ingresa una superficie válida de al menos 0.01 ha.';
                    }
                    return null;
                  },
                  onChanged: (_) => _clearError(field: 'superficie'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('lote.cantidad_semilla_planificada'),
                  controller: _plannedSeed,
                  scrollPadding: scrollPadding,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('cantidad_semilla_planificada'),
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: plannedUnit != null
                        ? 'Cantidad de semilla planificada ($plannedUnit, opcional)'
                        : 'Cantidad de semilla planificada (opcional)',
                    hintText: 'Ej. 10',
                    helperText:
                        'Si la dejas vacía, el sistema calculará la sugerida.',
                    prefixIcon: const Icon(Icons.scale_outlined),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final parsed = _parseDecimal(text);
                    if (parsed == null || parsed < 0) {
                      return 'Ingresa una cantidad válida mayor o igual a 0.';
                    }
                    return null;
                  },
                  onChanged: (_) =>
                      _clearError(field: 'cantidad_semilla_planificada'),
                ),
                const SizedBox(height: 20),
                LocationInputField(
                  controller: _location,
                  latitudeController: _latitude,
                  longitudeController: _longitude,
                  requestLocation: widget.requestLocation,
                  enabled: !_submitting,
                  locationError: _fieldError('ubicacion'),
                  latitudeError: _fieldError('latitud'),
                  longitudeError: _fieldError('longitud'),
                  onLocationChanged: (_) => _clearError(field: 'ubicacion'),
                  onCoordinatesChanged: (_) {
                    _clearError(field: 'latitud');
                    _clearError(field: 'longitud');
                  },
                ),
                if (_notice case final notice?) ...[
                  const SizedBox(height: 20),
                  AppNotice(tone: AppNoticeTone.info, message: notice),
                ],
                if (generalError != null) ...[
                  const SizedBox(height: 20),
                  AppNotice(tone: AppNoticeTone.error, message: generalError),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(
                    _submitting
                        ? 'Guardando...'
                        : (_isEdit ? 'Guardar cambios' : 'Crear lote'),
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
