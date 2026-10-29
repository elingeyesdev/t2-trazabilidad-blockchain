import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const forest = Color(0xFF1C4938);
  static const ink = Color(0xFF202D26);
  static const muted = Color(0xFF657168);
  static const canvas = Color(0xFFF7F6F0);
  static const line = Color(0xFFE2E5DB);
  static const sage = Color(0xFFEAF0E4);
  static const ochre = Color(0xFFF0C879);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: forest).copyWith(
      primary: forest,
      onPrimary: Colors.white,
      secondary: ochre,
      onSecondary: forest,
      surface: canvas,
      surfaceContainerLow: Colors.white,
      surfaceContainerHighest: sage,
      onSurface: ink,
      onSurfaceVariant: muted,
      primaryContainer: sage,
      onPrimaryContainer: forest,
      outlineVariant: line,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: muted),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: sage,
        height: 76,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? forest : muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
