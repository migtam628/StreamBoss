import 'package:flutter/material.dart';
import '../models/media.dart';
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
