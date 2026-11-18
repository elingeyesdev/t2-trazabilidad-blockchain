import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/auth_controller.dart';
import '../../models/registration_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/form_validation.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fields = {
    for (final name in [
      'nombre',
      'apellido',
      'email',
      'nombreusuario',
      'telefono',
      'password',
      'password_confirmation',
    ])
      name: TextEditingController(),
  };
  final _visiblePasswords = <String>{};
  RegistrationResult? _result;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _leave() {
    widget.controller.clearError();
    Navigator.of(context).pop(_result);
  }

  Future<void> _submit() async {
    if (widget.controller.isSubmitting || !validateForm(_formKey)) {
      return;
    }
    FocusScope.of(context).unfocus();
    final result = await widget.controller.register(
      name: _fields['nombre']!.text,
      lastName: _fields['apellido']!.text,
      email: _fields['email']!.text,
      username: _fields['nombreusuario']!.text,
      phone: _fields['telefono']!.text,
      password: _fields['password']!.text,
    );
    if (!mounted) return;
    if (result == null) {
      revealFormErrors(_formKey);
      return;
    }
    _fields['password']!.clear();
    _fields['password_confirmation']!.clear();
    TextInput.finishAutofillContext(shouldSave: false);
    setState(() => _result = result);
  }

  Widget _field(
    String name,
    String label, {
    bool optional = false,
    bool secret = false,
    TextInputType? keyboard,
    List<String>? autofillHints,
    String? helperText,
    String? Function(String?)? validator,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    final messages = widget.controller.error?.validationErrors[name];
    final visible = _visiblePasswords.contains(name);
    final busy = widget.controller.isSubmitting;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        key: ValueKey('register.$name'),
        controller: _fields[name],
        scrollPadding: formScrollPadding(context),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        forceErrorText: messages == null || messages.isEmpty
            ? null
            : messages.join('\n'),
        enabled: !busy,
        keyboardType: keyboard,
        autofillHints: autofillHints,
        autocorrect: false,
        enableSuggestions: !secret,
        textCapitalization: capitalization,
        obscureText: secret && !visible,
        textInputAction: name == 'password_confirmation'
            ? TextInputAction.done
            : TextInputAction.next,
        onFieldSubmitted: name == 'password_confirmation'
            ? (_) => _submit()
            : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          errorMaxLines: 3,
          suffixIcon: secret
              ? IconButton(
                  tooltip:
                      '${visible ? 'Ocultar' : 'Mostrar'} ${label.toLowerCase()}',
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          if (visible) {
                            _visiblePasswords.remove(name);
                          } else {
                            _visiblePasswords.add(name);
                          }
                        }),
                  icon: Icon(
                    visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                )
              : null,
        ),
        validator:
            validator ??
            (value) {
              if (optional) return null;
              if (name == 'email') return validateEmail(value);
              final input = secret ? value ?? '' : value?.trim() ?? '';
              if (input.isEmpty) {
                return switch (name) {
                  'nombre' => 'Ingresa tu nombre.',
                  'apellido' => 'Ingresa tu apellido.',
                  'nombreusuario' => 'Ingresa un nombre de usuario.',
                  _ => 'Ingresa tu contraseña.',
                };
              }
              if (name == 'password' && input.runes.length < 6) {
                return 'Usa una contraseña de al menos 6 caracteres.';
              }
              return null;
            },
        onChanged: (_) => widget.controller.clearError(field: name),
      ),
    );
  }

  Widget _confirmation(RegistrationResult result) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppTheme.sage,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  size: 48,
                  color: AppTheme.forest,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Solicitud enviada',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(result.email, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              AppNotice(
                tone: AppNoticeTone.success,
                message: result.message,
              ),
              const SizedBox(height: 12),
              const Text(
                'Podrás iniciar sesión cuando un administrador apruebe tu cuenta.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              const Divider(color: AppTheme.line),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _leave,
                child: const Text('Volver al inicio de sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.isSubmitting;
        final result = _result;
        final error = widget.controller.error;
        final message =
            error != null &&
                (error.validationErrors.isEmpty ||
                    error.validationErrors.keys.any(
                      (name) => !_fields.containsKey(name),
                    ))
            ? error.message
            : null;
        return PopScope(
          canPop: !busy,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Crear cuenta'),
              leading: IconButton(
                tooltip: 'Volver',
                onPressed: busy ? null : _leave,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            body: SafeArea(
              child: result != null
                  ? _confirmation(result)
                  : Center(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: formContentPadding(context),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: AutofillGroup(
                            onDisposeAction: AutofillContextAction.cancel,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const BrandWordmark(),
                                  const SizedBox(height: 32),
                                  Text(
                                    'Todo empieza en el campo.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Crea tu cuenta de agricultor para consultar tus lotes y seguir el trabajo de cada cosecha.',
                                  ),
                                  const SizedBox(height: 20),
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.sage,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.info_outline_rounded,
                                          size: 20,
                                          color: AppTheme.forest,
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Tu registro requiere la aprobación de un administrador.',
                                            style: TextStyle(
                                              color: AppTheme.forest,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _section('01', 'Datos personales'),
                                  _field(
                                    'nombre',
                                    'Nombre',
                                    capitalization: TextCapitalization.words,
                                    autofillHints: const [
                                      AutofillHints.givenName,
                                    ],
                                  ),
                                  _field(
                                    'apellido',
                                    'Apellido',
                                    capitalization: TextCapitalization.words,
                                    autofillHints: const [
                                      AutofillHints.familyName,
                                    ],
                                  ),
                                  _field(
                                    'telefono',
                                    'Teléfono (opcional)',
                                    optional: true,
                                    keyboard: TextInputType.phone,
                                    autofillHints: const [
                                      AutofillHints.telephoneNumber,
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _section('02', 'Datos de acceso'),
                                  _field(
                                    'email',
                                    'Correo electrónico',
                                    keyboard: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                  ),
                                  _field(
                                    'nombreusuario',
                                    'Nombre de usuario',
                                    autofillHints: const [
                                      AutofillHints.newUsername,
                                    ],
                                  ),
                                  _field(
                                    'password',
                                    'Contraseña',
                                    secret: true,
                                    helperText: 'Mínimo 6 caracteres.',
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                  ),
                                  _field(
                                    'password_confirmation',
                                    'Confirmar contraseña',
                                    secret: true,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Confirma tu contraseña.';
                                      }
                                      return value != _fields['password']!.text
                                          ? 'Las contraseñas no coinciden.'
                                          : null;
                                    },
                                  ),
                                  if (message != null) ...[
                                    AppNotice(
                                      tone: AppNoticeTone.error,
                                      message: message,
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  FilledButton.icon(
                                    onPressed: busy ? null : _submit,
                                    icon: busy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.person_add_outlined),
                                    label: Padding(
                                      padding: EdgeInsets.zero,
                                      child: Text(
                                        busy
                                            ? 'Enviando solicitud...'
                                            : 'Enviar solicitud',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: busy ? null : _leave,
                                    child: const Text('Ya tengo una cuenta'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _section(String number, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        Text(
          number,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    ),
  );
}
