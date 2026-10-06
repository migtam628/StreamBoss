import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/time_format.dart';
import '../services/xtream_client.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'hub_view.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

const _ink = Color(0xFF17141F);
const _sky = Color(0xFF62B6FF);
const _mint = Color(0xFF5FD36F);
const _pink = Color(0xFFFFA3D1);
const _paper = Color(0xFFF6F4F1);

/// Bento's Home: a board of flat colored tiles with 2 px between them. On a wide screen the tiles
/// share the screen; on a phone they stack. No photos, shadows or gradients.
class BentoHome extends StatelessWidget {
  const BentoHome({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final wide = TvScope.of(context) || MediaQuery.sizeOf(context).width >= 800;
    final c = s.shown;
    final resume = s.recents.isNotEmpty ? s.recents.first : null;
    final cont = resume ?? (c.movies.isNotEmpty ? c.movies.first : null);
    final lastLive = s.recents.where((e) => e.kind == MediaKind.live).firstOrNull ?? c.live.firstOrNull;
    final liveIdx = lastLive == null ? 0 : c.live.indexWhere((e) => e.key == lastLive.key) + 1;
    void go(int tab) => ShellNav.maybeOf(context)?.select(tab);

    final continueTile = _Tile(
      color: p.accent,
      semantic: 'Continue',
      autofocus: TvScope.of(context),
      onTap: cont == null ? () => go(3) : () => openItem(context, cont),
      child: _Continue(item: cont, resuming: resume != null, wide: wide),
    );
    final liveTile = _Tile(
      color: p.accent2,
      semantic: 'Live now',
      onTap: lastLive == null ? () => go(1) : () => openItem(context, lastLive, queue: c.live),
      child: _Live(channel: lastLive, number: liveIdx, wide: wide),
    );
    final searchTile = _Tile(
      color: _paper,
      semantic: 'Search',
      onTap: () => go(5),
      child: const Row(children: [
        Icon(Icons.search, color: _ink, size: 28),
        SizedBox(width: 12),
        Expanded(
            child: Text('Search channels, movies, series',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w600))),
      ]),
    );
    final newTile = _Tile(
      color: _mint,
      semantic: 'In your library',
      onTap: () => go(3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Label('Library'),
        const Spacer(),
        for (final (n, t) in [(c.movies.length, 'Movies'), (c.series.length, 'Series'), (c.live.length, 'Channels')])
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('$n', style: const TextStyle(color: _ink, fontSize: 28, fontWeight: FontWeight.w800, height: 1.0)),
                const SizedBox(width: 8),
                Text(t, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
    );
    final favs = s.favoriteItems;
    final favTile = _Tile(
      color: _pink,
      semantic: 'My list',
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FavoritesPage())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Label('My list'),
        const Spacer(),
        Text('${favs.length}', style: const TextStyle(color: _ink, fontSize: 40, fontWeight: FontWeight.w800, height: 1.0)),
        Text(favs.isEmpty ? 'Nothing saved yet' : favs.take(2).map((e) => e.name).join(', '),
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w500)),
      ]),
    );
    final guideTile = _Tile(
      color: _sky,
      semantic: 'On now, open the guide',
      onTap: () => go(2),
      child: _GuideStrip(channels: c.live.take(wide ? 4 : 3).toList()),
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Column(children: [
          Expanded(
            flex: 7,
            child: Row(children: [
              Expanded(flex: 6, child: continueTile),
              const SizedBox(width: 2),
              Expanded(
                flex: 4,
                child: Column(children: [
                  Expanded(flex: 3, child: liveTile),
                  const SizedBox(height: 2),
                  Expanded(flex: 2, child: searchTile),
                ]),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: 3,
                child: Column(children: [
                  Expanded(flex: 3, child: newTile),
                  const SizedBox(height: 2),
                  Expanded(flex: 2, child: favTile),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 2),
          Expanded(flex: 3, child: guideTile),
        ]),
      );
    }
    return ListView(padding: const EdgeInsets.all(2), children: [
      SizedBox(height: 230, child: continueTile),
      const SizedBox(height: 2),
      SizedBox(height: 160, child: liveTile),
      const SizedBox(height: 2),
      SizedBox(
        height: 190,
        child: Row(children: [Expanded(child: newTile), const SizedBox(width: 2), Expanded(child: favTile)]),
      ),
      const SizedBox(height: 2),
      SizedBox(height: 150, child: guideTile),
      const SizedBox(height: 2),
      SizedBox(height: 72, child: searchTile),
    ]);
  }
}

/// One flat tile. [color] fills it; the text on it is ink.
class _Tile extends StatelessWidget {
  final Color color;
  final String semantic;
  final VoidCallback onTap;
  final Widget child;
  final bool autofocus;
  const _Tile({required this.color, required this.semantic, required this.onTap, required this.child, this.autofocus = false});

  @override
  Widget build(BuildContext context) => FocusSurface(
        radius: 0,
        autofocus: autofocus,
        semanticLabel: semantic,
        onTap: onTap,
        builder: (_, __) => Container(
          width: double.infinity,
          height: double.infinity,
          color: color,
          padding: const EdgeInsets.all(18),
          child: child,
        ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  final Widget? lead;
  const _Label(this.text, {this.lead});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (lead != null) ...[lead!, const SizedBox(width: 8)],
        Flexible(
          child: Text(text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        ),
      ]);
}

class _Continue extends StatelessWidget {
  final MediaItem? item;
  final bool resuming, wide;
  const _Continue({required this.item, required this.resuming, required this.wide});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (item == null) {
      return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label('Continue'),
        Spacer(),
        Text('Nothing to continue yet.', style: TextStyle(color: _ink, fontSize: 28, fontWeight: FontWeight.w800)),
      ]);
    }
    final r = s.resumeFor(item!);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Label(resuming ? 'Continue' : 'Start with'),
      const Spacer(),
      Text(item!.name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _ink, fontSize: wide ? 52 : 34, fontWeight: FontWeight.w800, height: 0.98, letterSpacing: -1)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Text(
              r != null
                  ? 'Resume at ${r.inMinutes} min'
                  : (item!.kind == MediaKind.series ? 'Series' : (item!.kind == MediaKind.live ? 'Live' : 'Movie')),
              style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Container(
            width: 52,
            height: 52,
            color: _ink,
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 30)),
      ]),
    ]);
  }
}

