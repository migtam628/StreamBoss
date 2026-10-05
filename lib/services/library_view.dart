import '../models/media.dart';

final _adult = RegExp(r'(\badult\b|\bxxx\b|\bporn|\b18\s*\+|\berotic|\bsex\b)', caseSensitive: false);

/// True for category names that are clearly adult content. This is a convenience filter
/// based on names, not a parental lock.
bool isAdultCategory(String name) => _adult.hasMatch(name);

/// What the browse screens show: the loaded [c] minus hidden categories, optionally sorted A-Z.
/// Returns [c] itself when no option is active.
Catalog buildView(Catalog c, {required bool hideAdult, required bool sortAz}) {
  if (!hideAdult && !sortAz) return c;

  Set<String> blocked(List<Category> cs) =>
      hideAdult ? {for (final x in cs) if (isAdultCategory(x.name)) x.id} : <String>{};

  List<Category> cats(List<Category> cs, Set<String> b) {
    final r = cs.where((x) => !b.contains(x.id)).toList();
    if (sortAz) r.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return r;
  }

  List<MediaItem> items(List<MediaItem> l, Set<String> b) {
    final r = b.isEmpty ? [...l] : l.where((i) => !b.contains(i.categoryId)).toList();
    if (sortAz) r.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return r;
  }

  final bl = blocked(c.liveCategories);
  final bm = blocked(c.movieCategories);
  final bs = blocked(c.seriesCategories);
  return Catalog(
    liveCategories: cats(c.liveCategories, bl),
    movieCategories: cats(c.movieCategories, bm),
    seriesCategories: cats(c.seriesCategories, bs),
    live: items(c.live, bl),
    movies: items(c.movies, bm),
    series: items(c.series, bs),
    epgUrl: c.epgUrl,
  );
}
