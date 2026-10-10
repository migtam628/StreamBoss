import '../models/media.dart';
import 'search.dart' show normalizeSearch;
import 'tmdb.dart' show cleanTitle;
import 'vod_filter.dart' show ratingOf, yearOf;

/// "1h 48m", "52m", "2h": a runtime as people say it.
String formatRuntime(int minutes) {
  if (minutes <= 0) return '';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// "4K", "1080p", "720p" or "SD" when the name says so, else null.
String? qualityTagOf(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'\b(4k|uhd|2160p)\b').hasMatch(n)) return '4K';
  if (RegExp(r'\b(fhd|1080p|1080i)\b').hasMatch(n)) return '1080p';
  if (RegExp(r'\b(720p|hd)\b').hasMatch(n)) return '720p';
  if (RegExp(r'\b(sd|480p|360p)\b').hasMatch(n)) return 'SD';
  return null;
}

int _qualityRank(String? q) => switch (q) { '4K' => 4, '1080p' => 3, '720p' => 2, 'SD' => 1, _ => 0 };

final _titleKey = Expando<String>('titleKey');

/// What two copies of the same title have in common: the name without quality tags, brackets, year and
/// accents, plus the year when the name has one.
String titleKeyOf(MediaItem i) => _titleKey[i] ??= () {
      final y = yearOf(i);
      return '${normalizeSearch(cleanTitle(i.name))}${y == null ? '' : ' $y'}';
    }();

/// Other copies of [item] in the library (a 4K and a 720p one, say), best quality first.
List<MediaItem> versionsOf(MediaItem item, Iterable<MediaItem> all) {
  final key = titleKeyOf(item);
  final first = normalizeSearch(cleanTitle(item.name)).split(' ').firstWhere((w) => w.isNotEmpty, orElse: () => '');
  if (first.isEmpty) return const [];
  final out = <MediaItem>[];
  for (final o in all) {
    if (o.kind != item.kind || o.key == item.key) continue;
    // Cheap test first: most of a big library does not even contain the first word.
    if (!normalizeSearch(o.name).contains(first)) continue;
    if (titleKeyOf(o) == key) out.add(o);
  }
  out.sort((a, b) => _qualityRank(qualityTagOf(b.name)) - _qualityRank(qualityTagOf(a.name)));
  return out;
}

/// Titles to offer under "More like this": the same kind and category, best rated first.
List<MediaItem> similarTo(MediaItem item, List<MediaItem> all, {int limit = 18}) {
  final same = [
    for (final o in all)
      if (o.kind == item.kind && o.categoryId == item.categoryId && o.key != item.key) o,
  ];
  final at = {for (var i = 0; i < same.length; i++) same[i].key: i};
  same.sort((a, b) {
    final r = ratingOf(b).compareTo(ratingOf(a));
    return r != 0 ? r : at[a.key]! - at[b.key]!;
  });
  return same.take(limit).toList();
}

/// Which episode to offer under Continue: the one you are partway through, else the one after the last
/// you finished, else the first. Null when every episode is watched. [watched] and [inProgress] are in
/// episode order.
int? nextUpIndex(List<bool> watched, List<bool> inProgress) {
  if (watched.isEmpty) return null;
  var last = -1;
  for (var i = 0; i < watched.length; i++) {
    if (watched[i] || inProgress[i]) last = i;
  }
  if (last < 0) return 0;
  if (inProgress[last] && !watched[last]) return last;
  return last + 1 < watched.length ? last + 1 : null;
}

/// Whether an episode aired in the last [days] days (the date as a provider writes it: 2026-10-03).
bool isRecentEpisode(String? airDate, {DateTime? now, int days = 14}) {
  if (airDate == null) return false;
  final d = DateTime.tryParse(airDate.trim());
  if (d == null) return false;
  final n = now ?? DateTime.now();
  final age = n.difference(d);
  return !age.isNegative && age.inDays <= days;
}
