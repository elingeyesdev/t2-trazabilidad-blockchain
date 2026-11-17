import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/auth_controller.dart';
import '../../models/registration_result.dart';
import '../../navigation/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/action_confirmation.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/form_validation.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  Future<void> _openRegistration() async {
    widget.controller.clearError();
    final result = await Navigator.of(context).pushNamed(AppRoutes.register);
    if (!mounted) return;
    widget.controller.clearError();
    if (result is RegistrationResult) {
      _email.text = result.email;
      _password.clear();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.controller.isSubmitting) return;
    if (!validateForm(_formKey)) return;
    FocusScope.of(context).unfocus();
    final success = await widget.controller.login(_email.text, _password.text);
    if (!mounted) return;
    if (!success) {
      revealFormErrors(_formKey);
      return;
    }
    _password.clear();
    TextInput.finishAutofillContext();
  }

  String? _fieldError(String field) {
    final messages = widget.controller.error?.validationErrors[field];
    return messages == null || messages.isEmpty ? null : messages.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.isSubmitting;
        final theme = Theme.of(context);
        final availableHeight =
            MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom;
        final showBrandPanel =
            availableHeight >= 740 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24;
        final scrollPadding = formScrollPadding(context);
        final emailError = _fieldError('email');
        final passwordError = _fieldError('password');
        final error = widget.controller.error;
        final message =
            error != null &&
                (error.validationErrors.isEmpty ||
                    error.validationErrors.keys.any(
                      (field) => field != 'email' && field != 'password',
                    ))
            ? error.message
            : null;

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: formContentPadding(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showBrandPanel)
                            _brandPanel()
                          else
                            const BrandWordmark(),
                          SizedBox(height: showBrandPanel ? 32 : 24),
                          Text(
                            'Inicia sesión',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tu campo y tu trabajo, en un mismo lugar.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 24),
                          if (widget.controller.logoutResult
                              case final result?) ...[
                            AppNotice(
                              tone: result.remoteClosed
                                  ? AppNoticeTone.success
                                  : AppNoticeTone.warning,
                              message: result.message,
                            ),
                            const SizedBox(height: 20),
                          ],
                          TextFormField(
                            controller: _email,
                            scrollPadding: scrollPadding,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            forceErrorText: emailError,
                            enabled: !busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            autocorrect: false,
                            textCapitalization: TextCapitalization.none,
                            decoration: InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: const Icon(Icons.mail_outline),
                              hintText: 'nombre@correo.com',
                            ),
                            validator: validateEmail,
                            onChanged: (_) =>
                                widget.controller.clearError(field: 'email'),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            scrollPadding: scrollPadding,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            forceErrorText: passwordError,
                            enabled: !busy,
                            obscureText: _obscurePassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                onPressed: busy
                                    ? null
                                    : () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Ingresa tu contraseña.'
                                : null,
                            onChanged: (_) =>
                                widget.controller.clearError(field: 'password'),
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (message != null) ...[
                            const SizedBox(height: 20),
                            AppNotice(
                              tone: AppNoticeTone.error,
                              message: message,
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: busy ? null : _submit,
                            child: Padding(
                              padding: EdgeInsets.zero,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (busy) ...[
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Flexible(
                                    child: Text(
                                      busy ? 'Ingresando...' : 'Iniciar sesión',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  if (!busy) ...[
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 20,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('¿Aún no tienes cuenta?'),
                              TextButton(
                                onPressed: busy ? null : _openRegistration,
                                child: const Text('Crear cuenta'),
                              ),
                            ],
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
      },
    );
  }

  Widget _brandPanel() => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: ColoredBox(
      color: AppTheme.forest,
      child: Stack(
        children: [
          const Positioned(
            right: -30,
            bottom: -48,
            width: 170,
            height: 180,
            child: ExcludeSemantics(child: CustomPaint(painter: FieldLines())),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandWordmark(inverse: true),
                const SizedBox(height: 32),
                const Text(
                  'El origen de\ncada cosecha.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.12,
                    letterSpacing: -.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(width: 32, height: 3, color: AppTheme.ochre),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
