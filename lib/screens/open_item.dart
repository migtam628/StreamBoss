import 'package:flutter/material.dart';
import '../models/media.dart';
import 'player_screen.dart';
import 'series_screen.dart';

void openItem(BuildContext context, MediaItem item) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => item.kind == MediaKind.series
        ? SeriesScreen(series: item)
        : PlayerScreen(title: item.name, url: item.streamUrl!, item: item),
  ));
}
