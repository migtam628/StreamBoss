import '../models/media.dart';

const _fold = {
  'àáâãäåāăą': 'a',
  'çćčĉċ': 'c',
  'ďđ': 'd',
  'èéêëēĕėęě': 'e',
  'ĝğġģ': 'g',
  'ìíîïĩīĭįı': 'i',
  'ķ': 'k',
  'ĺļľłŀ': 'l',
  'ñńņňŉ': 'n',
  'òóôõöøōŏő': 'o',
  'ŕŗř': 'r',
  'śŝşš': 's',
  'ţťŧ': 't',
  'ùúûüũūŭůűų': 'u',
  'ŵ': 'w',
  'ýÿŷ': 'y',
  'źżž': 'z',
};
final Map<int, String> _foldMap = {
  for (final e in _fold.entries)
    for (final c in e.key.runes) c: e.value,
};

/// Lowercase, accents removed, everything that is not a letter or digit turned into a space.
/// "Amélie (2001)" becomes "amelie 2001".
String normalizeSearch(String s) {
  final b = StringBuffer();
  var gap = true;
  for (final r in s.toLowerCase().runes) {
    final c = _foldMap[r];
    final isWord = c != null ||
        (r >= 0x30 && r <= 0x39) ||
        (r >= 0x61 && r <= 0x7a) ||
        r > 0x7f; // other scripts stay as they are
    if (isWord) {
      b.write(c ?? String.fromCharCode(r));
      gap = false;
    } else if (!gap) {
      b.write(' ');
      gap = true;
    }
  }
  return b.toString().trimRight();
}

/// How the results are ordered.
enum SearchSort { best, az, rating }

class SearchFilters {
  /// Which kinds to look in; empty means all.
  final Set<MediaKind> kinds;

  /// Category name (as shown to the user) to stay in, for a single kind.
  final String? category;
  final double? minRating;
  final SearchSort sort;
  const SearchFilters(
      {this.kinds = const {},
      this.category,
      this.minRating,
      this.sort = SearchSort.best});
}

class _Entry {
  final MediaItem item;
  final String name; // normalized
  final List<String> words;
  final String category; // normalized category name
  final double rating;
  _Entry(this.item, this.name, this.words, this.category, this.rating);
}

/// Every item of a catalog with its name already normalized, so a search is only comparisons.
class SearchIndex {
  final List<_Entry> _entries;
  final Map<MediaKind, List<String>> categoryNames;
  SearchIndex._(this._entries, this.categoryNames);

  factory SearchIndex.of(Catalog c) {
    final names = <MediaKind, Map<String, String>>{
      for (final k in MediaKind.values)
        k: {for (final x in c.categoriesFor(k)) x.id: x.name},
    };
    final entries = <_Entry>[];
    for (final k in MediaKind.values) {
      for (final i in c.itemsFor(k)) {
        final n = normalizeSearch(i.name);
        entries.add(_Entry(
            i,
            n,
            n.isEmpty ? const [] : n.split(' '),
            normalizeSearch(names[k]![i.categoryId] ?? ''),
            double.tryParse(i.rating ?? '') ?? 0));
      }
    }
    return SearchIndex._(entries, {
      for (final k in MediaKind.values)
        k: [for (final x in c.categoriesFor(k)) x.name],
    });
  }

  int get length => _entries.length;

  /// Items matching [query] (every word of it), best first. An empty query lists nothing.
  List<MediaItem> search(String query,
      {SearchFilters filters = const SearchFilters(),
      Set<String> favorites = const {},
      Set<String> recent = const {},
      int limit = 400}) {
    final q = normalizeSearch(query);
    if (q.length < 2) return const [];
    final tokens = q.split(' ');
    final wantCat =
        filters.category == null ? null : normalizeSearch(filters.category!);
    final hits = <(double, _Entry)>[];
    for (final e in _entries) {
      if (filters.kinds.isNotEmpty && !filters.kinds.contains(e.item.kind)) {
        continue;
      }
      if (wantCat != null && e.category != wantCat) continue;
      if (filters.minRating != null && e.rating < filters.minRating!) continue;
      final s = _score(e, q, tokens);
      if (s <= 0) continue;
      hits.add((
        s +
            (favorites.contains(e.item.key) ? 5 : 0) +
            (recent.contains(e.item.key) ? 3 : 0),
        e
      ));
    }
    switch (filters.sort) {
      case SearchSort.best:
        hits.sort((a, b) {
          final c = b.$1.compareTo(a.$1);
          return c != 0
              ? c
              : a.$2.name.length != b.$2.name.length
                  ? a.$2.name.length - b.$2.name.length
                  : a.$2.name.compareTo(b.$2.name);
        });
      case SearchSort.az:
        hits.sort((a, b) => a.$2.name.compareTo(b.$2.name));
      case SearchSort.rating:
        hits.sort((a, b) {
          final c = b.$2.rating.compareTo(a.$2.rating);
          return c != 0 ? c : b.$1.compareTo(a.$1);
        });
    }
    return [for (final h in hits.take(limit)) h.$2.item];
  }

  double _score(_Entry e, String q, List<String> tokens) {
    var total = 0.0;
    for (final t in tokens) {
      final w = _tokenScore(e, t);
      if (w == 0) return 0; // every word has to be found somewhere
      total += w;
    }
    if (e.name == q) total += 50;
    if (e.name.startsWith(q)) total += 30;
    if (e.name.contains(q)) total += 10; // the words in a row
    return total;
  }

  double _tokenScore(_Entry e, String t) {
    var best = 0.0;
    for (final w in e.words) {
      if (w == t) {
        best = 10;
        break;
      }
      if (w.startsWith(t)) {
        best = best < 8 ? 8 : best;
      } else if (best < 5 && t.length >= 3 && w.contains(t)) {
        best = 5;
      } else if (best < 3 &&
          t.length >= 4 &&
          w.length >= 4 &&
          _within(w, t, 1)) {
        best = 3; // a typo
      }
    }
    if (best == 0 && e.category.isNotEmpty && e.category.contains(t)) {
      best = 1.5; // the category names it
    }
    return best;
  }
}

/// True when the typed [t] is [word] (or the start of it) give or take [max] single-letter edits:
/// an inserted, missing or changed letter, or two neighbours swapped.
bool _within(String word, String t, int max) {
  if (word == t) return true;
  if ((word.length - t.length).abs() <= max && _edit(word, t) <= max) {
    return true;
  }
  if (word.length > t.length) {
    // A typo in the start of a longer word: compare with its same-length start (and one longer).
    if (_edit(word.substring(0, t.length), t) <= max) return true;
    if (word.length > t.length + 1 &&
        _edit(word.substring(0, t.length + 1), t) <= max) {
      return true;
    }
  }
  return false;
}

int _edit(String a, String b) {
  final n = a.length, m = b.length;
  if (n == 0) return m;
  if (m == 0) return n;
  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  for (var i = 1; i <= n; i++) {
    final cur = List<int>.filled(m + 1, 0)..[0] = i;
    for (var j = 1; j <= m; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        final t = prev2[j - 2] + 1;
        if (t < v) v = t;
      }
      cur[j] = v;
    }
    prev2 = prev;
    prev = cur;
  }
  return prev[m];
}
