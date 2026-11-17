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

EdgeInsets formScrollPadding(BuildContext context) {
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  return EdgeInsets.fromLTRB(20, 20, 20, keyboard + 120);
}

EdgeInsets formContentPadding(BuildContext context, {double base = 24}) {
  final width = MediaQuery.sizeOf(context).width;
  final horizontal = width < 360 ? 16.0 : base;
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  return EdgeInsets.fromLTRB(
    horizontal,
    base,
    horizontal,
    base + (keyboard > 0 ? 16 : 0),
  );
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