/// Builds from a channel's now and next, fetched once.
class _NowNext extends StatefulWidget {
  final MediaItem channel;
  final Widget Function(EpgEntry? now, EpgEntry? next) builder;
  const _NowNext({required this.channel, required this.builder});

  @override
  State<_NowNext> createState() => _NowNextState();
}

class _NowNextState extends State<_NowNext> {
  late final Future<List<EpgEntry>> _epg;

  @override
  void initState() {
    super.initState();
    _epg = context.read<AppState>().epg(widget.channel).catchError((_) => <EpgEntry>[]);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<EpgEntry>>(
        future: _epg,
        builder: (_, snap) {
          final all = snap.data ?? const <EpgEntry>[];
          final now = all.where((e) => e.isNow).firstOrNull;
          final next = now == null
              ? all.where((e) => e.start.isAfter(DateTime.now())).firstOrNull
              : all.where((e) => !e.start.isBefore(now.end)).firstOrNull;
          return widget.builder(now, next);
        },
      );
}

class _Live extends StatelessWidget {
  final MediaItem? channel;
  final int number;
  final bool wide;
  const _Live({required this.channel, required this.number, required this.wide});

  @override
  Widget build(BuildContext context) {
    final use24h = context.select<SettingsState, bool>((st) => st.use24h);
    final dot = Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFE0200F), shape: BoxShape.circle));
    if (channel == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label('Live now', lead: dot),
        const Spacer(),
        const Text('No live channels', style: TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w800)),
      ]);
    }
    return _NowNext(
      channel: channel!,
      builder: (now, next) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label('Live now', lead: dot),
        const Spacer(),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('$number', style: TextStyle(color: _ink, fontSize: wide ? 58 : 46, fontWeight: FontWeight.w800, height: 0.9, letterSpacing: -2)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(channel!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w800)),
              Text(now?.title ?? 'Live', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
        if (next != null) ...[
          const SizedBox(height: 8),
          Text('Next ${fmtTime(next.start, use24h: use24h)}  ${next.title}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

/// A row of channels with what is on each.
class _GuideStrip extends StatelessWidget {
  final List<MediaItem> channels;
  const _GuideStrip({required this.channels});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Label('On now'),
        const Spacer(),
        if (channels.isEmpty)
          const Text('No guide yet', style: TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w700))
        else
          Row(children: [
            for (final ch in channels)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _NowNext(
                    channel: ch,
                    builder: (now, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(now?.title ?? 'Live', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 15)),
                    ]),
                  ),
                ),
              ),
          ]),
      ]);
}
