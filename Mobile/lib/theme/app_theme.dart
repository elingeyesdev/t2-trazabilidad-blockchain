import 'package:flutter/material.dart';

/// Sistema visual "Libreta de campo".
///
/// Papel cálido, tinta oscura y bordes firmes: se lee bien a pleno sol y los
/// elementos tocables parecen botones físicos. Todos los pares de color de
/// texto cumplen al menos WCAG AA (la mayoría AAA).
abstract final class AppTheme {
  // Base
  static const paper = Color(0xFFF5F0E4);
  static const surface = Color(0xFFFFFCF5);
  static const ink = Color(0xFF1B2620);
  static const inkSoft = Color(0xFF465149);
  static const line = Color(0xFFD8CFBB);
  static const border = Color(0xFFC5BBA5);
  static const sproutBorder = Color(0xFFA8C59D);
  static const lineStrong = Color(0xFF6E776F);

  // Marca
  static const field = Color(0xFF2B6A3D);
  static const fieldDeep = Color(0xFF1C4A2A);
  static const sprout = Color(0xFFDCEBD3);
  static const maize = Color(0xFFF2B33D);
  static const maizeSoft = Color(0xFFFBE8B8);
  static const clay = Color(0xFFA63D24);
  static const claySoft = Color(0xFFF7DCD3);
  static const sky = Color(0xFF235E84);
  static const skySoft = Color(0xFFD7E6F0);

  // Alias usados por pantallas anteriores.
  static const forest = field;
  static const muted = inkSoft;
  static const canvas = paper;
  static const sage = sprout;
  static const ochre = maize;

  /// Sombra sutil para dar profundidad sin bordes gruesos ni efecto cómic.
  static List<BoxShadow> stamp([double depth = 4, Color color = ink]) => [
    BoxShadow(
      color: ink.withValues(alpha: .07),
      blurRadius: depth * 2.5,
      offset: Offset(0, (depth * .5).clamp(1.0, 3.0)),
    ),
  ];

  static const radius = 18.0;

  /// Títulos: Bricolage Grotesque, de ancho variable. Da carácter sin perder
  /// legibilidad; el cuerpo usa Atkinson Hyperlegible, pensada para leer con
  /// poca vista o a pleno sol.
  static TextStyle display(
    double size,
    double height,
    double weight,
    double spacing,
  ) => TextStyle(
    fontFamily: 'Bricolage',
    fontSize: size,
    height: height,
    letterSpacing: spacing,
    color: ink,
    fontVariations: [FontVariation.weight(weight)],
  );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: field).copyWith(
      primary: field,
      onPrimary: Colors.white,
      primaryContainer: sprout,
      onPrimaryContainer: fieldDeep,
      secondary: maize,
      onSecondary: ink,
      secondaryContainer: maizeSoft,
      onSecondaryContainer: ink,
      error: clay,
      onError: Colors.white,
      errorContainer: claySoft,
      onErrorContainer: const Color(0xFF5E1D0E),
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: inkSoft,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: const Color(0xFFEFE8D8),
      surfaceContainerHighest: const Color(0xFFE9E1CF),
      outline: lineStrong,
      outlineVariant: line,
    );

    const font = 'Atkinson';
    final text = TextTheme(
      displaySmall: display(34, 1.12, 800, -0.8),
      headlineMedium: display(30, 1.15, 800, -0.6),
      headlineSmall: display(27, 1.18, 800, -0.5),
      titleLarge: display(21, 1.25, 800, -0.3),
      titleMedium: TextStyle(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 17, height: 1.45, color: ink),
      bodyMedium: TextStyle(fontSize: 16, height: 1.45, color: inkSoft),
      bodySmall: TextStyle(fontSize: 14, height: 1.4, color: inkSoft),
      labelLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      labelMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      fontFamily: font,
      textTheme: text,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      iconTheme: const IconThemeData(color: ink, size: 26),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 64,
        iconTheme: IconThemeData(color: ink, size: 28),
        actionsIconTheme: IconThemeData(color: ink, size: 28),
        titleTextStyle: display(22, 1.2, 800, -.4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: field,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFD9D3C4),
          disabledForegroundColor: inkSoft,
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: font,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: .1,
          ),
          iconSize: 22,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: surface,
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          side: const BorderSide(color: border, width: 1.2),
          textStyle: const TextStyle(
            fontFamily: font,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          iconSize: 22,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fieldDeep,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(
            fontFamily: font,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationThickness: 2,
          ),
          iconSize: 20,
          shape: buttonShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(52, 52),
          iconSize: 28,
          foregroundColor: ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        labelStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.error)
                ? clay
                : states.contains(WidgetState.focused)
                ? field
                : ink,
          ),
        ),
        hintStyle: const TextStyle(fontSize: 17, color: Color(0xFF6F776F)),
        helperStyle: const TextStyle(fontSize: 15, color: inkSoft),
        errorStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: clay,
        ),
        prefixIconColor: inkSoft,
        suffixIconColor: inkSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: field, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: clay, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: clay, width: 1.8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line, width: 1),
        ),
        errorMaxLines: 3,
        helperMaxLines: 3,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: sprout,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: sproutBorder, width: 1),
        ),
        height: 84,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 28,
            color: states.contains(WidgetState.selected) ? fieldDeep : inkSoft,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: font,
            fontSize: 15,
            color: states.contains(WidgetState.selected) ? fieldDeep : inkSoft,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(
          fontFamily: font,
          fontSize: 17,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: field,
        linearTrackColor: sprout,
        circularTrackColor: sprout,
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: const TextStyle(fontSize: 15, color: Colors.white),
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: ink,
        textColor: ink,
        minTileHeight: 64,
      ),
    );
  }
}
