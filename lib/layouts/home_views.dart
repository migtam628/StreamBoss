import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/media_tile.dart';
import '../widgets/net_image.dart';
import '../widgets/tv.dart';
import 'bento_view.dart';
import 'cable_view.dart';
import 'common.dart';
import 'daylight_view.dart';
import 'glass_view.dart';
import 'hub_view.dart';
import 'index_view.dart';
import 'console_view.dart';
import 'deck_view.dart';
import 'lounge_view.dart';
import 'madlib_view.dart';
import 'matchday_view.dart';
import 'easy_view.dart';
import 'wall_view.dart';
import 'globe_view.dart';
import 'playground_view.dart';
import 'tonight_view.dart';
import 'mosaic_view.dart';
import 'prime_view.dart';
import 'spotlight_view.dart';
import 'ui_layout.dart';

/// One row of tiles under a title. [dense] is Control Room's tighter, label-style version.
class Shelf extends StatelessWidget {
  final String title;
  final List<MediaItem> items;
  final bool dense;
  const Shelf(
      {super.key,
      required this.title,
      required this.items,
      this.dense = false});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final s = context.read<AppState>();
    final size = context.watch<SettingsState>().posterScale;
    final tv = TvScope.of(context);
    final p = LayoutPalette.of(context);
    final h = (dense ? 150 : 190) * size + (tv ? 24 : 0);
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 8 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: dense
              ? Text(title.toUpperCase(),
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4))
              : Text(title,
                  style: TextStyle(
                      fontSize: tv ? 22 : 18, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          // Extra height on TV leaves room for the focused tile's lift and glow.
          height: h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
                horizontal: tv ? 24 : 16, vertical: tv ? 14 : 6),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(width: tv ? 22 : 12),
            itemBuilder: (_, i) {
              final it = items[i];
              return AspectRatio(
                aspectRatio: it.kind == MediaKind.live ? 16 / 10 : 2 / 3,
                child: MediaTile(
                  item: it,
                  favorite: s.isFavorite(it),
                  onTap: () => openItem(context, it,
                      queue: it.kind == MediaKind.live ? items : null),
                  onLongPress: () => s.toggleFavorite(it),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// The shelves that belong to this viewer: what to watch next, then each collection they made.
List<Widget> personalShelves(AppState s, {bool dense = false}) {
  final r = s.recommendation;
  return [
    if (r != null) Shelf(title: r.reason, items: r.items, dense: dense),
    for (final n in s.collections.keys) Shelf(title: n, items: s.collectionItems(n), dense: dense),
  ];
}

/// Marquee's opening feature: big artwork, title, Play focused on a TV.
class FeatureHero extends StatelessWidget {
  final MediaItem item;
  const FeatureHero({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final tv = TvScope.of(context);
    final p = LayoutPalette.of(context);
    final s = context.watch<AppState>();
    final fav = s.isFavorite(item);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      height: tv ? 360 : 330,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
            colors: [p.accent, const Color(0xFF3B1055)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft),
      ),
      child: Stack(fit: StackFit.expand, children: [
        if (item.poster != null && item.kind != MediaKind.live)
          Positioned.fill(
              child: NetImage(item.poster!,
                  fit: BoxFit.cover, fallback: () => const SizedBox.shrink())),
        // Readable text over any artwork.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [
                  p.bg.withValues(alpha: 0.95),
                  p.bg.withValues(alpha: 0.55),
                  p.bg.withValues(alpha: 0.05)
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(tv ? 32 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Eyebrow('Featured'),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: tv ? 620 : 420),
                child: Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: tv ? 46 : 30,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  item.kind == MediaKind.live
                      ? 'Live'
                      : (item.kind == MediaKind.series ? 'Series' : 'Movie'),
                  if (item.rating != null &&
                      item.rating!.isNotEmpty &&
                      item.rating != '0')
                    '★ ${item.rating}',
                ].join('  ·  '),
                style: TextStyle(
                    color: p.text.withValues(alpha: 0.8),
                    fontSize: tv ? 18 : 14),
              ),
              if (item.plot != null && item.plot!.isNotEmpty && tv) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(item.plot!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.text.withValues(alpha: 0.75), fontSize: 17)),
                ),
              ],
              const SizedBox(height: 14),
              Row(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  // A remote has no pointer, so land the cursor on the main action.
                  autofocus: tv,
                  onPressed: () => openItem(context, item),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: () => s.toggleFavorite(item),
                  icon: Icon(fav ? Icons.check : Icons.add),
                  label: Text(fav ? 'In My list' : 'My list'),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

/// The Home tab, in whichever layout is selected.
class LayoutHome extends StatelessWidget {
  final UiLayout layout;
  const LayoutHome({super.key, required this.layout});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.shown;
    switch (layout) {
      case UiLayout.marquee:
        final feature = c.movies.isNotEmpty
            ? c.movies.first
            : (c.live.isNotEmpty ? c.live.first : null);
        return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              if (feature != null) FeatureHero(item: feature),
              Shelf(title: 'Continue watching', items: s.recents),
              Shelf(title: 'My list', items: s.favoriteItems),
              ...personalShelves(s),
              Shelf(title: 'Live now', items: c.live.take(20).toList()),
              Shelf(title: 'Movies', items: c.movies.take(30).toList()),
              Shelf(title: 'Series', items: c.series.take(30).toList()),
            ]);
      case UiLayout.control:
        return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Shelf(
                  dense: true,
                  title: 'Live now',
                  items: c.live.take(20).toList()),
              Shelf(dense: true, title: 'Continue watching', items: s.recents),
              Shelf(dense: true, title: 'My list', items: s.favoriteItems),
              ...personalShelves(s, dense: true),
              Shelf(
                  dense: true,
                  title: 'Movies',
                  items: c.movies.take(30).toList()),
              Shelf(
                  dense: true,
                  title: 'Series',
                  items: c.series.take(30).toList()),
            ]);
      case UiLayout.spotlight:
        final seen = <String>{};
        List<MediaItem> uniq(Iterable<MediaItem> xs) => [
              for (final x in xs)
                if (seen.add(x.key)) x
            ];
        final mix = uniq([
          ...s.recents,
          ...s.favoriteItems,
          ...c.movies.take(40),
          ...c.series.take(40),
          ...c.live.take(20)
        ]);
        return SpotlightView(
          sections: [
            ('All', mix),
            if (s.recents.isNotEmpty) ('Continue', s.recents),
            if (s.favoriteItems.isNotEmpty) ('My list', s.favoriteItems),
            ..._personalSections(s),
            if (c.movies.isNotEmpty) ('Movies', c.movies.take(60).toList()),
            if (c.series.isNotEmpty) ('Series', c.series.take(60).toList()),
            if (c.live.isNotEmpty) ('Live', c.live.take(60).toList()),
          ],
          showResume: true,
        );
      case UiLayout.prime:
        return const PrimeHome();
      case UiLayout.hub:
        return const HubHome();
      case UiLayout.daylight:
        return const DaylightHome();
      case UiLayout.cable:
        return const CableHome();
      case UiLayout.indexList:
        return const IndexHome();
      case UiLayout.glass:
        return const GlassHome();
      case UiLayout.bento:
        return const BentoHome();
      case UiLayout.mosaic:
        return const MosaicHome();
      case UiLayout.tonight:
        return const TonightHome();
      case UiLayout.globe:
        return const GlobeHome();
      case UiLayout.playground:
        return const PlaygroundHome();
      case UiLayout.console:
        return const ConsoleHome();
      case UiLayout.deck:
        return const DeckHome();
      case UiLayout.lounge:
        return const LoungeHome();
      case UiLayout.madlib:
        return const MadlibHome();
      case UiLayout.matchday:
        return const MatchdayHome();
      case UiLayout.easy:
        return const EasyHome();
      case UiLayout.wall:
        return const WallHome();
    }
  }
}

/// [personalShelves] as the (title, items) pairs that Spotlight uses. Empty ones are left out.
List<(String, List<MediaItem>)> _personalSections(AppState s) {
  final r = s.recommendation;
  return [
    if (r != null && r.items.isNotEmpty) (r.reason, r.items),
    for (final n in s.collections.keys)
      if (s.collectionItems(n).isNotEmpty) (n, s.collectionItems(n)),
  ];
}
