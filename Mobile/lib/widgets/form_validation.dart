import 'dart:async';

import 'package:flutter/material.dart';

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Ingresa tu correo electrónico.';
  if (!RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(email)) {
    return 'Escribe un correo válido, por ejemplo nombre@correo.com.';
  }
  return null;
}

bool validateForm(GlobalKey<FormState> key) {
  final valid = key.currentState!.validate();
  if (!valid) revealFormErrors(key);
  return valid;
}

void revealFormErrors(GlobalKey<FormState> key) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final errors = key.currentState?.validateGranularly();
    if (errors == null || errors.isEmpty) return;
    unawaited(
      Scrollable.ensureVisible(
        errors.first.context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
      ),
    );
  });
}
