import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// One word of the Index: its name, a count, and what it does when chosen.
class _Entry {
  final String label;
  final int? count;
  final int? tab; // opens this screen; null = Continue (opens the last title, or expands on a phone)
  const _Entry(this.label, this.count, this.tab);
}

/// Index's Home: very large words. On a wide screen the highlighted word shows what is inside it on
/// the right; on a phone the word opens in place. Only one image is on screen at a time.
class IndexHome extends StatefulWidget {
  const IndexHome({super.key});

  @override
  State<IndexHome> createState() => _IndexHomeState();
}

class _IndexHomeState extends State<IndexHome> {
  int? _sel;
  bool _open = false; // phone: Continue expanded

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final wide = tv || MediaQuery.sizeOf(context).width >= 800;
    final c = s.shown;
    final entries = [
      _Entry('Live now', c.live.length, 1),
      _Entry('Continue', s.recents.length, null),
      _Entry('Movies', c.movies.length, 3),
      _Entry('Series', c.series.length, 4),
      const _Entry('Guide', null, 2),
      const _Entry('Settings', null, 6),
    ];
    final sel = (_sel ?? (s.recents.isNotEmpty ? 1 : 0)).clamp(0, entries.length - 1).toInt();
    _open = _open && s.recents.isNotEmpty;

    void activate(int i) {
      final e = entries[i];
      if (e.tab != null) {
        ShellNav.maybeOf(context)?.select(e.tab!);
      } else if (wide) {
        if (s.recents.isNotEmpty) openItem(context, s.recents.first);
      } else {
        setState(() {
          _sel = i;
          _open = !_open;
        });
      }
    }

    final header = Padding(
      padding: EdgeInsets.fromLTRB(wide ? 8 : 16, 6, wide ? 8 : 16, wide ? 12 : 8),
      child: Row(children: [
        Text('STREAMBOSS',
            style: TextStyle(color: p.text, fontWeight: FontWeight.w800, letterSpacing: 4, fontSize: wide ? 18 : 15)),
        const Spacer(),
        FocusSurface(
          radius: 0,
          semanticLabel: 'Search',
          onTap: () => ShellNav.maybeOf(context)?.select(5),
          builder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.search, color: p.text, size: 22),
              const SizedBox(width: 6),
              Text('Search', style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 16)),
            ]),
          ),
        ),
        if (wide) ...[const SizedBox(width: 12), const NavClock()],
      ]),
    );

    Widget row(int i) => _Row(
          entry: entries[i],
          selected: i == sel,
          big: wide ? 64 : (MediaQuery.sizeOf(context).width * 0.15).clamp(40.0, 72.0).toDouble(),
          onFocus: (f) {
            if (f && _sel != i) setState(() => _sel = i);
          },
          onTap: () => activate(i),
        );

    if (!wide) {
      return Column(children: [
        header,
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
            for (var i = 0; i < entries.length; i++) ...[
              row(i),
              if (_open && entries[i].tab == null) _Inline(items: s.recents.take(3).toList()),
            ],
            if (s.recents.isNotEmpty) _ResumeBar(item: s.recents.first),
          ]),
        ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 6,
            child: ListView(children: [for (var i = 0; i < entries.length; i++) row(i)]),
          ),
          const SizedBox(width: 24),
          Expanded(flex: 5, child: _Panel(entry: entries[sel], app: s)),
        ]),
      ),
      if (tv)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('▲▼  Move      OK  Open      ◀  Back',
              style: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 16)),
        ),
    ]);
  }
}

