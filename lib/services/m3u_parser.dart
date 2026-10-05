import '../models/media.dart';

/// Parses an extended M3U playlist into a [Catalog].
/// Entries whose URL looks like an Xtream `/movie/` or `/series/` path are
/// classified as movies; everything else is live TV grouped by `group-title`.
Catalog parseM3u(String body) {
  final attr = RegExp(r'([\w-]+)="([^"]*)"');
  final live = <MediaItem>[];
  final movies = <MediaItem>[];
  final groups = <String, Category>{};

  String? epgUrl;
  Map<String, String> attrs = {};
  String name = '';
  var n = 0;

  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      final h = {for (final m in attr.allMatches(line)) m.group(1)!: m.group(2)!};
      final u = (h['url-tvg'] ?? h['x-tvg-url'])?.split(',').first.trim();
      if (u != null && u.isNotEmpty) epgUrl = u;
    } else if (line.startsWith('#EXTINF')) {
      attrs = {for (final m in attr.allMatches(line)) m.group(1)!: m.group(2)!};
      final comma = line.lastIndexOf(',');
      name = comma >= 0 ? line.substring(comma + 1).trim() : '';
      if (name.isEmpty) name = attrs['tvg-name'] ?? 'Channel ${n + 1}';
    } else if (!line.startsWith('#')) {
      final group = attrs['group-title']?.trim();
      final catId = (group == null || group.isEmpty) ? 'Other' : group;
      groups.putIfAbsent(catId, () => Category(catId, catId));
      final isVod = line.contains('/movie/') || line.contains('/series/');
      final item = MediaItem(
        id: '${n++}',
        name: name,
        kind: isVod ? MediaKind.movie : MediaKind.live,
        streamUrl: line,
        poster: attrs['tvg-logo'],
        categoryId: catId,
        epgId: attrs['tvg-id'],
      );
      (isVod ? movies : live).add(item);
      attrs = {};
      name = '';
    }
  }

  final liveCats = live.map((e) => e.categoryId).toSet();
  final movieCats = movies.map((e) => e.categoryId).toSet();
  return Catalog(
    epgUrl: epgUrl,
    live: live,
    movies: movies,
    liveCategories: [for (final c in groups.values) if (liveCats.contains(c.id)) c],
    movieCategories: [for (final c in groups.values) if (movieCats.contains(c.id)) c],
  );
}
