import '../models/media.dart';

/// One episode of a series for the watch page: what the provider says about it and the item that is
/// played, saved and resumed.
class WatchEpisode {
  final Episode episode;
  final MediaItem item;
  const WatchEpisode(this.episode, this.item);
}

/// The watch page replaces the full-screen player on phones, tablets, computers and the web, for movies and
/// episodes. A TV keeps the full-screen player (a remote cannot use a page), and so does live TV and catch-up.
bool useWatchPage(
        {required bool enabled,
        required bool isTv,
        required MediaItem item,
        bool catchUp = false}) =>
    enabled && !isTv && !catchUp && item.kind != MediaKind.live;

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
