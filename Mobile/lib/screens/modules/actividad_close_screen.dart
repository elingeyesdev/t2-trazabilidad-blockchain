import 'dart:async';

import 'package:file_selector/file_selector.dart';
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
  });

  final int actividadId;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;
  final ActividadEditableData? initialData;
  final Future<XFile?> Function()? capturePhoto;
  final Future<XFile?> Function()? selectFile;

  @override
  State<ActividadCloseScreen> createState() => _ActividadCloseScreenState();
}

class _ActividadCloseScreenState extends State<ActividadCloseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _resultController = TextEditingController();

  ActividadEditableData? _actividad;
  EvidencePhoto? _photo;
  bool _loading = false;
  bool _picking = false;
  bool _submitting = false;
  String? _loadError;
  String? _photoError;
  String? _cameraPermissionMessage;
  ApiException? _submitError;

  @override
  void initState() {
    super.initState();
    _actividad = widget.initialData;
    if (_actividad == null) {
      unawaited(_loadActivity());
    }
  }

  @override
  void dispose() {
    _resultController.dispose();
    super.dispose();
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
      final capture = widget.capturePhoto;
      if (capture == null) {
        throw const CameraPermissionException();
      }
      final picked = await _readPhoto(await capture());
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
      final file =
          await (widget.selectFile?.call() ??
              openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(
                    label: 'Fotografías',
                    extensions: ['jpg', 'jpeg', 'png', 'webp'],
                    mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
                    uniformTypeIdentifiers: [
                      'public.jpeg',
                      'public.png',
                      'org.webmproject.webp',
                    ],
                  ),
                ],
              ));
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
      _resultController.text.trim().isNotEmpty || _photo != null;

  Future<void> _cancel() async {
    if (_submitting) return;
    if (_hasUnsavedChanges) {
      final discard = await confirmImportantAction(
        context,
        icon: Icons.warning_amber_rounded,
        title: '¿Descartar cierre?',
        message:
            'Tienes el resultado o la fotografía sin enviar. Si sales ahora, la actividad seguirá pendiente.',
        cancelLabel: 'Seguir editando',
        confirmLabel: 'Descartar',
        destructive: true,
      );
      if (!mounted || !discard) return;
    }
    Navigator.of(context).pop();
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
    if (!validForm || photo == null) {
      return;
    }

    final resultText = _resultController.text.trim();
    final confirmed = await confirmImportantAction(
      context,
      icon: Icons.task_alt_rounded,
      title: '¿Confirmar cierre de actividad?',
      message:
          'Una vez cerrada, la actividad quedará completada con su fotografía y resultado.',
      details: [
        if (_actividad != null) 'Actividad: ${_actividad!.description}',
        'Resultado: $resultText',
        'Evidencia: ${photo.originalName}',
      ],
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
    const mappedFields = {'resultado', 'evidencia_foto'};
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
                  _actividad?.description ?? 'Actividad #${widget.actividadId}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Describe el resultado del trabajo y adjunta una fotografía de evidencia antes de confirmar el cierre.',
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
}
