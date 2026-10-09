import '../models/media.dart';

/// Puts the libraries of several sources into one. The main source is kept exactly as it is (so what
/// was saved from it, like My List, still matches); everything from another source is tagged with
/// that source's name, its category ids are made unique, and a category whose name is already taken
/// gets "(source)" after it so the two stay apart in the lists.
Catalog combineSources(
    Catalog primary, List<(String name, Catalog catalog)> extras) {
  if (extras.isEmpty) return primary;

  MediaItem tag(MediaItem e, String src) => MediaItem(
        id: e.id,
        name: e.name,
        kind: e.kind,
        streamUrl: e.streamUrl,
        poster: e.poster,
        categoryId: e.categoryId.isEmpty ? '' : '$src:${e.categoryId}',
        rating: e.rating,
        plot: e.plot,
        epgId: e.epgId,
        headers: e.headers,
        archiveDays: e.archiveDays,
        src: src,
      );

  List<Category> cats(
      List<Category> base, Iterable<(String, List<Category>)> more) {
    final out = [...base];
    final taken = {for (final c in base) c.name.toLowerCase()};
    for (final (src, list) in more) {
      for (final c in list) {
        final clash = !taken.add(c.name.toLowerCase());
        out.add(Category('$src:${c.id}', clash ? '${c.name} ($src)' : c.name));
      }
    }
    return out;
  }

  List<MediaItem> items(List<MediaItem> base, MediaKind k) => [
        ...base,
        for (final (src, c) in extras)
          for (final e in c.itemsFor(k)) tag(e, src),
      ];

  return Catalog(
    epgUrl: primary.epgUrl,
    liveCategories: cats(primary.liveCategories,
        [for (final (n, c) in extras) (n, c.liveCategories)]),
    movieCategories: cats(primary.movieCategories,
        [for (final (n, c) in extras) (n, c.movieCategories)]),
    seriesCategories: cats(primary.seriesCategories,
        [for (final (n, c) in extras) (n, c.seriesCategories)]),
    live: items(primary.live, MediaKind.live),
    movies: items(primary.movies, MediaKind.movie),
    series: items(primary.series, MediaKind.series),
  );
}
