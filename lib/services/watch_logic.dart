import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:media_kit/media_kit.dart' show VideoTrack;
import '../models/media.dart';
import 'xtream_client.dart' show EpgEntry;

/// One episode of a series for the watch page: what the provider says about it and the item that is
/// played, saved and resumed.
class WatchEpisode {
  final Episode episode;
  final MediaItem item;
  const WatchEpisode(this.episode, this.item);
}

/// The watch page replaces the full-screen player on phones, tablets, computers and the web, for movies, episodes
/// and live channels. A TV keeps the full-screen player (a remote cannot use a page), and so does catch-up.
bool useWatchPage(
        {required bool enabled,
        required bool isTv,
        required MediaItem item,
        bool catchUp = false}) =>
    enabled && !isTv && !catchUp;

/// Side by side from this width up; below it the page is one column, the video on top.
const watchWideFrom = 900.0;

bool isWatchWide(double width) => width >= watchWideFrom;

/// The seasons in [eps], in order.
List<int> watchSeasons(List<WatchEpisode> eps) =>
    ({for (final e in eps) e.episode.season}.toList()..sort());

/// The episodes of [season], in the order the series lists them.
List<WatchEpisode> inSeason(List<WatchEpisode> eps, int season) => [
      for (final e in eps)
        if (e.episode.season == season) e
    ];

/// The season the episode with key [itemKey] belongs to, else the first season, else 1.
int seasonOfItem(List<WatchEpisode> eps, String itemKey) {
  for (final e in eps) {
    if (e.item.key == itemKey) return e.episode.season;
  }
  final all = watchSeasons(eps);
  return all.isEmpty ? 1 : all.first;
}

/// "S2 · E5" for an episode.
String episodeTag(Episode e) => 'S${e.season} · E${e.number}';

/// The page's own title for what plays: a series shows its name large and the episode under it.
({String title, String? subtitle}) watchHeading(
    {required MediaItem item, MediaItem? series, Episode? episode}) {
  if (series != null && episode != null) {
    final t = episode.title.trim();
    return (
      title: series.name,
      subtitle: t.isEmpty ? episodeTag(episode) : '${episodeTag(episode)} · $t'
    );
  }
  return (title: item.name, subtitle: null);
}

/// One entry of the quality menu. A null [track] is Auto (the player chooses by itself).
class QualityChoice {
  final VideoTrack? track;
  final String label;
  const QualityChoice(this.track, this.label);
}

/// "1080p", "720p", "4K": how a picture size reads in the menu.
String qualityName(int? w, int? h) {
  if (h == null || h <= 0) return '';
  if ((w ?? 0) >= 3200 || h >= 2000) return '4K';
  return '${h}p';
}

/// The quality menu for a stream: Auto, then each picture size it offers, biggest first. Empty when the
/// stream offers fewer than two sizes (a plain file has nothing to choose), so no button is shown.
List<QualityChoice> qualityChoices(List<VideoTrack> tracks) {
  final best = <int,
      VideoTrack>{}; // height -> the track with the most data at that height
  for (final t in tracks) {
    final h = t.h;
    if (t.id == 'auto' || t.id == 'no' || h == null || h <= 0) continue;
    final old = best[h];
    if (old == null || (t.bitrate ?? 0) > (old.bitrate ?? 0)) best[h] = t;
  }
  if (best.length < 2) return const [];
  final heights = best.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    const QualityChoice(null, 'Auto'),
    for (final h in heights) QualityChoice(best[h], qualityName(best[h]!.w, h)),
  ];
}

/// Whether the choice [c] is the one playing, given the track the player has selected now.
bool qualityIsCurrent(QualityChoice c, VideoTrack? selected) {
  if (selected == null) return c.track == null;
  if (c.track == null) return selected.id == 'auto';
  return selected.id == c.track!.id;
}

enum LeaveAction { pause, resume, none }

/// Pause when the tab or window is hidden, and carry on when it is back, but only a pause made here:
/// a video the viewer paused stays paused.
LeaveAction leaveAction({
  required AppLifecycleState state,
  required bool enabled,
  required bool playing,
  required bool pausedByUs,
}) {
  if (!enabled) return LeaveAction.none;
  switch (state) {
    case AppLifecycleState.hidden:
    case AppLifecycleState.paused:
      return playing ? LeaveAction.pause : LeaveAction.none;
    case AppLifecycleState.resumed:
      return pausedByUs ? LeaveAction.resume : LeaveAction.none;
    default:
      return LeaveAction.none;
  }
}

/// Which part of a channel list to show beside a live channel: [size] channels, starting a little before the one on
/// screen (a list can have thousands). Indexes into the list, [end] not included.
({int start, int end}) channelWindow(int length, int current, {int size = 100}) {
  if (length <= size) return (start: 0, end: length);
  final start = (current - 8).clamp(0, length - size);
  return (start: start, end: start + size);
}

/// What is on, what is next and how far through the programme on now is (0 to 1), from a channel's guide.
({EpgEntry? now, EpgEntry? next, double progress}) nowAndNext(List<EpgEntry> epg, DateTime at) {
  EpgEntry? now, next;
  for (final e in epg) {
    if (!at.isBefore(e.start) && at.isBefore(e.end)) {
      now = e;
    } else if (e.start.isAfter(at) && (next == null || e.start.isBefore(next.start))) {
      next = e;
    }
  }
  var progress = 0.0;
  if (now != null) {
    final total = now.end.difference(now.start).inSeconds;
    if (total > 0) progress = (at.difference(now.start).inSeconds / total).clamp(0.0, 1.0);
  }
  return (now: now, next: next, progress: progress);
}
