import 'dart:math' as math;
import 'dart:ui' show PointMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/browse_screen.dart';
import '../screens/open_item.dart';
import '../services/countries.dart';
import '../state/app_state.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'ui_layout.dart';

/// Simplified outlines of the continents as (longitude, latitude) points. They are only dotted in, so
/// they need to be recognisable, not exact.
const _land = <List<(double, double)>>[
  [
    (-168, 66),
    (-140, 70),
    (-120, 72),
    (-95, 72),
    (-80, 68),
    (-62, 60),
    (-55, 50),
    (-67, 44),
    (-76, 36),
    (-81, 25),
    (-97, 26),
    (-105, 20),
    (-92, 15),
    (-83, 9),
    (-78, 9),
    (-86, 14),
    (-105, 22),
    (-117, 32),
    (-124, 40),
    (-125, 49),
    (-135, 58),
    (-150, 60),
    (-165, 60)
  ],
  [(-55, 60), (-45, 60), (-20, 70), (-20, 82), (-50, 83), (-70, 78), (-60, 68)],
  [
    (-78, 9),
    (-62, 10),
    (-50, 0),
    (-35, -6),
    (-39, -15),
    (-48, -26),
    (-58, -38),
    (-66, -46),
    (-70, -54),
    (-74, -50),
    (-72, -30),
    (-70, -18),
    (-81, -6),
    (-80, 2)
  ],
  [
    (-10, 36),
    (-9, 43),
    (-2, 48),
    (-5, 52),
    (5, 60),
    (10, 64),
    (20, 70),
    (30, 70),
    (40, 66),
    (40, 56),
    (30, 46),
    (28, 41),
    (22, 37),
    (12, 38),
    (8, 44),
    (0, 38)
  ],
  [(-6, 50), (2, 51), (0, 58), (-6, 58)],
  [
    (-17, 21),
    (-6, 35),
    (10, 37),
    (32, 31),
    (35, 28),
    (43, 12),
    (51, 12),
    (40, -3),
    (40, -15),
    (35, -25),
    (20, -35),
    (14, -22),
    (12, -5),
    (9, 4),
    (-8, 4),
    (-17, 14)
  ],
  [
    (30, 46),
    (40, 66),
    (60, 70),
    (100, 77),
    (140, 72),
    (170, 68),
    (180, 66),
    (160, 58),
    (142, 50),
    (130, 42),
    (122, 30),
    (110, 20),
    (105, 10),
    (100, 2),
    (98, 16),
    (88, 22),
    (80, 10),
    (72, 20),
    (58, 24),
    (50, 30),
    (36, 34),
    (30, 36),
    (28, 41)
  ],
  [(130, 32), (140, 36), (142, 44), (138, 38)],
  [
    (114, -22),
    (130, -12),
    (142, -11),
    (153, -26),
    (147, -38),
    (135, -35),
    (115, -34)
  ],
];

bool _inside(double lon, double lat, List<(double, double)> poly) {
  var c = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final (xi, yi) = poly[i];
    final (xj, yj) = poly[j];
    if ((yi > lat) != (yj > lat) &&
        lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
      c = !c;
    }
  }
  return c;
}

/// Dots covering the land, in map units (0 to 200 across, 0 to 100 down). Computed once.
final List<Offset> _dots = () {
  final out = <Offset>[];
  const step = 1.7;
  for (var y = 0.85; y < 100; y += step) {
    for (var x = 0.85; x < 200; x += step) {
      final lon = x / 200 * 360 - 180, lat = 90 - y / 100 * 180;
      if (_land.any((p) => _inside(lon, lat, p))) out.add(Offset(x, y));
    }
  }
  return out;
}();

Offset _pos(Country c) =>
    Offset((c.lon + 180) / 360 * 200, (90 - c.lat) / 180 * 100);

