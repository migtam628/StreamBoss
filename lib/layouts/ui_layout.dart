import 'package:flutter/material.dart';

/// The three selectable looks (Settings > Appearance > Layout). Each one changes the navigation,
/// the Home screen and the browse screens, and carries its own palette.
enum UiLayout {
  marquee('Marquee',
      'Cinematic. One big feature on Home, a slim icon rail, rows of posters.'),
  control('Control Room',
      'Channel-first. Categories, a numbered channel list with what is on now, and a details pane.'),
  spotlight('Spotlight',
      'A poster wall. The focused title gets a details panel; navigation is one pill.');

  final String label;
  final String blurb;
  const UiLayout(this.label, this.blurb);

  static UiLayout fromKey(String key) => UiLayout.values
      .firstWhere((l) => l.name == key, orElse: () => UiLayout.marquee);
}

/// Colors for one layout. Material widgets get them through the ThemeData in `Boss.theme`; the
/// layout widgets read them with [LayoutPalette.of].
class LayoutPalette extends ThemeExtension<LayoutPalette> {
  final Color bg, surface, surfaceHi, accent, accent2, text, muted, line;
  const LayoutPalette({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.accent,
    required this.accent2,
    required this.text,
    required this.muted,
    required this.line,
  });

  static const marquee = LayoutPalette(
    bg: Color(0xFF0B0B12),
    surface: Color(0xFF15151F),
    surfaceHi: Color(0xFF1F1F2E),
    accent: Color(0xFFFF3D71),
    accent2: Color(0xFFFFB02E),
    text: Color(0xFFF2F2F7),
    muted: Color(0xFF8C8CA1),
    line: Color(0x14FFFFFF),
  );
  static const control = LayoutPalette(
    bg: Color(0xFF090D13),
    surface: Color(0xFF0C121A),
    surfaceHi: Color(0xFF1B2A3A),
    accent: Color(0xFFFFB02E),
    accent2: Color(0xFFFF3D71),
    text: Color(0xFFEAF0F7),
    muted: Color(0xFF8EA0B4),
    line: Color(0xFF1D2733),
  );
  static const spotlight = LayoutPalette(
    bg: Color(0xFF140C1D),
    surface: Color(0xFF1E1430),
    surfaceHi: Color(0xFF2C1F42),
    accent: Color(0xFFFF3D71),
    accent2: Color(0xFF7D6DFF),
    text: Color(0xFFF4EEFB),
    muted: Color(0xFFB3A6C8),
    line: Color(0x1FFFFFFF),
  );

  static LayoutPalette forLayout(UiLayout l) => switch (l) {
        UiLayout.marquee => marquee,
        UiLayout.control => control,
        UiLayout.spotlight => spotlight,
      };

  /// The palette of the current theme; Marquee's when none is installed (tests, previews).
  static LayoutPalette of(BuildContext context) =>
      Theme.of(context).extension<LayoutPalette>() ?? marquee;

  @override
  LayoutPalette copyWith(
          {Color? bg,
          Color? surface,
          Color? surfaceHi,
          Color? accent,
          Color? accent2,
          Color? text,
          Color? muted,
          Color? line}) =>
      LayoutPalette(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHi: surfaceHi ?? this.surfaceHi,
        accent: accent ?? this.accent,
        accent2: accent2 ?? this.accent2,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        line: line ?? this.line,
      );

  @override
  LayoutPalette lerp(ThemeExtension<LayoutPalette>? other, double t) {
    if (other is! LayoutPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return LayoutPalette(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceHi: l(surfaceHi, other.surfaceHi),
      accent: l(accent, other.accent),
      accent2: l(accent2, other.accent2),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      line: l(line, other.line),
    );
  }
}
