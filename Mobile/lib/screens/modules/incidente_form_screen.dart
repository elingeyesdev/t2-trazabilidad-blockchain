import 'package:flutter/material.dart';

import '../../models/api_exception.dart';
import '../../models/auth_user.dart';
import '../../models/incidente_models.dart';
import '../../services/module_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/field_kit.dart';
import '../../widgets/form_validation.dart';
import 'module_access_denied.dart';

class IncidenteFormScreen extends StatefulWidget {
  const IncidenteFormScreen({
    super.key,
    required this.args,
    required this.user,
    required this.service,
    required this.onRefreshPermissions,
  });

  final IncidenteFormArgs args;
  final AuthUser user;
  final ModuleService service;
  final VoidCallback onRefreshPermissions;

  @override
  State<IncidenteFormScreen> createState() => _IncidenteFormScreenState();
}

class _IncidenteFormScreenState extends State<IncidenteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tipoCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _responsableCtrl = TextEditingController();

  bool _submitting = false;
  ApiException? _submitError;

  @override
  void dispose() {
    _tipoCtrl.dispose();
    _descripcionCtrl.dispose();
    _responsableCtrl.dispose();
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

  Future<void> _submit() async {
    if (_submitting) return;
    if (!validateForm(_formKey)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final responsableId = int.tryParse(_responsableCtrl.text.trim());
      final created = await widget.service.createIncidente(
        widget.user,
        afectadoTipo: widget.args.afectadoTipo,
        afectadoId: widget.args.afectadoId,
        tipo: _tipoCtrl.text.trim(),
        descripcion: _descripcionCtrl.text.trim(),
        responsableUsuarioId: responsableId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
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
          'No se pudo registrar la incidencia. Tus datos se conservaron para reintentar.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!IncidentePermissions.canCreate(widget.user)) {
      return ModuleAccessDenied(
        title: 'Reportar incidencia',
        onRefreshPermissions: widget.onRefreshPermissions,
      );
    }

    final scrollPadding = formScrollPadding(context);
    final generalError =
        _submitError != null &&
            (_submitError!.validationErrors.isEmpty ||
                _submitError!.validationErrors.keys.any(
                  (k) => !const {
                    'tipo',
                    'descripcion',
                    'responsable_usuarioid',
                  }.contains(k),
                ))
        ? _submitError!.message
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Reportar incidencia')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.maizeSoft,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: AppTheme.ink, width: 2),
                      ),
                      child: DetailField(
                        label: 'Operación vinculada',
                        value: widget.args.referenciaLabel,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const SectionTitle('Detalle del problema'),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('incidente.tipo'),
                      controller: _tipoCtrl,
                      scrollPadding: scrollPadding,
                      enabled: !_submitting,
                      maxLength: 100,
                      forceErrorText: _fieldError('tipo'),
                      decoration: const InputDecoration(
                        labelText: 'Tipo de problema (ej. Daño en empaque)',
                        prefixIcon: Icon(Icons.report_problem_outlined),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Indica el tipo de incidencia.';
                        }
                        return null;
                      },
                      onChanged: (_) => _clearError(field: 'tipo'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('incidente.descripcion'),
                      controller: _descripcionCtrl,
                      scrollPadding: scrollPadding,
                      enabled: !_submitting,
                      maxLines: 4,
                      maxLength: 3000,
                      forceErrorText: _fieldError('descripcion'),
                      decoration: const InputDecoration(
                        labelText: 'Descripción de la incidencia',
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Describe el problema ocurrido.';
                        }
                        return null;
                      },
                      onChanged: (_) => _clearError(field: 'descripcion'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('incidente.responsable'),
                      controller: _responsableCtrl,
                      scrollPadding: scrollPadding,
                      enabled: !_submitting,
                      keyboardType: TextInputType.number,
                      forceErrorText: _fieldError('responsable_usuarioid'),
                      decoration: const InputDecoration(
                        labelText: 'ID de responsable de atención (opcional)',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      onChanged: (_) =>
                          _clearError(field: 'responsable_usuarioid'),
                    ),
                    if (generalError != null) ...[
                      const SizedBox(height: 14),
                      AppNotice(
                        tone: AppNoticeTone.error,
                        message: generalError,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const ValueKey('incidente.guardar'),
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _submitting
                            ? 'Enviando reporte...'
                            : 'Enviar incidencia',
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
}
