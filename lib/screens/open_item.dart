import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/nav_guard.dart';
import '../services/play_choices.dart';
import '../services/watch_logic.dart';
import '../services/xmltv.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'series_screen.dart';
import 'watch_screen.dart';
import '../l10n/l10n.dart';

/// Opens the right screen for [item]. For live channels pass [queue] (the
/// visible list) so Up/Down can zap through it.
void openItem(BuildContext context, MediaItem item, {List<MediaItem>? queue}) {
  if (!NavGuard.allow()) return; // a double tap or held OK
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
  if (!NavGuard.allow()) return;
  final url = context.read<AppState>().catchUpUrl(ch, p);
  if (url == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('This channel has no catch-up.'))));
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

/// Plays a movie or an episode: in the watch page where there is one, else in the full-screen player.
/// For an episode pass its [series] and all the series' [episodes], so the page can list them and go on to the next.
void playMedia(
  BuildContext context,
  MediaItem item, {
  String? title,
  Duration? startAt,
  PlayChoices? choices,
  MediaItem? series,
  List<WatchEpisode>? episodes,
}) {
  if (!NavGuard.allow()) return;
  final st = context.read<SettingsState>();
  final Widget page = useWatchPage(enabled: st.watchPage, isTv: st.isTv, item: item)
      ? WatchScreen(item: item, title: title ?? item.name, startAt: startAt, choices: choices, series: series, episodes: episodes)
      : PlayerScreen(
          title: title ?? item.name,
          url: item.streamUrl!,
          item: item,
          startAt: startAt,
          choices: choices,
          episodes: episodes == null ? null : [for (final e in episodes) e.item],
        );
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}