class _Row extends StatelessWidget {
  final _Entry entry;
  final bool selected;
  final double big;
  final ValueChanged<bool> onFocus;
  final VoidCallback onTap;
  const _Row(
      {required this.entry, required this.selected, required this.big, required this.onFocus, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final ink = p.surfaceHi;
    return FocusSurface(
      radius: 0,
      semanticLabel: entry.label,
      onFocus: onFocus,
      onTap: onTap,
      builder: (_, focused) {
        final on = selected || focused;
        final color = on ? ink : p.text.withValues(alpha: 0.78);
        return Container(
          color: on ? p.accent : Colors.transparent,
          padding: EdgeInsets.symmetric(horizontal: big * 0.3, vertical: big * 0.04),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(entry.label.toUpperCase(),
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: big, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -1, color: color)),
              ),
            ),
            if (entry.count != null)
              Text(entry.count == 0 ? '' : '${entry.count}',
                  style: TextStyle(
                      fontSize: big > 50 ? 20 : 15,
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
      },
    );
  }
}

/// The right-hand panel on wide screens: one thumbnail and up to three lines about the highlighted word.
class _Panel extends StatelessWidget {
  final _Entry entry;
  final AppState app;
  const _Panel({required this.entry, required this.app});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final c = app.shown;
    final List<MediaItem> items = switch (entry.label) {
      'Live now' => c.live.take(3).toList(),
      'Continue' => app.recents.take(3).toList(),
      'Movies' => c.movies.take(3).toList(),
      'Series' => c.series.take(3).toList(),
      'Guide' => c.live.take(3).toList(),
      _ => const [],
    };
    final eyebrow = switch (entry.label) {
      'Live now' => 'On now',
      'Continue' => 'Continue · ${app.recents.length} ${app.recents.length == 1 ? 'title' : 'titles'}',
      'Movies' => 'In Movies',
      'Series' => 'In Series',
      'Guide' => 'The TV guide',
      _ => 'Settings',
    };
    final hero = items.isEmpty ? null : items.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(
        aspectRatio: 16 / 7,
        child: Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [const Color(0xFF3A1D9E), p.surfaceHi])),
          child: hero?.poster != null && hero!.kind != MediaKind.live
              ? NetImage(hero.poster!, fit: BoxFit.cover, fallback: () => const SizedBox.shrink())
              : Center(child: Icon(entry.label == 'Settings' ? Icons.tune : Icons.play_arrow, size: 56, color: p.accent)),
        ),
      ),
      const SizedBox(height: 12),
      Eyebrow(eyebrow, color: p.accent),
      const SizedBox(height: 6),
      if (items.isEmpty)
        Text(
            entry.label == 'Settings'
                ? 'Layout, TV size, playback, sources and more.'
                : (entry.label == 'Continue' ? 'Nothing started yet. Titles you watch show up here.' : 'Nothing here yet.'),
            style: TextStyle(color: p.muted, fontSize: 18)),
      for (final it in items)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
            Text(_sub(app, it), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: p.muted)),
          ]),
        ),
    ]);
  }
}

String _sub(AppState app, MediaItem it) {
  final r = app.resumeFor(it);
  if (r != null) return 'Resume ${r.inMinutes} min';
  return switch (it.kind) {
    MediaKind.live => 'Live channel',
    MediaKind.series => 'Series',
    MediaKind.movie => 'Movie',
  };
}

/// Phone: the titles under Continue, opened in place.
class _Inline extends StatelessWidget {
  final List<MediaItem> items;
  const _Inline({required this.items});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final app = context.read<AppState>();
    return Container(
      color: p.surface,
      child: Column(children: [
        for (final it in items)
          FocusSurface(
            radius: 0,
            semanticLabel: it.name,
            onTap: () => openItem(context, it),
            builder: (_, __) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
                Text(_sub(app, it), style: TextStyle(color: p.muted, fontSize: 14)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Phone: one tap to carry on with the last thing played.
class _ResumeBar extends StatelessWidget {
  final MediaItem item;
  const _ResumeBar({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: FocusSurface(
        radius: 0,
        semanticLabel: 'Resume ${item.name}',
        onTap: () => openItem(context, item),
        builder: (_, __) => Container(
          color: p.surfaceHi,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
                width: 36,
                height: 36,
                color: p.accent,
                child: Icon(Icons.play_arrow, color: p.surfaceHi)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
                Text('Tap to resume', style: TextStyle(color: p.muted, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
