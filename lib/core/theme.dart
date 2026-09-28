import 'package:flutter/material.dart';

import 'design/tokens.dart';

/// DocSync brand palette (from the logo's interlocking squares).
class Brand {
  static const blue = Color(0xFF2563EB);
  static const red = Color(0xFFE53935);
  static const green = Color(0xFF43A047);
  static const amber = Color(0xFFFBC02D);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Ds.blue,
    brightness: Brightness.light,
  ).copyWith(
    primary: Ds.blue,
    secondary: Ds.indigo,
    surface: Ds.surface,
    onSurface: Ds.ink,
    outline: Ds.muted,
    outlineVariant: Ds.line,
    error: Ds.red,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: Ds.ink, displayColor: Ds.ink).copyWith(
        headlineSmall: base.textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, color: Ds.ink),
        titleLarge: base.textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: Ds.ink),
        titleMedium: base.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600, color: Ds.ink),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: Ds.muted),
        labelMedium: base.textTheme.labelMedium?.copyWith(color: Ds.muted),
      );

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: Ds.bgBottom,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: Ds.ink,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ds.rCard),
        side: const BorderSide(color: Ds.line),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Ds.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ds.rField),
        borderSide: const BorderSide(color: Ds.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ds.rField),
        borderSide: const BorderSide(color: Ds.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ds.rField),
        borderSide: const BorderSide(color: Ds.blue, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rChip)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Ds.ink,
        side: const BorderSide(color: Ds.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rChip)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      side: const BorderSide(color: Ds.line),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rChip)),
      labelStyle: const TextStyle(color: Ds.inkSoft, fontWeight: FontWeight.w500),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Ds.rCard + 4)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Ds.line, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Ds.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ds.rChip)),
    ),
  );
}
