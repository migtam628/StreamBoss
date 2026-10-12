import '../models/media.dart';
import 'search.dart' show normalizeSearch;
import 'tmdb.dart';
import 'vod_filter.dart' show yearOf;

/// Finds the library's own copy of a TMDB title, by name (accents, punctuation, quality tags and the year in
/// the name ignored) and, when both sides have one, by year (a year apart is allowed: release dates differ).
class LibraryMatcher {
  final Map<String, List<MediaItem>> _movies = {}, _series = {};

  LibraryMatcher(Iterable<MediaItem> movies, Iterable<MediaItem> series) {
    void add(Map<String, List<MediaItem>> into, MediaItem i) {
      final k = normalizeSearch(cleanTitle(i.name));
      if (k.isNotEmpty) (into[k] ??= []).add(i);
    }

    for (final m in movies) {
      add(_movies, m);
    }
    for (final s in series) {
      add(_series, s);
    }
  }

  MediaItem? find(DiscoverTitle t) {
    final c = (t.tv ? _series : _movies)[normalizeSearch(t.title)];
    if (c == null) return null;
    MediaItem? loose;
    for (final i in c) {
      final y = yearOf(i);
      if (y == null || t.year == null) {
        loose ??= i;
      } else if (y == t.year) {
        return i;
      } else if ((y - t.year!).abs() <= 1) {
        loose ??= i;
      }
    }
    return loose;
  }
}

/// The lists the Discover page shows: title, TMDB path and whether it is series.
const discoverRows = <({String title, String path, bool tv})>[
  (title: 'Trending movies', path: 'trending/movie/week', tv: false),
  (title: 'Trending series', path: 'trending/tv/week', tv: true),
  (title: 'Popular movies', path: 'movie/popular', tv: false),
  (title: 'Popular series', path: 'tv/popular', tv: true),
  (title: 'Top rated movies', path: 'movie/top_rated', tv: false),
  (title: 'Top rated series', path: 'tv/top_rated', tv: true),
];
