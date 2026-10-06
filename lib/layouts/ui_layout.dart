import 'package:flutter/material.dart';

/// The selectable looks (Settings > Appearance > Layout). Each one changes the navigation,
/// the Home screen and the browse screens, and carries its own palette.
enum UiLayout {
  marquee('Marquee',
      'Cinematic. One big feature on Home, a slim icon rail, rows of posters.'),
  control('Control Room',
      'Channel-first. Categories, a numbered channel list with what is on now, and a details pane.'),
  spotlight('Spotlight',
      'A poster wall. The focused title gets a details panel; navigation is one pill.'),
  prime('Prime Time',
      'The TV guide is Home: details of the highlighted show above a time grid of every channel.'),
  coverflow('Coverflow',
      'One big poster at a time with its neighbors fanned out. Flip through and press play.'),
  hub('Hub',
      'A launcher of big colored tiles, with what you were watching underneath. Nothing to learn.'),
  daylight('Daylight',
      'The light layout. White cards on soft grey, one green accent, a feature card and what is live.'),
  cable('Cable Box',
      'Opens on a channel with a banner like a cable box. Up and Down change channel, OK plays.'),
  indexList('Index',
      'Big type and almost no posters. A list of words that opens what is inside. Light to run.');

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

  /// Light palettes (Daylight) flip the Material theme to light and the focus ring to ink.
  final Brightness brightness;
  const LayoutPalette({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.accent,
    required this.accent2,
    required this.text,
    required this.muted,
    required this.line,
    this.brightness = Brightness.dark,
  });

  bool get light => brightness == Brightness.light;

  /// The outline on a focused control on a TV: white on dark layouts, ink on light ones.
  Color get ring => light ? text : Colors.white;

  /// A faint wash of the text color, for chips and fields that sit on the background.
  Color wash([double alpha = 0.10]) => text.withValues(alpha: alpha);

  /// Text that sits on [accent]: dark on a bright accent, white on a dark one.
  Color get onAccent => accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;

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

  static const prime = LayoutPalette(
    bg: Color(0xFF0A1020),
    surface: Color(0xFF101A33),
    surfaceHi: Color(0xFF1A2A52),
    accent: Color(0xFF4C8DFF),
    accent2: Color(0xFFFFD166),
    text: Color(0xFFEEF2FB),
    muted: Color(0xFF93A3C8),
    line: Color(0xFF1B2748),
  );
  static const coverflow = LayoutPalette(
    bg: Color(0xFF0E0B0A),
    surface: Color(0xFF1A1412),
    surfaceHi: Color(0xFF2A201B),
    accent: Color(0xFFFF6A3D),
    accent2: Color(0xFFF3E9DC),
    text: Color(0xFFF3E9DC),
    muted: Color(0xFFA89A8C),
    line: Color(0x1FF3E9DC),
  );
  static const hub = LayoutPalette(
    bg: Color(0xFF12131A),
    surface: Color(0xFF1B1C26),
    surfaceHi: Color(0xFF262836),
    accent: Color(0xFF35D0BA),
    accent2: Color(0xFFFF5D8F),
    text: Color(0xFFF2F2F7),
    muted: Color(0xFF9A9BB2),
    line: Color(0x14FFFFFF),
  );

  static const daylight = LayoutPalette(
    bg: Color(0xFFECEFF3),
    surface: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFE2E7EE),
    accent: Color(0xFF0E9F6E),
    accent2: Color(0xFF0B7A55),
    text: Color(0xFF111827),
    muted: Color(0xFF566070),
    line: Color(0xFFDDE2EA),
    brightness: Brightness.light,
  );
  static const cable = LayoutPalette(
    bg: Color(0xFF05070A),
    surface: Color(0xFF0B1116),
    surfaceHi: Color(0xFF16222B),
    accent: Color(0xFFFFB000),
    accent2: Color(0xFF3DFF8A),
    text: Color(0xFFFFE0A3),
    muted: Color(0xFFC99A3C),
    line: Color(0x66FFB000),
  );
  static const indexList = LayoutPalette(
    bg: Color(0xFF1D33F0),
    surface: Color(0xFF142BD0),
    surfaceHi: Color(0xFF0B0F3A),
    accent: Color(0xFFF7E733),
    accent2: Color(0xFFF7E733),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFFCBD2FF),
    line: Color(0x61FFFFFF),
  );

  static LayoutPalette forLayout(UiLayout l) => switch (l) {
        UiLayout.marquee => marquee,
        UiLayout.control => control,
        UiLayout.spotlight => spotlight,
        UiLayout.prime => prime,
        UiLayout.coverflow => coverflow,
        UiLayout.hub => hub,
        UiLayout.daylight => daylight,
        UiLayout.cable => cable,
        UiLayout.indexList => indexList,
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
          Color? line,
          Brightness? brightness}) =>
      LayoutPalette(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceHi: surfaceHi ?? this.surfaceHi,
        accent: accent ?? this.accent,
        accent2: accent2 ?? this.accent2,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        brightness: brightness ?? this.brightness,
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
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}
