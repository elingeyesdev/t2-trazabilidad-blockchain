import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/auth_controller.dart';
import '../../models/registration_result.dart';

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
    if (widget.controller.isSubmitting || !_formKey.currentState!.validate()) {
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
    if (!mounted || result == null) return;
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
          border: const OutlineInputBorder(),
          errorMaxLines: 3,
          errorText: messages == null || messages.isEmpty
              ? null
              : messages.join('\n'),
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
              final empty =
                  value == null ||
                  (secret ? value.isEmpty : value.trim().isEmpty);
              return empty ? 'Completa este campo.' : null;
            },
        onChanged: (_) => widget.controller.clearError(),
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
              Icon(
                Icons.schedule_outlined,
                size: 56,
                color: theme.colorScheme.primary,
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
              Semantics(
                liveRegion: true,
                child: Text(result.message, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              const Text(
                'Podrás iniciar sesión cuando un administrador apruebe tu cuenta.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
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
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: AutofillGroup(
                            onDisposeAction: AutofillContextAction.cancel,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Solicita una cuenta de agricultor. Tu registro requiere la aprobación de un administrador.',
                                  ),
                                  const SizedBox(height: 24),
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
                                    'telefono',
                                    'Teléfono (opcional)',
                                    optional: true,
                                    keyboard: TextInputType.phone,
                                    autofillHints: const [
                                      AutofillHints.telephoneNumber,
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
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        message,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
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
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        busy
                                            ? 'Enviando solicitud...'
                                            : 'Enviar solicitud',
                                      ),
                                    ),
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
}
