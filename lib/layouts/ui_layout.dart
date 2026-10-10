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
      'Big type and almost no posters. A list of words that opens what is inside. Light to run.'),
  glass('Glass',
      'Frosted panels floating over a soft colored backdrop, with a small dock at the bottom.'),
  bento('Bento',
      'Home is a board of flat colored tiles: continue, live now, a guide strip, your list and search.'),
  library('Library',
      'Like a media server: a tree on the left, dense rows on the right, a thin breadcrumb on top.'),
  orbit('Orbit',
      'A big dial. Spin it to a section and its titles fan out beside it. Left and Right turn it.'),
  mood('Mood',
      'Asks what you are in the mood for, then shows a shelf for it. Calm, spacious, one idea at a time.'),
  mosaic('Mosaic',
      'Four channel tiles at once with the sound on one of them. Made for sport and news days.'),
  tonight('Tonight',
      'An evening planner. One timeline of what is on now, what starts later, what you are halfway through and what you saved.'),
  globe('Globe',
      'Live TV by country. A dotted world map with a pin on every country that has channels; pick one to see its channels.'),
  playground('Playground',
      'Made for a Kids profile. Big colored tiles, a keep-watching card, a bedtime timer and no menu. Grown-ups asks for the PIN.'),
  console('Console',
      'A prompt. Type to find channels, movies and series as you type, or start with a slash for a command. Plain and fast.'),
  deck('Deck',
      'A deck of picks for tonight. Skip, save or play with four keys, or swipe on a phone.');

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

  /// Glass draws panels as translucent fills over the backdrop (and blurs them off a TV).
  final bool frosted;
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
    this.frosted = false,
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

  static const glass = LayoutPalette(
    bg: Color(0xFF0D2F4A),
    surface: Color(0xFF16405F),
    surfaceHi: Color(0xFF225778),
    accent: Color(0xFFBFE9FF),
    accent2: Color(0xFFFFAA78),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFFB5D2E6),
    line: Color(0x52FFFFFF),
    frosted: true,
  );
  static const bento = LayoutPalette(
    bg: Color(0xFF17141F),
    surface: Color(0xFF2A2535),
    surfaceHi: Color(0xFF3A3447),
    accent: Color(0xFFFF5A3C),
    accent2: Color(0xFFFFD23F),
    text: Color(0xFFF6F4F1),
    muted: Color(0xFFA8A2B5),
    line: Color(0xFF3A3447),
  );
  static const library = LayoutPalette(
    bg: Color(0xFF20272E),
    surface: Color(0xFF181E24),
    surfaceHi: Color(0xFF2B343C),
    accent: Color(0xFFCFA95B),
    accent2: Color(0xFF8DB07A),
    text: Color(0xFFDBE1E6),
    muted: Color(0xFF93A0AB),
    line: Color(0xFF333D47),
  );

  static const orbit = LayoutPalette(
    bg: Color(0xFF2A0E1E),
    surface: Color(0xFF3A1428),
    surfaceHi: Color(0xFF4A1A35),
    accent: Color(0xFFF0CF86),
    accent2: Color(0xFFB9CBA7),
    text: Color(0xFFE6ECD8),
    muted: Color(0xFFBBA6B0),
    line: Color(0x66F0CF86),
  );
  static const mood = LayoutPalette(
    bg: Color(0xFF131E3B),
    surface: Color(0xFF243059),
    surfaceHi: Color(0xFF33406F),
    accent: Color(0xFFFFD0B0),
    accent2: Color(0xFFD9A199),
    text: Color(0xFFFDF1EE),
    muted: Color(0xFFCBC5E2),
    line: Color(0x40FFFFFF),
  );
  static const mosaic = LayoutPalette(
    bg: Color(0xFF0F5B30),
    surface: Color(0xFF0B3A20),
    surfaceHi: Color(0xFF14693A),
    accent: Color(0xFFFFD400),
    accent2: Color(0xFFF2F6EE),
    text: Color(0xFFF2F6EE),
    muted: Color(0xFFCFE0C8),
    line: Color(0x4DF2F6EE),
  );

  static const tonight = LayoutPalette(
    bg: Color(0xFFF1E8D4),
    surface: Color(0xFFFFFAF0),
    surfaceHi: Color(0xFFE9DCC0),
    accent: Color(0xFFA83A20),
    accent2: Color(0xFF5B6B3A),
    text: Color(0xFF241D14),
    muted: Color(0xFF7A6A4E),
    line: Color(0xFFD9CCB0),
    brightness: Brightness.light,
  );

  static const globe = LayoutPalette(
    bg: Color(0xFF070B1D),
    surface: Color(0xFF10163A),
    surfaceHi: Color(0xFF1B2358),
    accent: Color(0xFFFF6F61),
    accent2: Color(0xFF8FA4FF),
    text: Color(0xFFE8ECFF),
    muted: Color(0xFF8F9BD6),
    line: Color(0xFF2B3570),
  );
  static const playground = LayoutPalette(
    bg: Color(0xFFFFF4DC),
    surface: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFFFE4A3),
    accent: Color(0xFF7C5CFF),
    accent2: Color(0xFFFF5A5F),
    text: Color(0xFF2B2350),
    muted: Color(0xFF6D6590),
    line: Color(0x1F2B2350),
    brightness: Brightness.light,
  );

  static const console = LayoutPalette(
    bg: Color(0xFF110C04),
    surface: Color(0xFF1D1507),
    surfaceHi: Color(0xFF2B2008),
    accent: Color(0xFFFFB000),
    accent2: Color(0xFFC9A24D),
    text: Color(0xFFFFF0CC),
    muted: Color(0xFF8F7231),
    line: Color(0xFF3B2F12),
  );
  static const deck = LayoutPalette(
    bg: Color(0xFF1735D6),
    surface: Color(0xFF2A4BFF),
    surfaceHi: Color(0xFF0F2299),
    accent: Color(0xFFFF7A1A),
    accent2: Color(0xFFFFB266),
    text: Color(0xFFFFF4E0),
    muted: Color(0xFFCFD8FF),
    line: Color(0x66FFF4E0),
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
        UiLayout.glass => glass,
        UiLayout.bento => bento,
        UiLayout.library => library,
        UiLayout.orbit => orbit,
        UiLayout.mood => mood,
        UiLayout.mosaic => mosaic,
        UiLayout.tonight => tonight,
        UiLayout.globe => globe,
        UiLayout.playground => playground,
        UiLayout.console => console,
        UiLayout.deck => deck,
      };

  /// The palette of the current theme; Marquee's when none is installed (tests, previews).
  /// Background looks the viewer can pick over a layout's own: key, label, and the colors.
  static const backgrounds = <String, (String, Color bg, Color surface, Color surfaceHi, Color text, Color muted, Color line, Brightness)>{
    'black': ('Black', Color(0xFF000000), Color(0xFF0B0B0B), Color(0xFF181818), Color(0xFFF2F2F2), Color(0xFF8A8A8A), Color(0x1FFFFFFF), Brightness.dark),
    'charcoal': ('Charcoal', Color(0xFF121212), Color(0xFF1C1C1E), Color(0xFF2A2A2D), Color(0xFFF2F2F2), Color(0xFF9A9AA0), Color(0x1FFFFFFF), Brightness.dark),
    'midnight': ('Midnight', Color(0xFF0A0F1F), Color(0xFF111A33), Color(0xFF1B2850), Color(0xFFEEF2FB), Color(0xFF93A3C8), Color(0x1FFFFFFF), Brightness.dark),
    'forest': ('Forest', Color(0xFF08120D), Color(0xFF0F1F17), Color(0xFF18362A), Color(0xFFEAF5EE), Color(0xFF8DAA9A), Color(0x1FFFFFFF), Brightness.dark),
    'plum': ('Plum', Color(0xFF140A18), Color(0xFF21122A), Color(0xFF341C42), Color(0xFFF6EEFA), Color(0xFFB6A3C4), Color(0x1FFFFFFF), Brightness.dark),
    'paper': ('Paper', Color(0xFFF7F5F0), Color(0xFFFFFFFF), Color(0xFFECE8DF), Color(0xFF1B1B1F), Color(0xFF6B6B76), Color(0x1A000000), Brightness.light),
  };

  /// This palette with the viewer's accent color and background look on top. [background] is a key of
  /// [backgrounds]; anything else (or [keepBackground]) leaves the layout's own colors.
  LayoutPalette customized({Color? accent, String background = 'layout', bool keepBackground = false}) {
    var p = this;
    final b = keepBackground ? null : backgrounds[background];
    if (b != null) {
      p = p.copyWith(bg: b.$2, surface: b.$3, surfaceHi: b.$4, text: b.$5, muted: b.$6, line: b.$7, brightness: b.$8);
    }
    if (accent != null) p = p.copyWith(accent: accent);
    return p;
  }

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
          Brightness? brightness,
          bool? frosted}) =>
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
        frosted: frosted ?? this.frosted,
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
      frosted: t < 0.5 ? frosted : other.frosted,
    );
  }
}
