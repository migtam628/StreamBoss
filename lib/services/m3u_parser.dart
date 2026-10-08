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
  var hdrs = <String, String>{};

  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      final h = {for (final m in attr.allMatches(line)) m.group(1)!: m.group(2)!};
      final u = (h['url-tvg'] ?? h['x-tvg-url'])?.split(',').first.trim();
      if (u != null && u.isNotEmpty) epgUrl = u;
    } else if (line.startsWith('#EXTINF')) {
      attrs = {for (final m in attr.allMatches(line)) m.group(1)!: m.group(2)!};
      final comma = _titleComma(line);
      name = comma >= 0 ? line.substring(comma + 1).trim() : '';
      if (name.isEmpty) name = attrs['tvg-name'] ?? 'Channel ${n + 1}';
    } else if (line.startsWith('#EXTVLCOPT:')) {
      // Some streams only answer with the right Referer or User-Agent; iptv-org lists say so here.
      final eq = line.indexOf('=');
      if (eq > 0) {
        final key = line.substring('#EXTVLCOPT:'.length, eq).trim().toLowerCase();
        final val = line.substring(eq + 1).trim();
        final header = switch (key) {
          'http-referrer' || 'http-referer' => 'Referer',
          'http-user-agent' => 'User-Agent',
          'http-origin' => 'Origin',
          _ => null,
        };
        if (header != null && val.isNotEmpty) hdrs[header] = val;
      }
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
        headers: hdrs.isEmpty ? null : hdrs,
      );
      (isVod ? movies : live).add(item);
      attrs = {};
      hdrs = <String, String>{};
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

/// Combines several parsed playlists into one. A stream that appears in more than one is kept once,
/// ids are prefixed with the list they came from so they stay unique, and categories keep the order
/// they were first seen in.
Catalog mergeCatalogs(List<Catalog> parts) {
  final seen = <String>{};
  final live = <MediaItem>[];
  final movies = <MediaItem>[];
  String? epg;
  MediaItem take(int p, MediaItem e) => MediaItem(
        id: '$p-${e.id}',
        name: e.name,
        kind: e.kind,
        streamUrl: e.streamUrl,
        poster: e.poster,
        categoryId: e.categoryId,
        rating: e.rating,
        plot: e.plot,
        epgId: e.epgId,
        headers: e.headers,
      );
  for (var p = 0; p < parts.length; p++) {
    epg ??= parts[p].epgUrl;
    for (final e in parts[p].live) {
      if (seen.add(e.streamUrl ?? '$p-${e.id}')) live.add(take(p, e));
    }
    for (final e in parts[p].movies) {
      if (seen.add(e.streamUrl ?? '$p-${e.id}')) movies.add(take(p, e));
    }
  }
  List<Category> cats(Iterable<Category> all, List<MediaItem> items) {
    final used = items.map((e) => e.categoryId).toSet();
    final byId = <String, Category>{};
    for (final c in all) {
      if (used.contains(c.id)) byId.putIfAbsent(c.id, () => c);
    }
    return byId.values.toList();
  }

  return Catalog(
    epgUrl: epg,
    live: live,
    movies: movies,
    liveCategories: cats([for (final p in parts) ...p.liveCategories], live),
    movieCategories: cats([for (final p in parts) ...p.movieCategories], movies),
  );
}

/// Index of the first comma outside quotes (the title follows it), or -1.
int _titleComma(String line) {
  var inQuote = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      inQuote = !inQuote;
    } else if (c == ',' && !inQuote) {
      return i;
    }
  }
  return -1;
}
