import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/control_view.dart';
import '../layouts/spotlight_view.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/channel_filter_bar.dart';
import '../widgets/media_tile.dart';
import '../widgets/vod_filter_bar.dart';
import 'open_item.dart';

/// Live, Movies and Series. What it looks like depends on Settings > Appearance > Layout.
class BrowseScreen extends StatelessWidget {
  final MediaKind kind;
  final Catalog catalog;
  const BrowseScreen({super.key, required this.kind, required this.catalog});

  @override
  Widget build(BuildContext context) {
    switch (context.select<SettingsState, UiLayout>((s) => s.layout)) {
      case UiLayout.marquee:
      case UiLayout.hub:
      case UiLayout.daylight:
      case UiLayout.glass:
      case UiLayout.playground:
      case UiLayout.deck:
      case UiLayout.madlib:
      case UiLayout.wall:
      case UiLayout.easy:
        return _MarqueeBrowse(kind: kind, catalog: catalog);
      case UiLayout.cable:
      case UiLayout.lounge:
      case UiLayout.indexList:
      case UiLayout.bento:
      case UiLayout.mosaic:
        return kind == MediaKind.live ? ControlView(kind: kind, catalog: catalog) : _MarqueeBrowse(kind: kind, catalog: catalog);
      case UiLayout.prime:
      case UiLayout.tonight:
      case UiLayout.globe:
      case UiLayout.console:
      case UiLayout.matchday:
        return kind == MediaKind.live ? ControlView(kind: kind, catalog: catalog) : _MarqueeBrowse(kind: kind, catalog: catalog);
      case UiLayout.control:
        return ControlView(kind: kind, catalog: catalog);
      case UiLayout.spotlight:
        final s = context.watch<AppState>();
        final listKey = kind == MediaKind.series ? 'series' : 'movie';
        final filtered = kind == MediaKind.live ? catalog.itemsFor(kind) : s.filterVod(listKey, catalog.itemsFor(kind));
        final cats = catalog.categoriesFor(kind);
        final view = SpotlightView(sections: [
          ('All', filtered),
          for (final c in cats) (c.name, filtered.where((i) => i.categoryId == c.id).toList()),
        ]);
        if (kind == MediaKind.live) {
          return view;
        }
        return Column(children: [
          VodFilterBar(list: listKey, noun: kind == MediaKind.series ? 'series' : 'movies', shown: filtered.length),
          Expanded(child: view),
        ]);
    }
  }
}

/// Category chips over a poster grid.
class _MarqueeBrowse extends StatefulWidget {
  final MediaKind kind;
  final Catalog catalog;
  const _MarqueeBrowse({required this.kind, required this.catalog});

  @override
  State<_MarqueeBrowse> createState() => _MarqueeBrowseState();
}

class _MarqueeBrowseState extends State<_MarqueeBrowse> {
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final size = context.watch<SettingsState>().posterScale;
    final cats = widget.catalog.categoriesFor(widget.kind);
    final live = widget.kind == MediaKind.live;
    final base = widget.catalog.itemsFor(widget.kind);
    final list = widget.kind == MediaKind.series ? 'series' : 'movies';
    final listKey = widget.kind == MediaKind.series ? 'series' : 'movie';
    final all = live ? s.filterChannels(base) : s.filterVod(listKey, base);
    final items =
        _cat == null ? all : all.where((i) => i.categoryId == _cat).toList();

    if (base.isEmpty) {
      return Center(
          child: Text('Nothing here yet.',
              style: TextStyle(color: LayoutPalette.of(context).muted)));
    }

    return Column(children: [
      if (live) ChannelFilterBar(shown: items.length) else VodFilterBar(list: listKey, noun: list, shown: items.length),
      ChipRow(
        labels: ['All', for (final c in cats) c.name],
        selected: _cat == null ? 0 : cats.indexWhere((c) => c.id == _cat) + 1,
        onSelect: (i) => setState(() => _cat = i == 0 ? null : cats[i - 1].id),
      ),
      Expanded(
        child: items.isEmpty
            ? Center(
                child: Text(live ? 'No channels match the filters.' : 'No titles match the filters.',
                    style: TextStyle(color: LayoutPalette.of(context).muted)))
            : GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: (live ? 220 : 160) * size,
            childAspectRatio: live ? 16 / 10 : 2 / 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final it = items[i];
            return MediaTile(
              item: it,
              favorite: s.isFavorite(it),
              offline: live && s.isDead(it),
              onTap: () => openItem(context, it, queue: items),
              onLongPress: () => s.toggleFavorite(it),
            );
          },
        ),
      ),
    ]);
  }
}
