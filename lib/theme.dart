import 'package:flutter/material.dart';
import 'layouts/ui_layout.dart';

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
  static ThemeData theme({bool tv = false, UiLayout layout = UiLayout.marquee}) {
    final p = LayoutPalette.forLayout(layout);
    final base = p.light ? ThemeData.light(useMaterial3: true) : ThemeData.dark(useMaterial3: true);

    // Buttons get a white outline while focused so the selection is visible from the couch.
    WidgetStateProperty<BorderSide?>? focusSide([BorderSide unfocused = BorderSide.none]) => tv
        ? WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused) ? BorderSide(color: p.ring, width: 3) : unfocused)
        : null;

    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      extensions: [p],
      focusColor: p.accent.withValues(alpha: 0.28),
      hoverColor: p.accent.withValues(alpha: 0.10),
      colorScheme: (p.light ? ColorScheme.light : ColorScheme.dark)(
        primary: p.accent,
        secondary: p.accent2,
        surface: p.surface,
        // Tonal buttons on a light layout: a quiet grey chip with ink text, not a dark green block.
        secondaryContainer: p.light ? p.surfaceHi : null,
        onSecondaryContainer: p.light ? p.text : null,
      ),
      textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.frosted ? p.text.withValues(alpha: 0.12) : p.surface,
        elevation: p.frosted ? 0 : null,
        surfaceTintColor: p.frosted ? Colors.transparent : null,
        indicatorColor: p.accent.withValues(alpha: 0.25),
      ),
      // Buttons are bigger on a TV: they are read and pressed from across the room.
      filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
        side: focusSide(),
        textStyle: tv ? const WidgetStatePropertyAll(TextStyle(fontSize: 18, fontWeight: FontWeight.w700)) : null,
        padding: tv ? const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 26, vertical: 14)) : null,
        minimumSize: tv ? const WidgetStatePropertyAll(Size(0, 52)) : null,
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(side: focusSide(BorderSide(color: p.text.withValues(alpha: 0.38))))),
      textButtonTheme: TextButtonThemeData(style: ButtonStyle(side: focusSide())),
      iconButtonTheme: IconButtonThemeData(style: ButtonStyle(side: focusSide())),
      chipTheme: ChipThemeData(
        side: tv
            ? WidgetStateBorderSide.resolveWith((s) => s.contains(WidgetState.focused)
                ? BorderSide(color: p.ring, width: 3)
                : BorderSide(color: p.text.withValues(alpha: 0.24)))
            : null,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tv ? Colors.transparent : p.surface,
        unselectedIconTheme: tv ? IconThemeData(size: 30, color: p.text.withValues(alpha: 0.8)) : null,
        minWidth: tv ? 96 : null,
        indicatorColor: p.accent.withValues(alpha: 0.25),
        selectedIconTheme: IconThemeData(color: p.accent, size: tv ? 30 : null),
        selectedLabelTextStyle: TextStyle(color: p.accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceHi,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
