import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'hub_view.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// One stop on the dial.
class _Stop {
  final String label;
  final IconData icon;
  final int? tab; // null = My list
  const _Stop(this.label, this.icon, this.tab);
}

const _stops = [
  _Stop('Live', Icons.live_tv_outlined, 1),
  _Stop('Movies', Icons.movie_outlined, 3),
  _Stop('Series', Icons.tv_outlined, 4),
  _Stop('Guide', Icons.view_list_outlined, 2),
  _Stop('My list', Icons.favorite_border, null),
  _Stop('Search', Icons.search, 5),
  _Stop('Settings', Icons.settings_outlined, 6),
];

/// Orbit's Home: the sections sit on a big dial. Left and Right (or a swipe, or a tap on a label)
/// spin it, Up and Down pick one of the titles fanned out beside it, OK opens that title or, with
/// none picked, the section. On a phone the dial rises from the bottom edge.
class OrbitHome extends StatefulWidget {
  const OrbitHome({super.key});

  @override
  State<OrbitHome> createState() => _OrbitHomeState();
}

class _OrbitHomeState extends State<OrbitHome> {
  int _pos = 1; // unbounded dial position; the front stop is _pos mod 7
  int? _item; // highlighted fan item after Up or Down

  int get _front => ((_pos % _stops.length) + _stops.length) % _stops.length;

  void _spin(int by) => setState(() {
        _pos += by;
        _item = null;
      });

  List<MediaItem> _fan(AppState s) {
    final c = s.shown;
    final items = switch (_stops[_front].label) {
      'Live' => c.live,
      'Movies' => c.movies,
      'Series' => c.series,
      'Guide' => c.live,
      'My list' => s.favoriteItems,
      _ => const <MediaItem>[],
    };
    return items.take(5).toList();
  }

  void _enter() {
    final stop = _stops[_front];
    if (stop.tab == null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FavoritesPage()));
    } else {
      ShellNav.maybeOf(context)?.select(stop.tab!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final fan = _fan(s);
    final stop = _stops[_front];

    final dial = _Dial(pos: _pos, wide: wide, onTapStop: (i) {
      // Tapping the front label enters it; any other label spins it to the front.
      final d = ((i - _front + 3) % _stops.length) - 3;
      if (d == 0) {
        _enter();
      } else {
        _spin(d);
      }
    });

    final fanView = _Fan(
      stop: stop,
      items: fan,
      picked: _item,
      wide: wide,
      onOpen: (it) => openItem(context, it, queue: it.kind == MediaKind.live ? fan : null),
      onEnter: _enter,
    );

    return Focus(
      autofocus: tv,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowLeft) {
          _spin(-1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowRight) {
          _spin(1);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown && fan.isNotEmpty) {
          setState(() => _item = _item == null ? 0 : math.min(fan.length - 1, _item! + 1));
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp && fan.isNotEmpty) {
          setState(() => _item = _item == null ? 0 : math.max(0, _item! - 1));
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
          final it = _item;
          if (it != null && it < fan.length) {
            openItem(context, fan[it], queue: fan[it].kind == MediaKind.live ? fan : null);
          } else {
            _enter();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 200) _spin(v < 0 ? 1 : -1);
        },
        child: wide
            ? Row(children: [
                SizedBox(width: 470, child: dial),
                Expanded(child: fanView),
              ])
            : Column(children: [
                Expanded(child: fanView),
                SizedBox(height: 250, child: dial),
              ]),
      ),
    );
  }
}

/// The ring of labels. The front stop sits at the right of the ring on a wide screen and at the
/// top on a phone; the rest are spread around it.
class _Dial extends StatelessWidget {
  final int pos;
  final bool wide;
  final ValueChanged<int> onTapStop;
  const _Dial({required this.pos, required this.wide, required this.onTapStop});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final n = _stops.length;
    return LayoutBuilder(builder: (context, c) {
      final r = wide ? math.min(c.maxHeight * 0.4, 260.0) : math.min(c.maxWidth * 0.62, 240.0);
      // Ring centre: off the left edge on a wide screen, below the bottom edge on a phone.
      final cx = wide ? r * 0.28 : c.maxWidth / 2;
      final cy = wide ? c.maxHeight / 2 : c.maxHeight + r * 0.42;
      final front = wide ? 0.0 : -math.pi / 2;
      const step = 2 * math.pi / 11; // a little tighter than an even split so labels never touch
      return TweenAnimationBuilder<double>(
        tween: Tween(end: pos.toDouble()),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) {
          final tag = <Widget>[];
          for (var i = 0; i < n; i++) {
            // Shortest distance round the ring from the front stop.
            var d = (i - v) % n;
            if (d > n / 2) d -= n;
            final a = front + d * step;
            if (d.abs() > 3.2) continue;
            final x = cx + r * math.cos(a);
            final y = cy + r * math.sin(a);
            final near = (1 - d.abs() / 3.4).clamp(0.2, 1.0).toDouble();
            final isFront = d.abs() < 0.5;
            tag.add(Positioned(
              left: x - (wide ? 20 : 54),
              top: y - 22,
              child: Opacity(
                opacity: near,
                child: InkWell(
                  onTap: () => onTapStop(i),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isFront ? p.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_stops[i].icon, size: 20, color: isFront ? p.onAccent : p.accent2),
                      const SizedBox(width: 8),
                      Text(_stops[i].label,
                          style: TextStyle(
                              color: isFront ? p.onAccent : p.text,
                              fontSize: isFront ? 20 : 17,
                              fontWeight: isFront ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ));
          }
          return ClipRect(
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _Ring(cx, cy, r, p.accent, p.line, v, step, front))),
              ...tag,
            ]),
          );
        },
      );
    });
  }
}

