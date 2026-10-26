import 'api_exception.dart';

class RegistrationResult {
  const RegistrationResult({required this.message, required this.email});

  factory RegistrationResult.fromJson(Object? json) {
    if (json
        case {
          'message': String message,
          'user': {'email': String email, 'estado_cuenta': 'pendiente'},
        }
        when !json.containsKey('token') &&
            message.trim().isNotEmpty &&
            email.trim().isNotEmpty) {
      return RegistrationResult(message: message, email: email);
    }
    throw const ApiException(
      'La API devolvió una confirmación de registro inválida.',
    );
  }

  final String message;
  final String email;
}
