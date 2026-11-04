import 'package:flutter/material.dart';

/// Tema de StudyVerse: simple y con aire.
///
/// Claro: blanco con acentos celestes. Oscuro: azul noche con el mismo celeste
/// más luminoso, para que se lea bien sin encandilar.
class AppTheme {
  static const celeste = Color(0xFF1C8AD4);

  static ThemeData light() => _build(_claro);
  static ThemeData dark() => _build(_oscuro);

  static final _claro = ColorScheme.fromSeed(seedColor: celeste).copyWith(
    primary: const Color(0xFF1479C4), // contraste AA sobre blanco
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD9EEFC),
    onPrimaryContainer: const Color(0xFF00344F),
    secondaryContainer: const Color(0xFFE3F2FD),
    onSecondaryContainer: const Color(0xFF0B3A5B),
    surface: Colors.white,
    onSurface: const Color(0xFF16202A),
    onSurfaceVariant: const Color(0xFF51606E),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF6FAFE),
    surfaceContainer: const Color(0xFFF0F6FC),
    surfaceContainerHigh: const Color(0xFFEAF2FA),
    surfaceContainerHighest: const Color(0xFFE3EDF7),
    outline: const Color(0xFF8A99A8),
    outlineVariant: const Color(0xFFDCE5EE),
    inverseSurface: const Color(0xFF26323D),
    onInverseSurface: const Color(0xFFF1F5F9),
    inversePrimary: const Color(0xFF8CCBF5),
  );

  static final _oscuro = ColorScheme.fromSeed(seedColor: celeste, brightness: Brightness.dark).copyWith(
    primary: const Color(0xFF8CCBF5),
    onPrimary: const Color(0xFF00344F),
    primaryContainer: const Color(0xFF0F4C75),
    onPrimaryContainer: const Color(0xFFD9EEFC),
    secondaryContainer: const Color(0xFF1B3448),
    onSecondaryContainer: const Color(0xFFD6E8F7),
    surface: const Color(0xFF0F1720),
    onSurface: const Color(0xFFE3EAF1),
    onSurfaceVariant: const Color(0xFFA9B6C3),
    surfaceContainerLowest: const Color(0xFF0B1219),
    surfaceContainerLow: const Color(0xFF141E28),
    surfaceContainer: const Color(0xFF18232E),
    surfaceContainerHigh: const Color(0xFF1E2A36),
    surfaceContainerHighest: const Color(0xFF25323F),
    outline: const Color(0xFF6F7E8C),
    outlineVariant: const Color(0xFF2C3946),
    inverseSurface: const Color(0xFFE3EAF1),
    onInverseSurface: const Color(0xFF1A2530),
    inversePrimary: const Color(0xFF1479C4),
  );

  static ThemeData _build(ColorScheme scheme) {
    final radius = BorderRadius.circular(12);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        // Errores como en Drive: texto chico debajo del campo, sin bloques de color.
        errorMaxLines: 2,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Ancho completo solo donde el padre estira (formularios).
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      // Avisos como los de Drive: oscuros, compactos, abajo a la izquierda en
      // pantallas anchas, sin colores de alarma.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 14),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 2,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
