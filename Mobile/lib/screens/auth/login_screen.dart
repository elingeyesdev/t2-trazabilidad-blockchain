import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/auth_controller.dart';
import '../../models/registration_result.dart';
import '../../navigation/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_kit.dart';

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
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final success = await widget.controller.login(_email.text, _password.text);
    if (!mounted || !success) return;
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
        final message = emailError == null && passwordError == null
            ? widget.controller.error?.message
            : null;
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
        final shortScreen = MediaQuery.sizeOf(context).height < 680;

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
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
                          _banner(largeText || shortScreen),
                          SizedBox(height: shortScreen ? 16 : 24),
                          Semantics(
                            header: true,
                            child: Text(
                              'Inicia sesión con tu cuenta',
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Escribe el correo y la contraseña que usas en AgroFusion.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppTheme.inkSoft,
                            ),
                          ),
                          SizedBox(height: shortScreen ? 16 : 22),
                          if (widget.controller.logoutResult
                              case final result?) ...[
                            _notice(
                              icon: Icons.check_circle_rounded,
                              text: result.message,
                              tone: AppTheme.sprout,
                              ink: AppTheme.fieldDeep,
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _email,
                            enabled: !busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            autocorrect: false,
                            textCapitalization: TextCapitalization.none,
                            style: const TextStyle(fontSize: 18),
                            decoration: InputDecoration(
                              labelText: 'Correo electrónico',
                              hintText: 'nombre@correo.com',
                              prefixIcon: const Icon(
                                Icons.mail_outline_rounded,
                              ),
                              errorText: emailError,
                              errorMaxLines: 3,
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Ingresa tu correo electrónico.'
                                : null,
                            onChanged: (_) => widget.controller.clearError(),
                          ),
                          SizedBox(height: shortScreen ? 14 : 20),
                          TextFormField(
                            controller: _password,
                            enabled: !busy,
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
                              errorText: passwordError,
                              errorMaxLines: 3,
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
                            onChanged: (_) => widget.controller.clearError(),
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
                          SizedBox(height: shortScreen ? 4 : 10),
                          Center(
                            child: TextButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => Navigator.of(
                                      context,
                                    ).pushNamed(AppRoutes.connection),
                              icon: const Icon(Icons.wifi_rounded),
                              label: const Text('Comprobar conexión'),
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
    height: compact ? 86 : 148,
    decoration: BoxDecoration(
      color: const Color(0xFFCFE5EC),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppTheme.ink, width: 2),
      boxShadow: AppTheme.stamp(5),
    ),
    clipBehavior: Clip.antiAlias,
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
                border: Border.all(color: AppTheme.ink, width: 2),
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
        border: Border.all(color: ink, width: 1.5),
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
