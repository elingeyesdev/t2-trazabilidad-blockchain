import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/actividad_models.dart';
import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/module_page.dart';
import '../../navigation/app_module.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_error_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/camera_permission_notice.dart';
import '../../widgets/form_validation.dart';
import 'module_access_denied.dart';

class ActividadCloseResult {
  const ActividadCloseResult({required this.record});

  final ModuleRecord record;
}

class ActividadCloseScreen extends StatefulWidget {
  const ActividadCloseScreen({
    super.key,
    required this.actividadId,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
    this.initialData,
    this.capturePhoto,
    this.selectFile,
    this.onExternalPicker,
  });

  final int actividadId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final ActividadEditableData? initialData;
  final Future<XFile?> Function()? capturePhoto;
  final Future<XFile?> Function()? selectFile;
  final Future<XFile?> Function(Future<XFile?> Function() action)?
  onExternalPicker;

  @override
  State<ActividadCloseScreen> createState() => _ActividadCloseScreenState();
}

class _ConsumoDraft {
  _ConsumoDraft({
    this.almacenId,
    this.insumoId,
    String? initialQuantity,
    this.locked = false,
    this.lockedName,
    this.lockedUnit,
    this.lockedUnidadMedidaId,
    this.lockedTitle,
    this.lockedHint,
  }) : quantityController = TextEditingController(text: initialQuantity ?? '');

  int? almacenId;
  int? insumoId;
  final bool locked;
  final String? lockedName;
  final String? lockedUnit;
  final int? lockedUnidadMedidaId;
  final String? lockedTitle;
  final String? lockedHint;
  final TextEditingController quantityController;

  void dispose() => quantityController.dispose();
}

class _ActividadCloseScreenState extends State<ActividadCloseScreen> {
  static const _maxConsumos = 10;

  final _formKey = GlobalKey<FormState>();
  final _resultController = TextEditingController();
  final List<_ConsumoDraft> _consumos = [];

  ActividadEditableData? _actividad;
  EvidencePhoto? _photo;
  List<AlmacenOption> _almacenes = const [];
  List<InsumoOption> _insumos = const [];
  bool _loading = false;
  bool _loadingInventory = false;
  bool _picking = false;
  bool _submitting = false;
  String? _loadError;
  String? _inventoryError;
  String? _consumosError;
  String? _photoError;
  String? _cameraPermissionMessage;
  ApiException? _submitError;

  bool get _canSelectInventory =>
      widget.user.permissions.contains(AppModule.insumos.permission) &&
      widget.user.permissions.contains(AppModule.almacenes.permission);

  bool get _showInsumosSection =>
      (_canSelectInventory || (_actividad?.hasPlannedInsumos ?? false)) &&
      !(_actividad?.hidesInsumos ?? false);

