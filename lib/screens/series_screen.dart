import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'player_screen.dart';

class SeriesScreen extends StatelessWidget {
  final MediaItem series;
  const SeriesScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(series.name), backgroundColor: Boss.bg),
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
          return ListView(children: [
            if (series.plot != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(series.plot!)),
            for (final e in eps)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text('S${e.season} · E${e.number}  ${e.title}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    title: '${series.name} – ${e.title}',
                    url: e.url,
                    item: series,
                  ),
                )),
              ),
          ]);
        },
      ),
    );
  }
}