class _MapPainter extends CustomPainter {
  final List<CountryGroup> groups;
  final Country? selected;
  final LayoutPalette p;
  final bool compact;
  _MapPainter(this.groups, this.selected, this.p, this.compact);

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / 200, size.height / 100);
    final ox = (size.width - 200 * k) / 2, oy = (size.height - 100 * k) / 2;
    Offset at(Offset m) => Offset(ox + m.dx * k, oy + m.dy * k);

    final grid = Paint()
      ..color = p.line.withValues(alpha: 0.5)
      ..strokeWidth = 0.6;
    for (var lon = -150; lon <= 150; lon += 30) {
      final x = (lon + 180) / 1.8;
      canvas.drawLine(at(Offset(x, 0)), at(Offset(x, 100)), grid);
    }
    for (final lat in [-60, -30, 0, 30, 60]) {
      final y = (90 - lat) / 1.8;
      canvas.drawLine(at(Offset(0, y)), at(Offset(200, y)), grid);
    }
    canvas.drawPoints(
      PointMode.points,
      [for (final d in _dots) at(d)],
      Paint()
        ..color = p.accent2.withValues(alpha: 0.75)
        ..strokeWidth = k * 1.05
        ..strokeCap = StrokeCap.round,
    );

    final top =
        groups.take(compact ? 8 : 14).map((g) => g.country.code).toSet();
    for (final g in groups) {
      final c = at(_pos(g.country));
      final sel = g.country.code == selected?.code;
      final r =
          (sel ? 4.2 : 1.6 + math.min(1.6, math.sqrt(g.channels.length) / 14)) *
              k;
      if (sel) {
        canvas.drawCircle(
            c, r * 1.7, Paint()..color = p.accent.withValues(alpha: 0.25));
      }
      canvas.drawCircle(c, r,
          Paint()..color = sel ? p.accent : p.text.withValues(alpha: 0.85));
      if (sel) canvas.drawCircle(c, r * 0.38, Paint()..color = p.bg);
      if (sel || top.contains(g.country.code)) {
        final tp = TextPainter(
          text: TextSpan(
            text: sel
                ? '${g.country.name} ${g.channels.length}'
                : '${g.channels.length}',
            style: TextStyle(
                color: sel ? Colors.white : p.text.withValues(alpha: 0.85),
                fontSize: (sel ? 6.0 : 4.4) * k,
                fontWeight: sel ? FontWeight.w800 : FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final dx = sel ? -tp.width - r * 1.4 : r * 1.6;
        tp.paint(canvas, c + Offset(dx, sel ? r * 0.9 : -tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_MapPainter o) =>
      o.selected?.code != selected?.code || o.groups != groups || o.p != p;
}

/// Globe's Home: live TV by country. A dotted world map with a pin on every country that has channels;
/// arrow keys hop between pins, and the channels of the chosen country list beside (or below) it.
class GlobeHome extends StatefulWidget {
  const GlobeHome({super.key});

  @override
  State<GlobeHome> createState() => _GlobeHomeState();
}

class _GlobeHomeState extends State<GlobeHome> {
  final _mapNode = FocusNode(debugLabel: 'globe map');
  final _list = FocusScopeNode(debugLabel: 'globe list');
  String? _code;
  int _chip = 0;

  List<CountryGroup> _groups = const [];
  Object? _groupsFor;
  int _groupsLen = -1;

  @override
  void dispose() {
    _mapNode.dispose();
    _list.dispose();
    super.dispose();
  }

  List<CountryGroup> _groupsOf(AppState s) {
    final live = s.shown.live;
    if (!identical(_groupsFor, live) || _groupsLen != live.length) {
      _groupsFor = live;
      _groupsLen = live.length;
      _groups = groupByCountry(s.shown);
    }
    return _groups;
  }

  /// Where to start: the country of the channels watched most lately, else the biggest.
  String _start(AppState s, List<CountryGroup> groups) {
    final counts = <String, int>{};
    for (final r in s.recents) {
      if (r.kind != MediaKind.live) continue;
      for (final g in groups) {
        if (g.channels.any((c) => c.key == r.key)) {
          counts[g.country.code] = (counts[g.country.code] ?? 0) + 1;
        }
      }
    }
    if (counts.isNotEmpty) {
      return (counts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
    }
    return groups.first.country.code;
  }

  void _select(String code) {
    if (code == _code) return;
    setState(() {
      _code = code;
      _chip = 0;
    });
  }

  KeyEventResult _mapKey(KeyEvent e, List<CountryGroup> groups, Size size) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final cur = groups.firstWhere((g) => g.country.code == _code,
        orElse: () => groups.first);
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter) {
      _list.requestFocus();
      return KeyEventResult.handled;
    }
    final dir = key == LogicalKeyboardKey.arrowLeft
        ? const Offset(-1, 0)
        : key == LogicalKeyboardKey.arrowRight
            ? const Offset(1, 0)
            : key == LogicalKeyboardKey.arrowUp
                ? const Offset(0, -1)
                : key == LogicalKeyboardKey.arrowDown
                    ? const Offset(0, 1)
                    : null;
    if (dir == null) return KeyEventResult.ignored;
    final from = _pos(cur.country);
    CountryGroup? best;
    var bestScore = double.infinity;
    for (final g in groups) {
      if (g.country.code == cur.country.code) continue;
      final v = _pos(g.country) - from;
      final d = v.distance;
      if (d == 0) continue;
      final along = (v.dx * dir.dx + v.dy * dir.dy) / d;
      if (along < 0.5) {
        continue; // within about 60 degrees of the direction pressed
      }
      final score = d * (2 - along);
      if (score < bestScore) {
        bestScore = score;
        best = g;
      }
    }
    if (best == null) {
      return KeyEventResult.ignored; // let focus move on (down to the chips)
    }
    _select(best.country.code);
    return KeyEventResult.handled;
  }

  void _tapMap(Offset local, Size size, List<CountryGroup> groups) {
    final k = math.min(size.width / 200, size.height / 100);
    final ox = (size.width - 200 * k) / 2, oy = (size.height - 100 * k) / 2;
    CountryGroup? best;
    var bd = 28.0;
    for (final g in groups) {
      final m = _pos(g.country);
      final d = (Offset(ox + m.dx * k, oy + m.dy * k) - local).distance;
      if (d < bd) {
        bd = d;
        best = g;
      }
    }
    if (best != null) _select(best.country.code);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final groups = _groupsOf(s);

    if (groups.length < 2) {
      // Not enough country names to draw a map: say so and show the plain channel list.
      return Column(children: [
        Container(
          width: double.infinity,
          color: p.surface,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Text(
            'These channels do not name their countries, so there is no map to show. Here is the channel list instead.',
            style: TextStyle(color: p.muted, fontSize: wide ? 16 : 13),
          ),
        ),
        Expanded(child: BrowseScreen(kind: MediaKind.live, catalog: s.shown)),
      ]);
    }

    final code =
        groups.any((g) => g.country.code == _code) ? _code! : _start(s, groups);
    final group = groups.firstWhere((g) => g.country.code == code);

    // Category chips: the biggest groups within this country, by name without the country.
    final labelOf = {
      for (final c in s.shown.liveCategories) c.id: categoryLabel(c.name)
    };
    final counts = <String, int>{};
    for (final ch in group.channels) {
      final l = labelOf[ch.categoryId] ?? 'General';
      counts[l] = (counts[l] ?? 0) + 1;
    }
    final chipNames = (counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .toList();
    final chip = _chip.clamp(0, chipNames.length);
    final shown = chip == 0
        ? group.channels
        : [
            for (final ch in group.channels)
              if ((labelOf[ch.categoryId] ?? 'General') ==
                  chipNames[chip - 1].key)
                ch
          ];

    Widget chipW(int i, String label, int n) {
      final on = i == chip;
      return FocusSurface(
        radius: 24,
        semanticLabel: '$label $n',
        onTap: () => setState(() => _chip = i),
        builder: (_, __) => Container(
          padding: EdgeInsets.symmetric(
              horizontal: wide ? 18 : 13, vertical: wide ? 8 : 6),
          decoration: BoxDecoration(
            color: on ? p.accent : Colors.transparent,
            border: Border.all(color: on ? p.accent : p.line),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: label,
                    style: TextStyle(
                        fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                        color: on ? p.onAccent : p.text)),
                TextSpan(
                    text: '  $n',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: on ? p.onAccent : p.muted)),
              ]),
              style: TextStyle(fontSize: wide ? 16 : 13)),
        ),
      );
    }

    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chipW(0, 'All', group.channels.length),
        for (var i = 0; i < chipNames.length; i++)
          Padding(
              padding: const EdgeInsets.only(left: 8),
              child: chipW(i + 1, chipNames[i].key, chipNames[i].value)),
      ]),
    );

    Widget row(int i, MediaItem ch) {
      final now = s.programmesFor(ch).where((x) => x.isNow);
      final sub = now.isEmpty
          ? (labelOf[ch.categoryId] ?? 'Live')
          : 'now: ${now.first.title}';
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: FocusSurface(
          radius: 12,
          semanticLabel: ch.name,
          onTap: () => openItem(context, ch, queue: shown),
          builder: (_, __) => Container(
            height: wide ? 60 : 56,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.line)),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: p.text, borderRadius: BorderRadius.circular(8)),
                child: Text('${i + 1}',
                    style: TextStyle(
                        color: p.bg,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: wide ? 17 : 15,
                              color: p.text)),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: wide ? 13 : 12, color: p.muted)),
                    ]),
              ),
              Text('LIVE',
                  style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.2)),
            ]),
          ),
        ),
      );
    }

    Widget map(double height) => LayoutBuilder(builder: (context, box) {
          final size = Size(box.maxWidth, height);
          return Focus(
            focusNode: _mapNode,
            autofocus: tv,
            onKeyEvent: (_, e) => _mapKey(e, groups, size),
            child: Builder(builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return GestureDetector(
                onTapDown: (d) {
                  _mapNode.requestFocus();
                  _tapMap(d.localPosition, size, groups);
                },
                child: Container(
                  width: double.infinity,
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: focused && tv ? p.ring : Colors.transparent,
                        width: 2),
                  ),
                  child: CustomPaint(
                      painter: _MapPainter(groups, group.country, p, !wide)),
                ),
              );
            }),
          );
        });

    final header =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(group.country.name,
          style: TextStyle(
              fontSize: wide ? 44 : 32,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -1,
              color: p.text)),
      const SizedBox(height: 6),
      Text(
          '${group.channels.length} ${group.channels.length == 1 ? 'channel' : 'channels'}',
          style: TextStyle(color: p.muted, fontSize: wide ? 17 : 14)),
    ]);

    final list = Focus(
      canRequestFocus: false,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _mapNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FocusScope(
          node: _list,
          child: Column(children: [
            for (var i = 0; i < shown.length; i++) row(i, shown[i])
          ])),
    );

    if (!wide) {
      return ColoredBox(
        color: p.bg,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              map(170),
              const SizedBox(height: 10),
              header,
              const SizedBox(height: 12),
              chips,
              const SizedBox(height: 12),
              list,
            ]),
      );
    }
    return ColoredBox(
      color: p.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 62,
            child: LayoutBuilder(builder: (context, box) {
              final mapH = math.min(box.maxWidth / 2, box.maxHeight - 140);
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    map(math.max(mapH, 120)),
                    const SizedBox(height: 14),
                    header,
                    const SizedBox(height: 14),
                    chips,
                  ]);
            }),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 36,
            child: Container(
              decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.line)),
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.country.name,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: p.text)),
                    Text('What is on now',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                    const SizedBox(height: 10),
                    Expanded(child: SingleChildScrollView(child: list)),
                  ]),
            ),
          ),
        ]),
      ),
    );
  }
}
