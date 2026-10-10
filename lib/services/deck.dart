import '../models/media.dart';
import 'recommend.dart';

/// One card: a title and the line that says why it is in the deck.
class DeckCard {
  final MediaItem item;
  final String reason;
  const DeckCard(this.item, this.reason);
}

double _rate(MediaItem i) => double.tryParse(i.rating ?? '') ?? 0;

/// The deck for tonight: up to [max] movies and series. What fits the viewer's history comes first
/// ([recommendation]), then well-rated titles they have not touched, alternating movies and series so
/// the deck is not all one kind. Anything saved, already watched or skipped lately is left out.
/// [seed] (the day, say) varies the later cards from one day to the next without reshuffling during one.
List<DeckCard> buildDeck({
  required Catalog catalog,
  required Recommendation? recommendation,
  required List<MediaItem> recents,
  required Set<String> favorites,
  required Set<String> skipped,
  int seed = 0,
  int max = 12,
}) {
  final seen = {for (final r in recents) r.key};
  bool free(MediaItem i) =>
      !favorites.contains(i.key) &&
      !skipped.contains(i.key) &&
      !seen.contains(i.key);
  final out = <DeckCard>[];
  final used = <String>{};
  void add(MediaItem i, String reason) {
    if (out.length >= max || !free(i) || !used.add(i.key)) return;
    out.add(DeckCard(i, reason));
  }

  if (recommendation != null) {
    for (final i in recommendation.items) {
      if (i.kind != MediaKind.live) add(i, recommendation.reason);
    }
  }

  List<MediaItem> best(List<MediaItem> l) {
    final c = [
      for (final i in l)
        if (free(i) && !used.contains(i.key)) i
    ];
    // Best rated first; a stable day-based rotation breaks ties so ties do not always favour the same titles.
    c.sort((a, b) {
      final r = _rate(b).compareTo(_rate(a));
      return r != 0
          ? r
          : ((a.key.hashCode ^ seed) & 0xffff)
              .compareTo((b.key.hashCode ^ seed) & 0xffff);
    });
    return c.take(max).toList();
  }

  final movies = best(catalog.movies), series = best(catalog.series);
  for (var k = 0;
      out.length < max && (k < movies.length || k < series.length);
      k++) {
    if (k < movies.length) {
      add(movies[k],
          _rate(movies[k]) >= 7 ? 'Highly rated' : 'Something different');
    }
    if (k < series.length) {
      add(series[k],
          _rate(series[k]) >= 7 ? 'Highly rated' : 'Something different');
    }
  }
  return out;
}
