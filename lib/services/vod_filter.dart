import '../models/media.dart';
import 'search.dart' show normalizeSearch;

/// The release years a title can be narrowed to.
enum Era {
  any('Any year'),
  y2020('2020s'),
  y2010('2010s'),
  y2000('2000s'),
  older('1990s and older');

  final String label;
  const Era(this.label);

  bool holds(int year) => switch (this) {
        Era.any => true,
        Era.y2020 => year >= 2020,
        Era.y2010 => year >= 2010 && year < 2020,
        Era.y2000 => year >= 2000 && year < 2010,
        Era.older => year < 2000,
      };
}

enum VodSort {
  provider('Provider order'),
  name('A to Z'),
  rating('Best rated first'),
  newest('Newest first');

  final String label;
  const VodSort(this.label);
}

/// How the Movies, Series and Anime lists are narrowed. One filter per list, kept while the app runs.
class VodFilter {
  /// Words that must all appear in the title or its category (accents and punctuation ignored).
  final String text;

  /// The lowest rating (out of 10) a title needs; 0 lets everything through, unrated titles included.
  final double minRating;
  final Era era;
  final bool favoritesOnly;

  /// Leaves out what you are partway through or have opened lately.
  final bool unwatchedOnly;
  final VodSort sort;
  const VodFilter({
    this.text = '',
    this.minRating = 0,
    this.era = Era.any,
    this.favoritesOnly = false,
    this.unwatchedOnly = false,
    this.sort = VodSort.provider,
  });

  static const none = VodFilter();

  /// The ratings the filter offers.
  static const ratingSteps = [0.0, 6.0, 7.0, 8.0];

  int get count =>
      (text.trim().isEmpty ? 0 : 1) +
      (minRating > 0 ? 1 : 0) +
      (era == Era.any ? 0 : 1) +
      (favoritesOnly ? 1 : 0) +
      (unwatchedOnly ? 1 : 0);

  bool get active => count > 0 || sort != VodSort.provider;

  VodFilter copyWith({
    String? text,
    double? minRating,
    Era? era,
    bool? favoritesOnly,
    bool? unwatchedOnly,
    VodSort? sort,
  }) =>
      VodFilter(
        text: text ?? this.text,
        minRating: minRating ?? this.minRating,
        era: era ?? this.era,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        unwatchedOnly: unwatchedOnly ?? this.unwatchedOnly,
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) =>
      other is VodFilter &&
      other.text == text &&
      other.minRating == minRating &&
      other.era == era &&
      other.favoritesOnly == favoritesOnly &&
      other.unwatchedOnly == unwatchedOnly &&
      other.sort == sort;

  @override
  int get hashCode =>
      Object.hash(text, minRating, era, favoritesOnly, unwatchedOnly, sort);
}

final _year = RegExp(r'(?<!\d)(19[3-9]\d|20[0-3]\d)(?!\d)');

/// The release year in a title such as "Harbor Lights (2021)" or "Harbor Lights 2021", else null.
/// Takes the last year-looking number, so "2012 (2009)" reads as 2009.
int? yearOf(MediaItem i) {
  final ms = _year.allMatches(i.name).toList();
  return ms.isEmpty ? null : int.parse(ms.last.group(0)!);
}

/// The rating out of 10, 0 when there is none. Some providers rate out of 5 or 100.
double ratingOf(MediaItem i) {
  final v = double.tryParse((i.rating ?? '').trim()) ?? 0;
  if (v > 10) return v / 10;
  return v;
}

/// [items] narrowed by [f]. [categoryName] gives a title's category name (searched with the words);
/// [isFavorite] and [started] answer the two toggles.
List<MediaItem> applyVodFilter(
  List<MediaItem> items,
  VodFilter f, {
  required String Function(MediaItem) categoryName,
  required bool Function(MediaItem) isFavorite,
  required bool Function(MediaItem) started,
}) {
  if (!f.active) return items;
  final words =
      normalizeSearch(f.text).split(' ').where((w) => w.isNotEmpty).toList();
  final out = <MediaItem>[];
  for (final i in items) {
    if (f.favoritesOnly && !isFavorite(i)) continue;
    if (f.unwatchedOnly && started(i)) continue;
    if (f.minRating > 0 && ratingOf(i) < f.minRating) continue;
    if (f.era != Era.any) {
      final y = yearOf(i);
      if (y == null || !f.era.holds(y)) continue;
    }
    if (words.isNotEmpty) {
      final hay = normalizeSearch('${i.name} ${categoryName(i)}');
      if (!words.every(hay.contains)) continue;
    }
    out.add(i);
  }
  final at = {for (var n = 0; n < out.length; n++) out[n].key: n};
  switch (f.sort) {
    case VodSort.provider:
      break;
    case VodSort.name:
      out.sort(
          (a, b) => normalizeSearch(a.name).compareTo(normalizeSearch(b.name)));
    case VodSort.rating:
      out.sort((a, b) {
        final r = ratingOf(b).compareTo(ratingOf(a));
        return r != 0 ? r : at[a.key]! - at[b.key]!;
      });
    case VodSort.newest:
      // Titles with no year sort last.
      out.sort((a, b) {
        final r = (yearOf(b) ?? 0).compareTo(yearOf(a) ?? 0);
        return r != 0 ? r : at[a.key]! - at[b.key]!;
      });
  }
  return out;
}
