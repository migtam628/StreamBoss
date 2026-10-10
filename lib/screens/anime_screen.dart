import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/shell_nav.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../services/anime.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/media_tile.dart';
import '../widgets/vod_filter_bar.dart';
import 'open_item.dart';

/// Anime: the series, movies and channels in the library that look like anime, found by category names
/// (Anime, Manga, Donghua, Shonen and so on) and "(Anime)" in a title. It has its own filters, and the
/// provider's anime categories as chips. When nothing is found it says how the page finds things.
class AnimeScreen extends StatefulWidget {
  const AnimeScreen({super.key});

  @override
  State<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends State<AnimeScreen> {
  MediaKind? _kind;
  String? _cat;

  static const _label = {MediaKind.series: 'Series', MediaKind.movie: 'Movies', MediaKind.live: 'Channels'};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = LayoutPalette.of(context);
    final size = context.watch<SettingsState>().posterScale;
    final c = s.shown;
    final found = {for (final k in MediaKind.values) k: animeOf(c, k)};
    final kinds = [for (final k in [MediaKind.series, MediaKind.movie, MediaKind.live]) if (found[k]!.items.isNotEmpty) k];

    if (kinds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome_outlined, size: 56, color: p.muted),
              const SizedBox(height: 14),
              Text('No anime found', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(height: 8),
              Text(
                  'This page lists the categories whose names say anime, manga, donghua, shonen and similar, and titles marked (Anime). '
                  'Your library has none. Anime in a category named something else is still under Series and Movies.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, height: 1.4)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => ShellNav.maybeOf(context)?.select(4), child: const Text('Browse series')),
            ]),
          ),
        ),
      );
    }

    final kind = kinds.contains(_kind) ? _kind! : kinds.first;
    final cur = found[kind]!;
    final live = kind == MediaKind.live;
    final base = _cat == null ? cur.items : [for (final i in cur.items) if (i.categoryId == _cat) i];
    final items = s.filterVod('anime', base);
    final cats = cur.categories;

    return Column(children: [
      if (kinds.length > 1)
        ChipRow(
          labels: [for (final k in kinds) '${_label[k]}  ${found[k]!.items.length}'],
          selected: kinds.indexOf(kind),
          onSelect: (i) => setState(() {
            _kind = kinds[i];
            _cat = null;
          }),
        ),
      VodFilterBar(list: 'anime', noun: 'anime', shown: items.length),
      if (cats.length > 1)
        ChipRow(
          labels: ['All', for (final cat in cats) cat.name],
          selected: _cat == null ? 0 : cats.indexWhere((x) => x.id == _cat) + 1,
          onSelect: (i) => setState(() => _cat = i == 0 ? null : cats[i - 1].id),
        ),
      Expanded(
        child: items.isEmpty
            ? Center(child: Text('No anime matches the filters.', style: TextStyle(color: p.muted)))
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: (live ? 220 : 160) * size,
                  childAspectRatio: live ? 16 / 10 : 2 / 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => MediaTile(
                  item: items[i],
                  favorite: s.isFavorite(items[i]),
                  offline: live && s.isDead(items[i]),
                  onTap: () => openItem(context, items[i], queue: items),
                  onLongPress: () => s.toggleFavorite(items[i]),
                ),
              ),
      ),
    ]);
  }
}
