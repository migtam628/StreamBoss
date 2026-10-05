import 'package:flutter/material.dart';
import '../layouts/ui_layout.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/tmdb_header.dart';
import '../widgets/tv.dart';
import 'player_screen.dart';

class SeriesScreen extends StatelessWidget {
  final MediaItem series;
  const SeriesScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(series.name), backgroundColor: LayoutPalette.of(context).bg),
      body: FutureBuilder<List<Episode>>(
        future: s.episodes(series),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load episodes: ${snap.error}'));
          }
          final eps = snap.data ?? [];
          final tv = TvScope.of(context);
          return TvSafe(
            child: ListView(children: [
            TmdbHeader(item: series),
            for (final e in eps)
              ListTile(
                autofocus: tv && e == eps.first,
                leading: const Icon(Icons.play_circle_outline),
                title: Text('S${e.season} · E${e.number}  ${e.title}'),
                onTap: () {
                  // Episode-scoped item so resume + "continue watching" are per episode.
                  final ep = MediaItem(
                    id: 'ep${e.id}',
                    name: '${series.name} – ${e.title}',
                    kind: MediaKind.movie,
                    streamUrl: e.url,
                    poster: series.poster,
                  );
                  final auto = context.read<SettingsState>().autoResume;
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      title: ep.name,
                      url: e.url,
                      item: ep,
                      startAt: auto ? s.resumeFor(ep) : null,
                    ),
                  ));
                },
              ),
          ]),
          );
        },
      ),
    );
  }
}
