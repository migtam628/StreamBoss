import 'package:flutter/material.dart';

class Boss {
  static const bg = Color(0xFF0B0B12);
  static const surface = Color(0xFF15151F);
  static const surfaceHi = Color(0xFF1F1F2E);
  static const accent = Color(0xFFFF3D71); // hot pink-red
  static const accent2 = Color(0xFFFFB02E); // gold
  static const text = Color(0xFFF2F2F7);
  static const muted = Color(0xFF8C8CA1);

  /// [tv] switches on the 10-foot styling: a bold white focus outline on every control (a
  /// remote has no pointer, so focus is the only cursor) and a larger navigation rail.
  static ThemeData theme({bool tv = false}) {
    final base = ThemeData.dark(useMaterial3: true);

    // Buttons get a white outline while focused so the selection is visible from the couch.
    WidgetStateProperty<BorderSide?>? focusSide([BorderSide unfocused = BorderSide.none]) => tv
        ? WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused) ? const BorderSide(color: Colors.white, width: 3) : unfocused)
        : null;

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      focusColor: accent.withValues(alpha: 0.28),
      hoverColor: accent.withValues(alpha: 0.10),
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent2,
        surface: surface,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.25),
      ),
      filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(side: focusSide())),
      outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(side: focusSide(const BorderSide(color: Colors.white38)))),
      textButtonTheme: TextButtonThemeData(style: ButtonStyle(side: focusSide())),
      iconButtonTheme: IconButtonThemeData(style: ButtonStyle(side: focusSide())),
      chipTheme: ChipThemeData(
        side: tv
            ? WidgetStateBorderSide.resolveWith((s) => s.contains(WidgetState.focused)
                ? const BorderSide(color: Colors.white, width: 3)
                : const BorderSide(color: Colors.white24))
            : null,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tv ? Colors.transparent : surface,
        unselectedIconTheme: tv ? const IconThemeData(size: 30, color: Color(0xFFD0D0DC)) : null,
        minWidth: tv ? 96 : null,
        indicatorColor: accent.withValues(alpha: 0.25),
        selectedIconTheme: IconThemeData(color: accent, size: tv ? 30 : null),
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
