import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/xmltv.dart';
import '../state/app_state.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'series_screen.dart';

/// Opens the right screen for [item]. For live channels pass [queue] (the
/// visible list) so Up/Down can zap through it.
void openItem(BuildContext context, MediaItem item, {List<MediaItem>? queue}) {
  final Widget page;
  switch (item.kind) {
    case MediaKind.series:
      page = SeriesScreen(series: item);
    case MediaKind.movie:
      page = DetailScreen(item: item);
    case MediaKind.live:
      final q = (queue ?? const <MediaItem>[]).where((e) => e.kind == MediaKind.live).toList();
      page = PlayerScreen(
        title: item.name,
        url: item.streamUrl!,
        item: item,
        queue: q.length > 1 ? q : null,
      );
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

/// Plays [p] of [ch] from the provider's archive. With [replace] it takes the place of the screen it
/// is opened from (the live player), so the live stream stops instead of playing underneath.
void openCatchUp(BuildContext context, MediaItem ch, Programme p, {bool replace = false}) {
  final url = context.read<AppState>().catchUpUrl(ch, p);
  if (url == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('This channel has no catch-up.')));
    return;
  }
  final item = MediaItem(
    id: 'catchup_${ch.id}_${p.start.millisecondsSinceEpoch}',
    name: '${ch.name}: ${p.title}',
    kind: MediaKind.movie,
    streamUrl: url,
    headers: ch.headers,
  );
  final page = PlayerScreen(title: p.title, url: url, item: item, catchUp: true);
  final nav = Navigator.of(context);
  replace ? nav.pushReplacement(MaterialPageRoute(builder: (_) => page)) : nav.push(MaterialPageRoute(builder: (_) => page));
}