  @override
  void initState() {
    super.initState();
    _actividad = widget.initialData;
    _ensureLockedSeedDraft();
    if (_actividad == null) {
      unawaited(_loadActivity());
    }
    if (_canSelectInventory && !(_actividad?.hidesInsumos ?? false)) {
      unawaited(_loadInventoryOptions());
    }
    if (widget.capturePhoto == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_recoverLostAndroidPhoto());
    }
  }

  Future<void> _recoverLostAndroidPhoto() async {
    final lost = await retrieveLostCameraPhoto();
    if (!mounted || lost == null || _photo != null) return;
    try {
      final picked = await _readPhoto(lost);
      if (!mounted || picked == null) return;
      setState(() {
        _photo = picked;
        _photoError = null;
        _cameraPermissionMessage = null;
      });
      _clearError(field: 'evidencia_foto');
    } catch (_) {}
  }

  Future<XFile?> _runPicker(Future<XFile?> Function() action) {
    final wrapper = widget.onExternalPicker;
    return wrapper != null ? wrapper(action) : action();
  }

  @override
  void dispose() {
    _resultController.dispose();
    for (final item in _consumos) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInventoryOptions() async {
    setState(() {
      _loadingInventory = true;
      _inventoryError = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.service.loadAlmacenOptions(widget.user),
        widget.service.loadInsumoOptions(widget.user),
      ]);
      if (!mounted) return;
      final almacenes = results[0] as List<AlmacenOption>;
      final almacenIds = almacenes.map((a) => a.id).toSet();
      final rawInsumos = results[1] as List<InsumoOption>;
      // Excluye insumos legacy sin almacén, almacenes ajenos y productos sin stock (> 0).
      final insumos = rawInsumos
          .where(
            (item) =>
                item.almacenId != null &&
                almacenIds.contains(item.almacenId) &&
                item.stock > 0,
          )
          .toList();
      setState(() {
        _almacenes = almacenes;
        _insumos = insumos;
        _loadingInventory = false;
        _ensureLockedSeedDraft();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingInventory = false;
        _inventoryError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingInventory = false;
        _inventoryError =
            'No se pudieron cargar los almacenes e insumos disponibles.';
      });
    }
  }

  AlmacenOption? _almacenById(int? id) {
    if (id == null) return null;
    for (final item in _almacenes) {
      if (item.id == id) return item;
    }
    return null;
  }

  InsumoOption? _insumoById(int? id) {
    if (id == null) return null;
    for (final item in _insumos) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool _matchesActivityCategory(InsumoOption item) {
    final tipoAct = (_actividad?.tipoNombre ?? '').toLowerCase();
    final tipoIns = (item.tipoNombre ?? '').toLowerCase();
    if (tipoAct.isEmpty || tipoIns.isEmpty) return true;

    final isSeed =
        tipoIns.contains('siembra') || tipoIns.contains('semilla');
    final isPest =
        tipoIns.contains('plaga') ||
        tipoIns.contains('pesticid') ||
        tipoIns.contains('fungic') ||
        tipoIns.contains('insect') ||
        tipoIns.contains('herbic');

    if (tipoAct.contains('siembra')) {
      return isSeed;
    }
    if (tipoAct.contains('plaga') ||
        tipoAct.contains('fumig') ||
        tipoAct.contains('fitosanit')) {
      return isPest;
    }
    if (tipoAct.contains('fertiliz')) {
      return !isSeed && !isPest;
    }
    return true;
  }

  List<InsumoOption> _insumosForAlmacen(int? almacenId) {
    if (almacenId == null) return const [];
    final inAlmacen = _insumos
        .where(
          (item) =>
              item.almacenId != null &&
              item.almacenId == almacenId &&
              item.stock > 0,
        )
        .toList();
    return inAlmacen.where(_matchesActivityCategory).toList();
  }

  void _ensureLockedSeedDraft() {
    final act = _actividad;
    if (act == null) return;
    if (act.hasLockedSeed) {
      final seedId = act.plannedSeedInsumoId!;
      if (_consumos.any((c) => c.locked && c.insumoId == seedId)) return;
      final seedInsumo = _insumoById(seedId);
      final almacenId =
          seedInsumo?.almacenId ??
          act.plannedSeedAlmacenId ??
          (_almacenes.length == 1 ? _almacenes.first.id : null);
      if (almacenId == null) return;
      for (final existing in _consumos) {
        existing.dispose();
      }
      _consumos
        ..clear()
        ..add(
          _ConsumoDraft(
            almacenId: almacenId,
            insumoId: seedId,
            initialQuantity: act.plannedSeedQuantity,
            locked: true,
            lockedName: act.plannedSeedName,
            lockedUnit: act.plannedSeedUnit,
            lockedTitle: 'Semilla planificada del lote',
            lockedHint:
                'Esta semilla fue elegida al crear el lote y no puede cambiarse. Solo confirma la cantidad real utilizada.',
          ),
        );
      return;
    }

    if (act.hasPlannedInsumos) {
      final expectedIds = act.plannedInsumos.map((e) => e.insumoId).toSet();
      final alreadyPopulated =
          _consumos.length == act.plannedInsumos.length &&
          _consumos.every(
            (c) => c.locked && c.insumoId != null && expectedIds.contains(c.insumoId),
          );
      if (alreadyPopulated) {
        for (final draft in _consumos) {
          draft.almacenId ??=
              _insumoById(draft.insumoId)?.almacenId ??
              (_almacenes.length == 1 ? _almacenes.first.id : null);
        }
        return;
      }
      for (final existing in _consumos) {
        existing.dispose();
      }
      _consumos.clear();
      for (final item in act.plannedInsumos) {
        final matchedInsumo = _insumoById(item.insumoId);
        final almacenId =
            item.almacenId ??
            matchedInsumo?.almacenId ??
            (_almacenes.length == 1 ? _almacenes.first.id : null);
        _consumos.add(
          _ConsumoDraft(
            almacenId: almacenId,
            insumoId: item.insumoId,
            initialQuantity: item.cantidad > 0
                ? formatQuantity(item.cantidad)
                : null,
            locked: true,
            lockedName: item.name,
            lockedUnit: item.unitLabel,
            lockedUnidadMedidaId: item.unidadMedidaId,
            lockedTitle: 'Insumo asignado para esta actividad',
            lockedHint:
                'Este insumo fue elegido al asignar la actividad. Solo confirma la cantidad real utilizada.',
          ),
        );
      }
    }
  }

  void _addConsumo() {
    if (_submitting || _consumos.length >= _maxConsumos) return;
    final defaultAlmacenId = _almacenes.length == 1
        ? _almacenes.first.id
        : null;
    setState(() {
      _consumos.add(_ConsumoDraft(almacenId: defaultAlmacenId));
      _consumosError = null;
    });
    _clearError(field: 'consumos');
  }

  void _removeConsumo(int index) {
    if (_submitting || index < 0 || index >= _consumos.length) return;
    setState(() {
      final removed = _consumos.removeAt(index);
      removed.dispose();
    });
    _clearError();
  }

  Future<void> _loadActivity() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final record = await widget.service.loadDetail(
        AppModule.actividades,
        widget.user,
        widget.actividadId,
      );
      if (!mounted) return;
      setState(() {
        _actividad = record.actividadData;
        _loading = false;
        _ensureLockedSeedDraft();
      });
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
        _loadError = 'No se pudo cargar la información de la actividad.';
      });
    }
  }

  Future<EvidencePhoto?> _readPhoto(XFile? file) async {
    if (file == null) return null;
    if (await file.length() > EvidencePhoto.maxBytes) {
      throw const ApiException('Selecciona una imagen de hasta 5 MB.');
    }
    return EvidencePhoto(await file.readAsBytes(), name: file.name);
  }

  Future<void> _captureFromCamera() async {
    if (_picking || _submitting) return;
    setState(() {
      _picking = true;
      _photoError = null;
      _cameraPermissionMessage = null;
    });
    try {
      final capture = widget.capturePhoto ?? captureCameraPhoto;
      final picked = await _readPhoto(await _runPicker(capture));
      if (!mounted || picked == null) return;
      setState(() {
        _photo = picked;
        _photoError = null;
        _cameraPermissionMessage = null;
      });
      _clearError(field: 'evidencia_foto');
    } catch (error) {
      if (!mounted) return;
      if (CameraPermissionException.isPermissionError(error)) {
        setState(() {
          _cameraPermissionMessage = CameraPermissionException.messageFor(
            error,
          );
        });
      } else if (error is ApiException) {
        setState(() => _photoError = error.message);
      } else {
        setState(() {
          _photoError = 'No se pudo tomar la fotografía. Intenta de nuevo.';
        });
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _selectFromDevice() async {
    if (_picking || _submitting) return;
    setState(() {
      _picking = true;
      _photoError = null;
    });
    try {
      final file = await _runPicker(
        () =>
            widget.selectFile?.call() ??
            openFile(
              acceptedTypeGroups: const [
                XTypeGroup(
                  label: 'Fotografías',
                  extensions: ['jpg', 'jpeg', 'png', 'webp'],
                  mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
                  uniformTypeIdentifiers: [
                    'public.jpeg',
                    'public.png',
                    'public.webp',
                    'org.webmproject.webp',
                  ],
                ),
              ],
            ),
      );
      final picked = await _readPhoto(file);
      if (!mounted || picked == null) return;
      setState(() {
        _photo = picked;
        _photoError = null;
        _cameraPermissionMessage = null;
      });
      _clearError(field: 'evidencia_foto');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _photoError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _photoError =
            'No se pudo abrir o leer la imagen seleccionada. Intenta de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
      _resultController.text.trim().isNotEmpty ||
      _photo != null ||
      _consumos.isNotEmpty;

  Future<void> _cancel() async {
    if (_submitting) return;
    if (_hasUnsavedChanges) {
      final discard = await confirmImportantAction(
        context,
        icon: Icons.warning_amber_rounded,
        title: '¿Descartar cierre?',
        message:
            'Tienes el resultado, insumos o la fotografía sin enviar. Si sales ahora, la actividad seguirá pendiente.',
        cancelLabel: 'Seguir editando',
        confirmLabel: 'Descartar',
        destructive: true,
      );
      if (!mounted || !discard) return;
    }
    Navigator.of(context).pop();
  }

  List<ActividadConsumoInput> _buildConsumoInputs() {
    final result = <ActividadConsumoInput>[];
    for (final draft in _consumos) {
      final almacenId = draft.almacenId;
      final insumoId = draft.insumoId;
      final parsed = parseQuantityInput(draft.quantityController.text);
      if (almacenId == null || insumoId == null || parsed == null) continue;
      final insumo = _insumoById(insumoId);
      result.add(
        ActividadConsumoInput(
          insumoId: insumoId,
          almacenId: almacenId,
          quantityText: formatQuantity(parsed),
          unidadMedidaId: insumo?.unidadMedidaId ?? draft.lockedUnidadMedidaId,
        ),
      );
    }
    return result;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final validForm = validateForm(_formKey);
    final photo = _photo;
    if (photo == null) {
      setState(() {
        _photoError = 'Toma o selecciona una fotografía de evidencia.';
      });
    }
    final missingRequiredInsumo =
        _showInsumosSection &&
        (_actividad?.requiresInsumos ?? false) &&
        _consumos.isEmpty;
    if (missingRequiredInsumo) {
      setState(() {
        _consumosError =
            'Debes agregar al menos un insumo utilizado para cerrar esta actividad.';
      });
    } else if (_consumosError != null) {
      setState(() => _consumosError = null);
    }
    if (!validForm || photo == null || missingRequiredInsumo) {
      return;
    }

    final resultText = _resultController.text.trim();
    final consumoInputs = _showInsumosSection
        ? _buildConsumoInputs()
        : const <ActividadConsumoInput>[];
    final details = <String>[
      if (_actividad != null) 'Actividad: ${_actividad!.description}',
      'Resultado: $resultText',
      for (final item in consumoInputs)
        'Insumo: ${_insumoById(item.insumoId)?.name ?? 'Insumo #${item.insumoId}'} (${item.quantityText} ${_insumoById(item.insumoId)?.unitLabel ?? ''})'
            .trim(),
      'Evidencia: ${photo.originalName}',
    ];
    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.task_alt_rounded,
      title: '¿Confirmar cierre de actividad?',
      message:
          'Una vez cerrada, la actividad quedará completada con su fotografía, resultado y consumos registrados.',
      details: details,
      confirmLabel: 'Confirmar cierre',
    );
    if (!mounted || !confirmed) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
      _photoError = null;
    });

    try {
      final closed = await widget.service.closeActividad(
        widget.user,
        widget.actividadId,
        result: resultText,
        photo: photo,
        consumos: consumoInputs.map((item) => item.toPayload()).toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(ActividadCloseResult(record: closed));
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
          'No se pudo enviar el cierre. Tus datos y la fotografía se conservaron para reintentar.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading &&
        _loadError == null &&
        _actividad != null &&
        !_actividad!.isCompleted &&
        !ActividadPermissions.canClose(widget.user, _actividad)) {
      return ModuleAccessDenied(
        title: 'Cerrar actividad',
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
          title: const Text('Cerrar actividad'),
        ),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const AppLoading(message: 'Cargando actividad...');
    }
    if (_loadError case final error?) {
      return AppErrorState(message: error, onRetry: _loadActivity);
    }
    if (_actividad?.isCompleted == true) {
      return AppEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Actividad ya completada',
        message:
            'Esta actividad ya fue cerrada y cuenta con su registro final.',
        action: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Volver al detalle'),
        ),
      );
    }

    final busy = _submitting || _picking;
    final scrollPadding = formScrollPadding(context);
    final photoValidationError = _photoError ?? _fieldError('evidencia_foto');
    final mappedFields = <String>{
      'resultado',
      'evidencia_foto',
      'consumos',
      for (var i = 0; i < _consumos.length; i++) ...[
        'consumos.$i.almacenid',
        'consumos.$i.insumoid',
        'consumos.$i.cantidad',
        'consumos.$i.unidadmedidaid',
      ],
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
    final consumosGeneralError = _fieldError('consumos');
    final hasConsumoServerError =
        error != null &&
        error.validationErrors.keys.any((key) => key.startsWith('consumos'));

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
                  _actividad?.description ?? 'Actividad #${widget.actividadId}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Describe el resultado del trabajo, registra los insumos utilizados si corresponde y adjunta una fotografía de evidencia antes de confirmar el cierre.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('actividad.resultado'),
                  controller: _resultController,
                  scrollPadding: scrollPadding,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  forceErrorText: _fieldError('resultado'),
                  enabled: !_submitting,
                  maxLines: 3,
                  maxLength: 250,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Resultado de la actividad',
                    hintText:
                        'Ej. Aplicación uniforme realizada en todo el lote',
                    prefixIcon: Icon(Icons.fact_check_outlined),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Describe el resultado de la actividad.';
                    }
                    if (text.length > 250) {
                      return 'El resultado no puede superar 250 caracteres.';
                    }
                    return null;
                  },
                  onChanged: (_) => _clearError(field: 'resultado'),
                ),
                if (_showInsumosSection) ...[
                  const SizedBox(height: 24),
                  const Divider(color: AppTheme.line),
                  const SizedBox(height: 16),
                  _buildConsumosSection(
                    context,
                    scrollPadding: scrollPadding,
                    consumosGeneralError:
                        _consumosError ?? consumosGeneralError,
                    hasConsumoServerError: hasConsumoServerError,
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(color: AppTheme.line),
                const SizedBox(height: 16),
                Text(
                  'Fotografía de evidencia',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'JPG, PNG o WebP, hasta 5 MB. Revísala antes de confirmar.',
                ),
                const SizedBox(height: 16),
                if (_photo case final photo?) ...[
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(
                        photo.bytes,
                        width: 240,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 240,
                          height: 180,
                          child: Icon(Icons.broken_image_outlined, size: 64),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    photo.originalName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _photo = null;
                            _photoError = null;
                          }),
                    child: const Text('Quitar fotografía'),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : _captureFromCamera,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(
                        _photo == null ? 'Tomar foto' : 'Tomar otra foto',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _selectFromDevice,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        _photo == null
                            ? 'Seleccionar imagen'
                            : 'Cambiar imagen',
                      ),
                    ),
                  ],
                ),
                if (_cameraPermissionMessage case final camMsg?) ...[
                  const SizedBox(height: 16),
                  CameraPermissionNotice(
                    message: camMsg,
                    alternativeLabel: 'Elegir imagen del dispositivo',
                    onUseAlternative: busy ? null : _selectFromDevice,
                  ),
                ],
                if (photoValidationError != null) ...[
                  const SizedBox(height: 16),
                  AppNotice(
                    tone: AppNoticeTone.error,
                    message: photoValidationError,
                  ),
                ],
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
                      : const Icon(Icons.task_alt_rounded),
                  label: Text(
                    _submitting ? 'Cerrando actividad...' : 'Cerrar actividad',
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

  Widget _buildConsumosSection(
    BuildContext context, {
    required EdgeInsets scrollPadding,
    required String? consumosGeneralError,
    required bool hasConsumoServerError,
  }) {
    final canAddMore =
        !_submitting &&
        !_loadingInventory &&
        _almacenes.isNotEmpty &&
        _insumos.isNotEmpty &&
        _consumos.length < _maxConsumos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Insumos utilizados',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!_loadingInventory &&
                (_inventoryError != null || hasConsumoServerError))
              TextButton.icon(
                onPressed: _submitting ? null : _loadInventoryOptions,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Actualizar existencias'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          (_actividad?.requiresInsumos ?? false)
              ? 'Obligatorio para esta actividad. Selecciona el almacén autorizado, el insumo con stock y la cantidad real utilizada.'
              : 'Selecciona el almacén autorizado, el insumo y la cantidad real utilizada con su unidad.',
        ),
        const SizedBox(height: 12),
        if (_loadingInventory)
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
                Expanded(
                  child: Text('Cargando almacenes e insumos disponibles...'),
                ),
              ],
            ),
          )
        else if (_inventoryError case final invError?)
          AppNotice(tone: AppNoticeTone.error, message: invError)
        else if ((_almacenes.isEmpty ||
                _insumos.where(_matchesActivityCategory).isEmpty) &&
            _actividad?.hasLockedInsumos != true)
          const AppNotice(
            tone: AppNoticeTone.info,
            message:
                'No hay insumos de este tipo con stock disponible en tu almacén agrícola. Carga existencias en Inventario antes de cerrar esta actividad.',
          )
        else ...[
          for (var i = 0; i < _consumos.length; i++) ...[
            _buildConsumoCard(context, i, scrollPadding: scrollPadding),
            const SizedBox(height: 14),
          ],
          if (_actividad?.hasLockedInsumos != true)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('consumos.add'),
                onPressed: canAddMore ? _addConsumo : null,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: Text(
                  _consumos.isEmpty ? 'Agregar insumo' : 'Agregar otro insumo',
                ),
              ),
            ),
        ],
        if (consumosGeneralError != null) ...[
          const SizedBox(height: 12),
          AppNotice(tone: AppNoticeTone.error, message: consumosGeneralError),
        ],
      ],
    );
  }

  Widget _buildConsumoCard(
    BuildContext context,
    int index, {
    required EdgeInsets scrollPadding,
  }) {
    final draft = _consumos[index];
    final selectedAlmacen = _almacenById(draft.almacenId);
    final availableInsumos = _insumosForAlmacen(draft.almacenId);
    final selectedInsumo = _insumoById(draft.insumoId);
    final parsedQty = parseQuantityInput(draft.quantityController.text);
    final availableScaled = selectedInsumo == null
        ? null
        : (selectedInsumo.stock * 1000).round();
    final requestedScaled = parsedQty == null
        ? null
        : (parsedQty * 1000).round();
    final exceedsStock =
        selectedInsumo != null &&
        requestedScaled != null &&
        availableScaled != null &&
        requestedScaled > availableScaled;
    final remaining =
        selectedInsumo != null &&
            requestedScaled != null &&
            availableScaled != null &&
            !exceedsStock
        ? (availableScaled - requestedScaled) / 1000
        : null;

    return Container(
      key: ValueKey('consumo.$index.card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: exceedsStock ? AppTheme.clay : AppTheme.ink,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.locked
                      ? (draft.lockedTitle ?? 'Insumo asignado')
                      : 'Consumo #${index + 1}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (!draft.locked)
                IconButton(
                  key: ValueKey('consumo.$index.remove'),
                  tooltip: 'Quitar insumo',
                  onPressed: _submitting ? null : () => _removeConsumo(index),
                  icon: const Icon(Icons.delete_outline_rounded),
                )
              else
                const Icon(Icons.lock_outline_rounded, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          if (draft.locked) ...[
            if (draft.almacenId != null) ...[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Almacén autorizado',
                  prefixIcon: Icon(Icons.warehouse_outlined),
                ),
                child: Text(
                  selectedAlmacen?.displayLabel ??
                      'Almacén #${draft.almacenId}',
                ),
              ),
              const SizedBox(height: 14),
            ],
            InputDecorator(
              key: ValueKey('consumo.$index.insumo_locked'),
              decoration: InputDecoration(
                labelText: _actividad?.hasLockedSeed == true
                    ? 'Semilla fijada al crear el lote'
                    : 'Insumo asignado',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
              child: Text(
                selectedInsumo?.displayLabel ??
                    draft.lockedName ??
                    _actividad?.plannedSeedName ??
                    'Insumo #${draft.insumoId}',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              draft.lockedHint ??
                  'Este insumo fue asignado previamente y no puede cambiarse. Solo confirma la cantidad real utilizada.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            DropdownButtonFormField<int>(
              key: ValueKey('consumo.$index.almacen'),
              initialValue: selectedAlmacen?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Almacén autorizado',
                prefixIcon: Icon(Icons.warehouse_outlined),
              ),
              forceErrorText: _fieldError('consumos.$index.almacenid'),
              items: [
                for (final almacen in _almacenes)
                  DropdownMenuItem(
                    value: almacen.id,
                    child: Text(
                      almacen.displayLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (value) {
                      setState(() {
                        draft.almacenId = value;
                        final currentInsumo = _insumoById(draft.insumoId);
                        if (currentInsumo != null &&
                            currentInsumo.almacenId != value) {
                          draft.insumoId = null;
                        }
                      });
                      _clearError(field: 'consumos.$index.almacenid');
                    },
              validator: (value) =>
                  value == null ? 'Selecciona el almacén autorizado.' : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              key: ValueKey('consumo.$index.insumo'),
              initialValue: availableInsumos.any((i) => i.id == draft.insumoId)
                  ? draft.insumoId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Insumo',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              forceErrorText: _fieldError('consumos.$index.insumoid'),
              items: [
                for (final insumo in availableInsumos)
                  DropdownMenuItem(
                    value: insumo.id,
                    child: Text(
                      insumo.displayLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (value) {
                      setState(() {
                        draft.insumoId = value;
                        final chosen = _insumoById(value);
                        if (draft.almacenId == null &&
                            chosen?.almacenId != null &&
                            _almacenById(chosen!.almacenId) != null) {
                          draft.almacenId = chosen.almacenId;
                        }
                      });
                      _clearError(field: 'consumos.$index.insumoid');
                    },
              validator: (value) {
                if (value == null) return 'Selecciona el insumo utilizado.';
                final duplicateCount = _consumos
                    .where((item) => item.insumoId == value)
                    .length;
                if (duplicateCount > 1) {
                  return 'No repitas el mismo insumo; indica su cantidad total en una sola línea.';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 14),
          TextFormField(
            key: ValueKey('consumo.$index.cantidad'),
            controller: draft.quantityController,
            scrollPadding: scrollPadding,
            enabled: !_submitting,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            forceErrorText:
                _fieldError('consumos.$index.cantidad') ??
                _fieldError('consumos.$index.unidadmedidaid'),
            decoration: InputDecoration(
              labelText: 'Cantidad utilizada',
              hintText: 'Ej. 2.5',
              prefixIcon: const Icon(Icons.scale_outlined),
              suffixText: selectedInsumo?.unitLabel ?? draft.lockedUnit,
            ),
            validator: (value) {
              if (selectedInsumo == null) {
                final parsed = parseQuantityInput(value ?? '');
                if (parsed == null) {
                  return 'Indica una cantidad positiva con hasta tres decimales.';
                }
                return null;
              }
              return validateConsumptionQuantity(
                value,
                availableStock: selectedInsumo.stock,
                unitLabel: selectedInsumo.unitLabel,
              );
            },
            onChanged: (_) {
              setState(() {});
              _clearError(field: 'consumos.$index.cantidad');
              _clearError(field: 'consumos.$index.unidadmedidaid');
            },
          ),
          if (selectedInsumo != null) ...[
            const SizedBox(height: 12),
            Text(
              'Disponible: ${selectedInsumo.formattedStock}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (remaining != null && parsedQty != null) ...[
              const SizedBox(height: 4),
              Text(
                'Utilizado: ${formatQuantity(parsedQty)} ${selectedInsumo.unitLabel} · Restante: ${formatQuantity(remaining)} ${selectedInsumo.unitLabel}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.forest,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ] else if (exceedsStock && parsedQty != null) ...[
              const SizedBox(height: 10),
              AppNotice(
                tone: AppNoticeTone.error,
                message:
                    'Existencias insuficientes: solicitaste ${formatQuantity(parsedQty)} ${selectedInsumo.unitLabel}, pero solo hay ${selectedInsumo.formattedStock} disponibles. Corrige la cantidad.',
              ),
            ],
          ],
        ],
      ),
    );
  }
}