class _Ring extends CustomPainter {
  final double cx, cy, r, pos, step, front;
  final Color accent, line;
  const _Ring(this.cx, this.cy, this.r, this.accent, this.line, this.pos, this.step, this.front);

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = line;
    canvas.drawCircle(Offset(cx, cy), r, ring);
    canvas.drawCircle(Offset(cx, cy), r * 0.78, ring..color = line.withValues(alpha: 0.5));
    // Brass ticks that turn with the dial.
    final tick = Paint()
      ..strokeWidth = 2
      ..color = accent.withValues(alpha: 0.8);
    for (var k = 0; k < 44; k++) {
      final a = front + (k / 44) * 2 * math.pi - pos * step;
      final long = k % 4 == 0;
      final r1 = r * (long ? 0.86 : 0.9);
      final r2 = r * 0.96;
      canvas.drawLine(Offset(cx + r1 * math.cos(a), cy + r1 * math.sin(a)), Offset(cx + r2 * math.cos(a), cy + r2 * math.sin(a)), tick);
    }
    // The index mark at the front.
    final idx = Paint()..color = accent;
    canvas.drawCircle(Offset(cx + (r * 1.1) * math.cos(front), cy + (r * 1.1) * math.sin(front)), 5, idx);
  }

  @override
  bool shouldRepaint(_Ring old) => old.pos != pos || old.r != r || old.cx != cx || old.cy != cy;
}

/// The titles of the front section, fanned out in a shallow arc.
class _Fan extends StatelessWidget {
  final _Stop stop;
  final List<MediaItem> items;
  final int? picked;
  final bool wide;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback onEnter;
  const _Fan({required this.stop, required this.items, required this.picked, required this.wide, required this.onOpen, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 8 : 20, wide ? 24 : 12, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(stop.label,
                style: TextStyle(fontSize: wide ? 40 : 30, fontWeight: FontWeight.w800, color: p.text, letterSpacing: -0.5)),
          ),
          FocusSurface(
            radius: 22,
            semanticLabel: 'Open ${stop.label}',
            onTap: onEnter,
            builder: (_, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: p.wash(0.12),
              child: Text('Open', style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                stop.label == 'My list' ? 'Nothing saved yet. Add titles from their pages.' : 'Turn the dial, or press OK to open ${stop.label}.',
                style: TextStyle(color: p.muted, fontSize: 18)),
          ),
        for (var i = 0; i < items.length; i++)
          Builder(builder: (context) {
            // A shallow arc: the middle of the fan sticks out most.
            final off = (wide ? 26.0 : 10.0) * (1 - ((i - (items.length - 1) / 2).abs() / math.max(1, items.length / 2)));
            final on = picked == i;
            return Padding(
              padding: EdgeInsets.only(left: off, bottom: 6),
              child: FocusSurface(
                radius: 14,
                semanticLabel: items[i].name,
                onTap: () => onOpen(items[i]),
                builder: (_, __) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: on ? p.accent : p.surfaceHi,
                    border: Border.all(color: on ? p.ring : p.line, width: on ? 3 : 1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Icon(items[i].kind == MediaKind.live ? Icons.live_tv : Icons.play_circle_outline,
                        color: on ? p.onAccent : p.accent, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(items[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: on ? p.onAccent : p.text, fontSize: tv ? 20 : 17, fontWeight: FontWeight.w700))),
                  ]),
                ),
              ),
            );
          }),
        const Spacer(),
        if (tv)
          Text('◀ ▶  Spin      ▲ ▼  Pick      OK  Open', style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 16)),
      ]),
    );
  }
}
