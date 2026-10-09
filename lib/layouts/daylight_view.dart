import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/xtream_client.dart';
import '../state/app_state.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'common.dart';
import 'home_views.dart';
import 'shell_nav.dart';
import 'ui_layout.dart';

/// Daylight's Home: a white feature card, what is live now as cards with progress, then the usual
/// shelves. Light surfaces on a soft grey ground; one green accent.
class DaylightHome extends StatelessWidget {
  const DaylightHome({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.shown;
    final p = LayoutPalette.of(context);
    final wide = TvScope.of(context) || MediaQuery.sizeOf(context).width >= 800;
    final resume = s.recents.isNotEmpty ? s.recents.first : null;
    final feature = resume ??
        (c.movies.isNotEmpty ? c.movies.first : (c.live.isNotEmpty ? c.live.first : null));
    return ListView(padding: const EdgeInsets.fromLTRB(0, 12, 0, 16), children: [
      if (!wide) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text('StreamBoss',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.text)),
        ),
        _SearchField(onTap: () => ShellNav.maybeOf(context)?.select(5)),
        const SizedBox(height: 14),
      ],
      if (feature != null) _FeatureCard(item: feature, resuming: resume != null, wide: wide),
      _LiveNow(items: c.live.take(20).toList()),
      Shelf(title: 'Continue watching', items: s.recents),
      Shelf(title: 'My list', items: s.favoriteItems),
      ...personalShelves(s),
      Shelf(title: 'Movies', items: c.movies.take(30).toList()),
      Shelf(title: 'Series', items: c.series.take(30).toList()),
    ]);
  }
}

class _SearchField extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchField({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FocusSurface(
        radius: 28,
        semanticLabel: 'Search',
        onTap: onTap,
        builder: (_, __) => Container(
          color: p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            Icon(Icons.search, color: p.muted),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Search channels, movies, series',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted))),
          ]),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final MediaItem item;
  final bool resuming, wide;
  const _FeatureCard({required this.item, required this.resuming, required this.wide});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final s = context.watch<AppState>();
    final tv = TvScope.of(context);
    final fav = s.isFavorite(item);
    final kind = item.kind == MediaKind.live
        ? 'Live'
        : (item.kind == MediaKind.series ? 'Series' : 'Movie');
    final hasRating = item.rating != null && item.rating!.isNotEmpty && item.rating != '0';
    final art = Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [p.accent, const Color(0xFF0D1B5C)])),
      child: item.poster != null && item.kind != MediaKind.live
          ? NetImage(item.poster!, fit: BoxFit.cover, fallback: () => const SizedBox.shrink())
          : null,
    );
    final copy = Padding(
      padding: EdgeInsets.all(wide ? 28 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Eyebrow(resuming ? 'Pick up where you left off' : 'Featured'),
          const SizedBox(height: 6),
          Text(item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: wide ? (tv ? 44 : 36) : 26,
                  height: 1.02,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: p.text)),
          const SizedBox(height: 8),
          Text([kind, if (hasRating) '★ ${item.rating}'].join('  ·  '),
              style: TextStyle(color: p.muted, fontSize: wide ? 17 : 14)),
          if (wide && item.plot != null && item.plot!.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(item.plot!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.text.withValues(alpha: 0.8), fontSize: 16, height: 1.35)),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(
              autofocus: tv,
              onPressed: () => openItem(context, item),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => s.toggleFavorite(item),
              icon: Icon(fav ? Icons.check : Icons.add),
              label: Text(fav ? 'In My list' : 'My list'),
            ),
          ]),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: p.text.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 4))],
      ),
      child: wide
          ? SizedBox(
              height: tv ? 300 : 260,
              child: Row(children: [
                Expanded(flex: 5, child: copy),
                Expanded(flex: 4, child: art),
              ]),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: 150, child: art),
              copy,
            ]),
    );
  }
}

class _LiveNow extends StatelessWidget {
  final List<MediaItem> items;
  const _LiveNow({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final tv = TvScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Live now', style: TextStyle(fontSize: tv ? 22 : 18, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: tv ? 128 : 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: tv ? 8 : 4),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: tv ? 230 : 190,
              child: _LiveCard(item: items[i], queue: items),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A channel card: logo, name, what is on and how far through it is.
class _LiveCard extends StatefulWidget {
  final MediaItem item;
  final List<MediaItem> queue;
  const _LiveCard({required this.item, required this.queue});

  @override
  State<_LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends State<_LiveCard> {
  late final Future<List<EpgEntry>> _epg;

  @override
  void initState() {
    super.initState();
    _epg = context.read<AppState>().epg(widget.item).catchError((_) => <EpgEntry>[]);
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final item = widget.item;
    return FocusSurface(
      radius: 14,
      semanticLabel: item.name,
      onTap: () => openItem(context, item, queue: widget.queue),
      onLongPress: () => context.read<AppState>().toggleFavorite(item),
      builder: (_, __) => Container(
        color: p.surface,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: item.poster == null
                  ? Icon(Icons.live_tv, size: 16, color: p.muted)
                  : NetImage(item.poster!,
                      fit: BoxFit.contain,
                      fallback: () => Icon(Icons.live_tv, size: 16, color: p.muted)),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.text))),
          ]),
          const SizedBox(height: 8),
          FutureBuilder<List<EpgEntry>>(
            future: _epg,
            builder: (_, snap) {
              final now = (snap.data ?? const <EpgEntry>[]).where((e) => e.isNow).firstOrNull;
              final total = now == null ? 0 : now.end.difference(now.start).inSeconds;
              final done = now == null ? 0.0 : DateTime.now().difference(now.start).inSeconds / (total == 0 ? 1 : total);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(now?.title ?? 'Live',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 14)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: now == null ? 0 : done.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: p.wash(0.12),
                    valueColor: AlwaysStoppedAnimation(p.accent),
                  ),
                ),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}
