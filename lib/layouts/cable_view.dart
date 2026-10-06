import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/time_format.dart';
import '../services/xtream_client.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

const _mono = 'monospace';

/// Cable Box's Home: the channel you were last on, with a big channel number and a banner showing
/// what is on now and next, like a cable box. Up and Down (or a swipe) change channel, Right reaches
/// the categories and the channel strip, OK plays full screen. The picture itself opens in the
/// player; this screen shows the banner, not live video.
class CableHome extends StatefulWidget {
  const CableHome({super.key});

  @override
  State<CableHome> createState() => _CableHomeState();
}

class _CableHomeState extends State<CableHome> {
  String? _cat;
  int? _idx;
  final _epg = <String, Future<List<EpgEntry>>>{};

  Future<List<EpgEntry>> _epgFor(MediaItem ch) => _epg.putIfAbsent(ch.id,
      () => context.read<AppState>().epg(ch).catchError((_) => <EpgEntry>[]));

  List<MediaItem> _channels(AppState s) {
    final all = s.shown.live;
    return _cat == null ? all : all.where((c) => c.categoryId == _cat).toList();
  }

  void _step(int by, int n) {
    if (n == 0) return;
    setState(() => _idx = ((_idx ?? 0) + by).clamp(0, n - 1).toInt());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final list = _channels(s);
    if (s.shown.live.isEmpty) {
      return Center(child: Text('No live channels in this source.', style: TextStyle(color: p.muted)));
    }
    // Start on the channel watched last, if it is in the list.
    _idx ??= () {
      final last = s.recents.where((e) => e.kind == MediaKind.live).firstOrNull;
      final at = last == null ? -1 : list.indexWhere((c) => c.key == last.key);
      return at < 0 ? 0 : at;
    }();
    final idx = list.isEmpty ? 0 : _idx!.clamp(0, list.length - 1).toInt();
    final cur = list.isEmpty ? null : list[idx];
    final cats = s.shown.liveCategories;
    final use24h = context.select<SettingsState, bool>((st) => st.use24h);

    final picture = _Picture(
      channel: cur,
      number: idx + 1,
      categoryName: cats.where((c) => c.id == cur?.categoryId).firstOrNull?.name ?? 'Live',
      wide: wide,
      onStep: (by) => _step(by, list.length),
      onOpen: () {
        if (cur != null) openItem(context, cur, queue: list);
      },
      clock: fmtTime(DateTime.now(), use24h: use24h),
    );

    final banner = _Banner(
      epg: cur == null ? null : _epgFor(cur),
      use24h: use24h,
      neighbours: [
        for (var k = idx - 2; k <= idx + 2; k++)
          if (k >= 0 && k < list.length) (k, list[k]),
      ],
      current: idx,
      showStrip: wide,
      onPick: (k) {
        if (k == idx) {
          if (cur != null) openItem(context, cur, queue: list);
        } else {
          setState(() => _idx = k);
        }
      },
    );

    void pickCat(String? id) => setState(() {
          _cat = id;
          _idx = 0;
        });

    if (!wide) {
      return Column(children: [
        Expanded(child: picture),
        ChipRow(
          labels: ['ALL', for (final c in cats) c.name.toUpperCase()],
          selected: _cat == null ? 0 : cats.indexWhere((c) => c.id == _cat) + 1,
          onSelect: (i) => pickCat(i == 0 ? null : cats[i - 1].id),
        ),
        banner,
        const SizedBox(height: 8),
      ]);
    }

    return Column(children: [
      Expanded(
        child: Row(children: [
          Expanded(child: picture),
          SizedBox(
            width: 210,
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
              _CatChip(label: 'ALL', selected: _cat == null, onTap: () => pickCat(null)),
              for (final c in cats)
                _CatChip(label: c.name.toUpperCase(), selected: _cat == c.id, onTap: () => pickCat(c.id)),
            ]),
          ),
        ]),
      ),
      banner,
      const SizedBox(height: 10),
      _SoftKeys(onSelect: (i) => ShellNav.maybeOf(context)?.select(i)),
      const SizedBox(height: 6),
    ]);
  }
}

/// The big channel number and name. Focused, Up and Down change channel and OK plays.
class _Picture extends StatelessWidget {
  final MediaItem? channel;
  final int number;
  final String categoryName, clock;
  final bool wide;
  final ValueChanged<int> onStep;
  final VoidCallback onOpen;
  const _Picture({
    required this.channel,
    required this.number,
    required this.categoryName,
    required this.clock,
    required this.wide,
    required this.onStep,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final num = Text('$number',
        style: TextStyle(
            fontFamily: _mono,
            fontSize: wide ? 120 : 96,
            height: 0.9,
            color: p.accent,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(color: p.accent.withValues(alpha: 0.6), blurRadius: 24)]));
    final name = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text((channel?.name ?? '').toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontFamily: _mono,
              color: p.accent2,
              fontSize: wide ? 24 : 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4)),
      const SizedBox(height: 4),
      Text('$categoryName  ·  ${wide ? 'press OK' : 'tap'} to watch',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: _mono, color: p.muted, fontSize: 15)),
    ]);
    final body = Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.35, -0.2),
            radius: 1.0,
            colors: [Color(0xFF1F7C86), Color(0xFF0D3446), Color(0xFF05070A)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
      ),
      const RepaintBoundary(child: IgnorePointer(child: CustomPaint(painter: _Scanlines()))),
      Padding(
        padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 20 : 14, wide ? 28 : 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 18, runSpacing: 4, children: [
                num,
                ConstrainedBox(constraints: BoxConstraints(maxWidth: wide ? 360 : 220), child: name),
              ]),
            ),
            Text(clock,
                style: TextStyle(
                    fontFamily: _mono,
                    color: p.accent,
                    fontSize: wide ? 34 : 22,
                    shadows: [Shadow(color: p.accent.withValues(alpha: 0.5), blurRadius: 12)])),
          ]),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: Text('▲ ▼  CHANNEL',
                style: TextStyle(fontFamily: _mono, color: p.muted, fontSize: 14, letterSpacing: 1.6)),
          ),
        ]),
      ),
    ]);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          onStep(1);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          onStep(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // A swipe up shows the next channel, down the one before, like turning a dial.
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 200) onStep(v < 0 ? 1 : -1);
        },
        child: FocusSurface(
          radius: wide ? 6 : 0,
          autofocus: tv,
          semanticLabel: 'Channel $number ${channel?.name ?? ''}, press to watch',
          onTap: onOpen,
          builder: (_, __) => body,
        ),
      ),
    );
  }
}

