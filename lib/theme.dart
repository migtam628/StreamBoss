import 'package:flutter/material.dart';

class Boss {
  static const bg = Color(0xFF0B0B12);
  static const surface = Color(0xFF15151F);
  static const surfaceHi = Color(0xFF1F1F2E);
  static const accent = Color(0xFFFF3D71); // hot pink-red
  static const accent2 = Color(0xFFFFB02E); // gold
  static const text = Color(0xFFF2F2F7);
  static const muted = Color(0xFF8C8CA1);

  static ThemeData theme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent2,
        surface: surface,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withOpacity(0.25),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withOpacity(0.25),
        selectedIconTheme: const IconThemeData(color: accent),
        selectedLabelTextStyle: const TextStyle(color: accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHi,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
