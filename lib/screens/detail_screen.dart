import 'package:flutter/material.dart';
import '../layouts/ui_layout.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/tmdb_header.dart';
import '../widgets/tv.dart';
import '../widgets/collections_sheet.dart';
import 'player_screen.dart';

class DetailScreen extends StatelessWidget {
  final MediaItem item;
  const DetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final tv = TvScope.of(context);
    final auto = context.watch<SettingsState>().autoResume;
    final resume = s.resumeFor(item);
    void play({Duration? at}) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(title: item.name, url: item.streamUrl!, item: item, startAt: at)));
    String stamp(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(backgroundColor: LayoutPalette.of(context).bg, actions: [
        IconButton(
          icon: const Icon(Icons.collections_bookmark_outlined),
          tooltip: 'Add to a collection',
          onPressed: () => showCollectionsSheet(context, item),
        ),
        IconButton(
          icon: Icon(s.isFavorite(item) ? Icons.favorite : Icons.favorite_border,
              color: LayoutPalette.of(context).accent),
          tooltip: 'My list',
          onPressed: () => s.toggleFavorite(item),
        ),
      ]),
      body: TvSafe(
        child: ListView(children: [
        TmdbHeader(item: item),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 12, runSpacing: 8, children: [
            if (resume == null)
              FilledButton.icon(
                autofocus: true,
                onPressed: play,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              )
            else if (auto) ...[
              // Auto-resume on: the main button continues where you left off.
              FilledButton.icon(
                autofocus: true,
                onPressed: () => play(at: resume),
                icon: const Icon(Icons.play_arrow),
                label: Text('Resume from ${stamp(resume)}'),
              ),
              OutlinedButton(
                onPressed: () {
                  s.positions.remove(item.key);
                  play();
                },
                child: const Text('Start over'),
              ),
            ] else ...[
              FilledButton.icon(
                autofocus: true,
                onPressed: play,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play from start'),
              ),
              OutlinedButton(
                onPressed: () => play(at: resume),
                child: Text('Resume from ${stamp(resume)}'),
              ),
            ],
            // The app-bar buttons are awkward with a remote, so TV gets a button beside Play.
            if (tv)
              OutlinedButton.icon(
                onPressed: () => showCollectionsSheet(context, item),
                icon: const Icon(Icons.collections_bookmark_outlined),
                label: Text(s.collections.values.any((l) => l.contains(item.key)) ? 'In a collection' : 'Add to collection'),
              ),
            if (tv)
              OutlinedButton.icon(
                onPressed: () => s.toggleFavorite(item),
                icon: Icon(s.isFavorite(item) ? Icons.favorite : Icons.favorite_border),
                label: Text(s.isFavorite(item) ? 'In My list' : 'Add to My list'),
              ),
          ]),
        ),
      ]),
      ),
    );
  }
}
