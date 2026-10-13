import 'package:flutter/material.dart';

/// Colours from the Haske Movement logo.
class HaskeColors {
  static const green = Color(0xFF0B6B30);
  static const red = Color(0xFFD7141A);
  static const gold = Color(0xFFF2B705);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HaskeColors.green,
    primary: HaskeColors.green,
    secondary: HaskeColors.gold,
    error: HaskeColors.red,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
