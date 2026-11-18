import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/auth_controller.dart';
import '../../models/registration_result.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_kit.dart';

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
    IconData? icon,
    String? Function(String?)? validator,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    final messages = widget.controller.error?.validationErrors[name];
    final visible = _visiblePasswords.contains(name);
    final busy = widget.controller.isSubmitting;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
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
        style: const TextStyle(fontSize: 18),
        textInputAction: name == 'password_confirmation'
            ? TextInputAction.done
            : TextInputAction.next,
        onFieldSubmitted: name == 'password_confirmation'
            ? (_) => _submit()
            : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          helperMaxLines: 2,
          prefixIcon: icon == null ? null : Icon(icon),
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

  Widget _step(int number, String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Semantics(
      header: true,
      label: 'Paso $number de 3. $title. $subtitle',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.maize,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.ink, width: 2),
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _confirmation(RegistrationResult result) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: IconMedallion(
                  icon: Icons.mark_email_read_rounded,
                  tone: AppTheme.maizeSoft,
                  ink: Color(0xFF5F4100),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Solicitud enviada',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                result.email,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: AppTheme.ink, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        result.message,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    const Divider(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.hourglass_top_rounded,
                          color: Color(0xFF5F4100),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Podrás iniciar sesión cuando un administrador apruebe tu cuenta.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _leave,
                child: const Text(
                  'Volver al inicio de sesión',
                  textAlign: TextAlign.center,
                ),
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
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            body: SafeArea(
              child: result != null
                  ? _confirmation(result)
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: AutofillGroup(
                            onDisposeAction: AutofillContextAction.cancel,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.skySoft,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppTheme.sky,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.info_outline_rounded,
                                          color: AppTheme.sky,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Solicita una cuenta de agricultor. Tu registro requiere la aprobación de un administrador.',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xFF173E57,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  _step(1, 'Tus datos', '¿Cómo te llamas?'),
                                  _field(
                                    'nombre',
                                    'Nombre',
                                    icon: Icons.badge_outlined,
                                    capitalization: TextCapitalization.words,
                                    autofillHints: const [
                                      AutofillHints.givenName,
                                    ],
                                  ),
                                  _field(
                                    'apellido',
                                    'Apellido',
                                    icon: Icons.badge_outlined,
                                    capitalization: TextCapitalization.words,
                                    autofillHints: const [
                                      AutofillHints.familyName,
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _step(
                                    2,
                                    'Cómo te encontramos',
                                    'Correo, usuario y teléfono.',
                                  ),
                                  _field(
                                    'email',
                                    'Correo electrónico',
                                    icon: Icons.mail_outline_rounded,
                                    keyboard: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                  ),
                                  _field(
                                    'nombreusuario',
                                    'Nombre de usuario',
                                    icon: Icons.alternate_email_rounded,
                                    autofillHints: const [
                                      AutofillHints.newUsername,
                                    ],
                                  ),
                                  _field(
                                    'telefono',
                                    'Teléfono (opcional)',
                                    icon: Icons.phone_outlined,
                                    optional: true,
                                    keyboard: TextInputType.phone,
                                    autofillHints: const [
                                      AutofillHints.telephoneNumber,
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _step(
                                    3,
                                    'Tu contraseña',
                                    'Escríbela dos veces para confirmar.',
                                  ),
                                  _field(
                                    'password',
                                    'Contraseña',
                                    icon: Icons.lock_outline_rounded,
                                    secret: true,
                                    helperText: 'Mínimo 6 caracteres.',
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                  ),
                                  _field(
                                    'password_confirmation',
                                    'Confirmar contraseña',
                                    icon: Icons.lock_outline_rounded,
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
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: AppTheme.claySoft,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: AppTheme.clay,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.error_outline_rounded,
                                              color: AppTheme.clay,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                message,
                                                style: const TextStyle(
                                                  color: Color(0xFF5E1D0E),
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  const SizedBox(height: 6),
                                  FilledButton.icon(
                                    onPressed: busy ? null : _submit,
                                    icon: busy
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: AppTheme.inkSoft,
                                            ),
                                          )
                                        : const Icon(Icons.send_rounded),
                                    label: Text(
                                      busy
                                          ? 'Enviando solicitud...'
                                          : 'Enviar solicitud',
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