/// Fine horizontal lines over the picture, like a tube screen.
class _Scanlines extends CustomPainter {
  const _Scanlines();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x38000000);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.4), paint);
    }
  }

  @override
  bool shouldRepaint(_Scanlines old) => false;
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: FocusSurface(
        radius: 4,
        semanticLabel: label,
        onTap: onTap,
        builder: (_, __) => Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
              color: selected ? p.accent : p.bg.withValues(alpha: 0.6),
              border: Border.all(color: p.line)),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: _mono,
                  letterSpacing: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? p.onAccent : p.accent)),
        ),
      ),
    );
  }
}

/// The banner: now and next with a progress bar, and (wide) the channels around this one.
class _Banner extends StatelessWidget {
  final Future<List<EpgEntry>>? epg;
  final bool use24h, showStrip;
  final List<(int, MediaItem)> neighbours;
  final int current;
  final ValueChanged<int> onPick;
  const _Banner({
    required this.epg,
    required this.use24h,
    required this.neighbours,
    required this.current,
    required this.showStrip,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final mono = TextStyle(fontFamily: _mono, color: p.accent, fontSize: 16);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: p.bg.withValues(alpha: 0.85), border: Border.all(color: p.line, width: 1.2)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<List<EpgEntry>>(
          future: epg,
          builder: (_, snap) {
            final all = snap.data ?? const <EpgEntry>[];
            final now = all.where((e) => e.isNow).firstOrNull;
            final next = now == null
                ? all.where((e) => e.start.isAfter(DateTime.now())).firstOrNull
                : all.where((e) => !e.start.isBefore(now.end)).firstOrNull;
            final total = now == null ? 1 : (now.end.difference(now.start).inSeconds).clamp(1, 1 << 30).toInt();
            final done = now == null ? 0.0 : DateTime.now().difference(now.start).inSeconds / total;
            Widget line(String tag, EpgEntry? e, {String? tail}) => Row(children: [
                  SizedBox(
                      width: 62,
                      child: Text(tag, style: mono.copyWith(color: p.accent2, letterSpacing: 1.6))),
                  Expanded(
                      child: Text(
                          e == null
                              ? (tag == 'NOW' ? 'No guide data for this channel' : '')
                              : '${e.title}  ·  ${fmtTime(e.start, use24h: use24h)} to ${fmtTime(e.end, use24h: use24h)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono.copyWith(color: p.text))),
                  if (tail != null) Text(tail, style: mono.copyWith(color: p.muted, fontSize: 14)),
                ]);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              line('NOW', now,
                  tail: now == null ? null : '${now.end.difference(DateTime.now()).inMinutes.clamp(0, 9999)} min left'),
              const SizedBox(height: 6),
              ClipRect(
                child: LinearProgressIndicator(
                  value: done.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: p.accent.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation(p.accent),
                ),
              ),
              const SizedBox(height: 6),
              line('NEXT', next),
            ]);
          },
        ),
        if (showStrip) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final (k, ch) in neighbours)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FocusSurface(
                    radius: 3,
                    semanticLabel: 'Channel ${k + 1} ${ch.name}',
                    onTap: () => onPick(k),
                    builder: (_, __) {
                      final on = k == current;
                      final fg = on ? p.onAccent : p.accent;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: on ? p.accent : Colors.transparent,
                            border: Border.all(color: p.line)),
                        child: Row(children: [
                          Text('${k + 1}',
                              style: TextStyle(fontFamily: _mono, fontSize: 22, color: fg, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(ch.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontFamily: _mono, fontSize: 14, color: on ? p.onAccent : p.text))),
                        ]),
                      );
                    },
                  ),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Wide screens: the other screens as labeled keys under the banner, like the colored keys on a remote.
class _SoftKeys extends StatelessWidget {
  final ValueChanged<int> onSelect;
  const _SoftKeys({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    const keys = [(2, 'GUIDE'), (1, 'CHANNELS'), (3, 'MOVIES'), (4, 'SERIES'), (5, 'SEARCH'), (6, 'SETTINGS')];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (final (i, label) in keys)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FocusSurface(
                radius: 3,
                semanticLabel: label,
                onTap: () => onSelect(i),
                builder: (_, __) => Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line)),
                  child: Text(label,
                      style: TextStyle(fontFamily: _mono, color: p.accent, fontSize: 14, letterSpacing: 1.4)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
