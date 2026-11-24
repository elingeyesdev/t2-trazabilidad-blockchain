import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/auth_controller.dart';
import '../../models/registration_result.dart';
import '../../navigation/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_kit.dart';
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

  Future<void> _openPublicTraceability() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).pushNamed(AppRoutes.trazabilidadPublica);
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
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
        final shortScreen = MediaQuery.sizeOf(context).height < 680;
        final scrollPadding = formScrollPadding(context);

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  20,
                  shortScreen ? 10 : 16,
                  20,
                  shortScreen ? 16 : 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!shortScreen) ...[
                            _banner(largeText),
                            const SizedBox(height: 24),
                          ] else ...[
                            const Row(
                              children: [
                                BrandMark(size: 36),
                                SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    'AgroFusion',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          Semantics(
                            header: true,
                            child: Text(
                              'Inicia sesión con tu cuenta',
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          if (!shortScreen) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Escribe el correo y la contraseña que usas en AgroFusion.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: AppTheme.inkSoft,
                              ),
                            ),
                          ],
                          SizedBox(height: shortScreen ? 14 : 22),
                          if (widget.controller.logoutResult
                              case final result?) ...[
                            _notice(
                              icon: result.remoteClosed
                                  ? Icons.check_circle_rounded
                                  : Icons.warning_amber_rounded,
                              text: result.message,
                              tone: result.remoteClosed
                                  ? AppTheme.sprout
                                  : AppTheme.maizeSoft,
                              ink: result.remoteClosed
                                  ? AppTheme.fieldDeep
                                  : AppTheme.ink,
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _email,
                            enabled: !busy,
                            scrollPadding: scrollPadding,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            forceErrorText: emailError,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            autocorrect: false,
                            textCapitalization: TextCapitalization.none,
                            style: const TextStyle(fontSize: 18),
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              hintText: 'nombre@correo.com',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: validateEmail,
                            onChanged: (_) =>
                                widget.controller.clearError(field: 'email'),
                          ),
                          SizedBox(height: shortScreen ? 14 : 20),
                          TextFormField(
                            controller: _password,
                            enabled: !busy,
                            scrollPadding: scrollPadding,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            forceErrorText: passwordError,
                            obscureText: _obscurePassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            style: const TextStyle(fontSize: 18),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: IconButton(
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
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Ingresa tu contraseña.'
                                : null,
                            onChanged: (_) =>
                                widget.controller.clearError(field: 'password'),
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (message != null) ...[
                            const SizedBox(height: 16),
                            _notice(
                              icon: Icons.error_outline_rounded,
                              text: message,
                              tone: AppTheme.claySoft,
                              ink: const Color(0xFF5E1D0E),
                            ),
                          ],
                          SizedBox(height: shortScreen ? 16 : 24),
                          FilledButton(
                            onPressed: busy ? null : _submit,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (busy) ...[
                                  const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: AppTheme.inkSoft,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                ] else ...[
                                  const Icon(Icons.login_rounded),
                                  const SizedBox(width: 10),
                                ],
                                Flexible(
                                  child: Text(
                                    busy ? 'Ingresando...' : 'Iniciar sesión',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: shortScreen ? 12 : 22),
                          if (!shortScreen) ...[
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    '¿Primera vez aquí?',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ],
                          OutlinedButton.icon(
                            onPressed: busy ? null : _openRegistration,
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('Crear cuenta'),
                          ),
                          SizedBox(height: shortScreen ? 10 : 14),
                          OutlinedButton.icon(
                            key: const ValueKey('login.trazabilidad_publica'),
                            onPressed: busy ? null : _openPublicTraceability,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppTheme.sprout,
                              foregroundColor: AppTheme.fieldDeep,
                              side: const BorderSide(
                                color: AppTheme.sproutBorder,
                                width: 1,
                              ),
                            ),
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: const Text(
                              'Consultar trazabilidad (QR o código)',
                              textAlign: TextAlign.center,
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
        );
      },
    );
  }

  Widget _banner(bool compact) => Container(
    height: compact ? 64 : 148,
    decoration: BoxDecoration(
      color: const Color(0xFFCFE5EC),
      borderRadius: BorderRadius.circular(24),
      boxShadow: AppTheme.stamp(4),
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppTheme.border, width: 1),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ExcludeSemantics(child: CustomPaint(painter: FurrowPainter())),
          Positioned(
            left: 16,
            top: 16,
            right: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BrandMark(size: 36),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'AgroFusion',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _notice({
    required IconData icon,
    required String text,
    required Color tone,
    required Color ink,
  }) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ink, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: ink,
                fontSize: 17,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
