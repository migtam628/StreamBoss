import '../models/media.dart';
import 'search.dart' show normalizeSearch;

class Recommendation {
  /// A line for the shelf, like "Because you watched Night Signal".
  final String reason;
  final List<MediaItem> items;
  const Recommendation(this.reason, this.items);
}

const _stop = {
  'part',
  'season',
  'episode',
  'movie',
  'film',
  'series',
  'show',
  'from',
  'that',
  'this',
  'with',
  'into'
};

Set<String> _words(String name) => {
      for (final w in normalizeSearch(name).split(' '))
        if (w.length >= 4 && !_stop.contains(w) && int.tryParse(w) == null) w,
    };

/// Movies and series the viewer has not seen, picked by what they have watched and saved:
/// the same categories, titles that share a word with something they liked (a sequel, a franchise),
/// and a lift for good ratings. Null when there is nothing to go on.
Recommendation? recommend({
  required Catalog catalog,
  required List<MediaItem> recents,
  required Set<String> favorites,
  required Map<String, int> positions,
  int limit = 24,
}) {
  final byKey = {
    for (final i in [...catalog.movies, ...catalog.series]) i.key: i
  };
  // Seeds with weights: the latest watched count most, then saved ones, then half-watched.
  final seeds = <MediaItem, double>{};
  var rank = 0;
  for (final r in recents.where((e) => e.kind != MediaKind.live)) {
    final it = byKey[r.key] ?? r;
    seeds[it] = (seeds[it] ?? 0) + (3.0 - (rank++ * 0.15)).clamp(1.0, 3.0);
  }
  for (final k in favorites) {
    final it = byKey[k];
    if (it != null) seeds[it] = (seeds[it] ?? 0) + 2;
  }
  for (final k in positions.keys) {
    final it = byKey[k];
    if (it != null) seeds[it] = (seeds[it] ?? 0) + 1;
  }
  if (seeds.isEmpty) return null;

  final cat = <String, double>{}; // 'kind:categoryId' -> weight
  final word = <String, double>{};
  String ck(MediaItem i) => '${i.kind.name}:${i.categoryId}';
  for (final e in seeds.entries) {
    if (e.key.categoryId.isNotEmpty) {
      cat[ck(e.key)] = (cat[ck(e.key)] ?? 0) + e.value;
    }
    for (final w in _words(e.key.name)) {
      word[w] = (word[w] ?? 0) + e.value;
    }
  }
  final maxCat = cat.values.fold(0.0, (a, b) => a > b ? a : b);
  final seen = {for (final s in seeds.keys) s.key};

  final scored = <(double, MediaItem)>[];
  var order = 0;
  for (final i in [...catalog.movies, ...catalog.series]) {
    order++;
    if (seen.contains(i.key)) continue;
    var s = 0.0;
    if (maxCat > 0 && i.categoryId.isNotEmpty) {
      s += 4 * (cat[ck(i)] ?? 0) / maxCat;
    }
    var shared = 0.0;
    for (final w in _words(i.name)) {
      shared += word[w] ?? 0;
    }
    s += shared > 0 ? 3 + shared.clamp(0, 3) : 0;
    if (s <= 0) continue; // nothing connects it to what they watch
    final rating = double.tryParse(i.rating ?? '') ?? 0;
    s += rating / 10 * 1.5;
    s -= order * 1e-7; // the provider's order breaks ties
    scored.add((s, i));
  }
  if (scored.isEmpty) return null;
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  final items = [for (final e in scored.take(limit)) e.$2];

  // Name the title that explains the top pick best: the latest watched one it shares a category or a word with.
  final top = items.first;
  MediaItem? anchor;
  for (final r in recents.where((e) => e.kind != MediaKind.live)) {
    final it = byKey[r.key] ?? r;
    final sameCat = it.categoryId.isNotEmpty && ck(it) == ck(top);
    if (sameCat || _words(it.name).intersection(_words(top.name)).isNotEmpty) {
      anchor = it;
      break;
    }
  }
  anchor ??= recents.where((e) => e.kind != MediaKind.live).firstOrNull;
  return Recommendation(
      anchor != null ? 'Because you watched ${anchor.name}' : 'Picked for you',
      items);
}
