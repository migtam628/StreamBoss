import '../models/media.dart';

/// The episode after [current] in [episodes] (their order is the season order), or null at the end
/// or when [current] is not in the list.
MediaItem? nextEpisodeAfter(List<MediaItem>? episodes, MediaItem current) {
  if (episodes == null) return null;
  final at = episodes.indexWhere((e) => e.key == current.key);
  return at >= 0 && at + 1 < episodes.length ? episodes[at + 1] : null;
}
