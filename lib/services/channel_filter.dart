import '../models/media.dart';
import 'channel_merge.dart' show channelQuality;
import 'countries.dart';
import 'search.dart' show normalizeSearch;

/// The smallest picture quality a channel's name promises. Names that say nothing count as "any".
enum QualityFilter {
  any('Any quality'),
  hd('HD and up'),
  fhd('Full HD and up'),
  uhd('4K');

  final String label;
  const QualityFilter(this.label);

  /// The quality score (see [channelQuality]) a channel needs.
  int get minimum => switch (this) {
        QualityFilter.any => 0,
        QualityFilter.hd => 2,
        QualityFilter.fhd => 3,
        QualityFilter.uhd => 4,
      };
}

enum ChannelSort {
  provider('Provider order'),
  name('A to Z'),
  quality('Best quality first');

  final String label;
  const ChannelSort(this.label);
}

/// How the live channel lists are narrowed. One filter is shared by the Live screens and the Guide,
/// so a filter made in one place is still there in the other.
class ChannelFilter {
  /// Words that must all appear in the channel name or its category (accents and punctuation ignored).
  final String text;
  final QualityFilter quality;

  /// A country code (see [countries]), or null for every country.
  final String? country;
  final bool favoritesOnly;

  /// Only channels the guide has programmes for.
  final bool guideOnly;
  final ChannelSort sort;
  const ChannelFilter({
    this.text = '',
    this.quality = QualityFilter.any,
    this.country,
    this.favoritesOnly = false,
    this.guideOnly = false,
    this.sort = ChannelSort.provider,
  });

  static const none = ChannelFilter();

  /// How many of the narrowing options are on (the search words count as one).
  int get count =>
      (text.trim().isEmpty ? 0 : 1) +
      (quality == QualityFilter.any ? 0 : 1) +
      (country == null ? 0 : 1) +
      (favoritesOnly ? 1 : 0) +
      (guideOnly ? 1 : 0);

  bool get active => count > 0 || sort != ChannelSort.provider;

  ChannelFilter copyWith({
    String? text,
    QualityFilter? quality,
    Object? country = _keep,
    bool? favoritesOnly,
    bool? guideOnly,
    ChannelSort? sort,
  }) =>
      ChannelFilter(
        text: text ?? this.text,
        quality: quality ?? this.quality,
        country: identical(country, _keep) ? this.country : country as String?,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        guideOnly: guideOnly ?? this.guideOnly,
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) =>
      other is ChannelFilter &&
      other.text == text &&
      other.quality == quality &&
      other.country == country &&
      other.favoritesOnly == favoritesOnly &&
      other.guideOnly == guideOnly &&
      other.sort == sort;

  @override
  int get hashCode =>
      Object.hash(text, quality, country, favoritesOnly, guideOnly, sort);
}

const _keep = Object();

/// [channels] narrowed by [f]. [categoryName] gives a channel's category name (used for the words and
/// the country); [isFavorite] and [hasGuide] answer the two toggles.
List<MediaItem> applyChannelFilter(
  List<MediaItem> channels,
  ChannelFilter f, {
  required String Function(MediaItem) categoryName,
  required bool Function(MediaItem) isFavorite,
  required bool Function(MediaItem) hasGuide,
}) {
  if (!f.active) return channels;
  final words =
      normalizeSearch(f.text).split(' ').where((w) => w.isNotEmpty).toList();
  final out = <MediaItem>[];
  for (final c in channels) {
    if (f.favoritesOnly && !isFavorite(c)) continue;
    if (f.guideOnly && !hasGuide(c)) continue;
    if (f.quality != QualityFilter.any &&
        channelQuality(c.name) < f.quality.minimum) {
      continue;
    }
    final cat = categoryName(c);
    if (f.country != null &&
        (countryOf(cat) ?? countryOf(c.name))?.code != f.country) {
      continue;
    }
    if (words.isNotEmpty) {
      final hay = normalizeSearch('${c.name} $cat');
      if (!words.every(hay.contains)) continue;
    }
    out.add(c);
  }
  switch (f.sort) {
    case ChannelSort.provider:
      break;
    case ChannelSort.name:
      out.sort(
          (a, b) => normalizeSearch(a.name).compareTo(normalizeSearch(b.name)));
    case ChannelSort.quality:
      // Stable: equal quality keeps the provider's order.
      final at = {for (var i = 0; i < out.length; i++) out[i].key: i};
      out.sort((a, b) {
        final q = channelQuality(b.name) - channelQuality(a.name);
        return q != 0 ? q : at[a.key]! - at[b.key]!;
      });
  }
  return out;
}

/// The countries that appear among [channels], biggest first, for the filter's country list.
List<(Country, int)> countriesIn(
    List<MediaItem> channels, String Function(MediaItem) categoryName) {
  final counts = <String, int>{};
  final by = <String, Country>{};
  for (final c in channels) {
    final cn = countryOf(categoryName(c)) ?? countryOf(c.name);
    if (cn == null) continue;
    by[cn.code] = cn;
    counts[cn.code] = (counts[cn.code] ?? 0) + 1;
  }
  final out = [for (final e in counts.entries) (by[e.key]!, e.value)];
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}
