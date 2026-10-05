import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/tmdb_header.dart';
import 'player_screen.dart';

class DetailScreen extends StatelessWidget {
  final MediaItem item;
  const DetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final resume = s.resumeFor(item);
    void play() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(title: item.name, url: item.streamUrl!, item: item)));

    return Scaffold(
      appBar: AppBar(backgroundColor: Boss.bg, actions: [
        IconButton(
          icon: Icon(s.isFavorite(item) ? Icons.favorite : Icons.favorite_border,
              color: Boss.accent),
          tooltip: 'My list',
          onPressed: () => s.toggleFavorite(item),
        ),
      ]),
      body: ListView(children: [
        TmdbHeader(item: item),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            FilledButton.icon(
              autofocus: true,
              onPressed: play,
              icon: const Icon(Icons.play_arrow),
              label: Text(resume == null
                  ? 'Play'
                  : 'Resume from ${resume.inMinutes}:${(resume.inSeconds % 60).toString().padLeft(2, '0')}'),
            ),
            if (resume != null) ...[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () {
                  s.positions.remove(item.key);
                  play();
                },
                child: const Text('Start over'),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
