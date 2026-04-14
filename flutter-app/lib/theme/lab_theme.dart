import 'package:flutter/material.dart';

ThemeData buildLabTheme() {
  const seedColor = Color(0xFF0F766E);
  const canvasColor = Color(0xFFF4EEE4);
  const strongInk = Color(0xFF152033);

  final base = ThemeData(useMaterial3: true);
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF0F766E),
        secondary: const Color(0xFFB45309),
        tertiary: const Color(0xFF0F4C81),
        surface: const Color(0xFFFBF8F2),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF3EDE1),
        surfaceContainer: const Color(0xFFEEE4D5),
        surfaceContainerHigh: const Color(0xFFE6D8C6),
        surfaceContainerHighest: const Color(0xFFDED0BF),
        outlineVariant: const Color(0xFFD3C3B2),
        onSurface: strongInk,
      );

  final textTheme = base.textTheme.copyWith(
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: strongInk,
      letterSpacing: -0.6,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: strongInk,
      letterSpacing: -0.2,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: strongInk,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      color: strongInk.withValues(alpha: 0.92),
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      color: strongInk.withValues(alpha: 0.84),
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      color: strongInk.withValues(alpha: 0.68),
    ),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
  );

  return base.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: canvasColor,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: colorScheme.outlineVariant),
      ),
      hintStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      side: BorderSide(color: colorScheme.outlineVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.secondary,
      foregroundColor: colorScheme.onSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: strongInk,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
