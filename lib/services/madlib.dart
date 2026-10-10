import '../models/media.dart';
import 'vod_filter.dart';

/// What the Madlib sentence can say it is. Provider data has no genre field, so a mood is a set of
/// words looked for in the category name, the title and the plot.
enum MadKind {
  movie('movie'),
  series('series'),
  live('live channel'),
  any('anything');

  final String label;
  const MadKind(this.label);
}

enum MadMood {
  any('anything', ''),
  funny('funny', r'(comed|funny|humou?r|sitcom|laugh)'),
  exciting('exciting', r'(action|adventure|thriller|crime|war\b|western)'),
  scary('scary', r'(horror|scary|terror|haunt|slasher|ghost)'),
  moving('moving', r'(drama|romanc|love|biograph)'),
  mindBending('mind-bending', r'(sci-?fi|science fiction|fantasy|mystery|space)'),
  familyFriendly('family friendly', r'(famil|kids?\b|child|animat|cartoon|disney)'),
  true_('true', r'(documentar|docu\b|nature|history|biograph|true story|real life)');

  final String label;
  final String pattern;
  const MadMood(this.label, this.pattern);

  RegExp? get regex => pattern.isEmpty ? null : RegExp(pattern, caseSensitive: false);
}

enum MadRating {
  any('any rating', 0),
  good('well rated', 7),
  great('top rated', 8);

  final String label;
  final double minimum;
  const MadRating(this.label, this.minimum);
}

/// One filled-in sentence.
class MadSentence {
  final MadKind kind;
  final MadMood mood;
  final MadRating rating;
  final Era era;
  const MadSentence({
    this.kind = MadKind.movie,
    this.mood = MadMood.any,
    this.rating = MadRating.any,
    this.era = Era.any,
  });

  MadSentence copyWith({MadKind? kind, MadMood? mood, MadRating? rating, Era? era}) => MadSentence(
        kind: kind ?? this.kind,
        mood: mood ?? this.mood,
        rating: rating ?? this.rating,
        era: era ?? this.era,
      );
}

/// The titles that fit [s], best rated first (the provider's order breaks ties). Live channels have
/// no rating or year, so a rating or year blank leaves them out.
List<MediaItem> madlibMatches(
  MadSentence s,
  Catalog c, {
  required String Function(MediaItem) categoryName,
}) {
  final pool = switch (s.kind) {
    MadKind.movie => c.movies,
    MadKind.series => c.series,
    MadKind.live => c.live,
    MadKind.any => [...c.movies, ...c.series, ...c.live],
  };
  final re = s.mood.regex;
  final out = <MediaItem>[];
  final catText = <String, String>{};
  for (final i in pool) {
    if (s.rating != MadRating.any) {
      if (i.kind == MediaKind.live || ratingOf(i) < s.rating.minimum) continue;
    }
    if (s.era != Era.any) {
      final y = yearOf(i);
      if (y == null || !s.era.holds(y)) continue;
    }
    if (re != null) {
      // The mood patterns are plain lower-case words, so the text needs no normalizing.
      if (!re.hasMatch(catText.putIfAbsent(i.categoryId, () => categoryName(i))) &&
          !re.hasMatch(i.name) &&
          !(i.plot != null && re.hasMatch(i.plot!))) {
        continue;
      }
    }
    out.add(i);
  }
  final at = {for (var n = 0; n < out.length; n++) out[n].key: n};
  out.sort((a, b) {
    final r = ratingOf(b).compareTo(ratingOf(a));
    return r != 0 ? r : at[a.key]! - at[b.key]!;
  });
  return out;
}
