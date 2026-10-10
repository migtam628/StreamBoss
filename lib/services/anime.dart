import '../models/media.dart';

/// Category names that look like anime: Anime itself, manga, the Chinese and Korean cousins, and the
/// usual genre words. Name based, so it is only as good as the provider's naming.
final _animeCategory = RegExp(
    r'(anime|animé|manga|donghua|shonen|shounen|shoujo|shojo|seinen|isekai|\bova\b|\bona\b|toonami|crunchyroll|funimation)',
    caseSensitive: false);

/// A title that says it is anime itself, in a category that does not.
final _animeTitle = RegExp(r'[\[(]\s*anime\s*[\])]', caseSensitive: false);

bool isAnimeCategory(String name) => _animeCategory.hasMatch(name);

/// Where the anime is: the categories of [kind] that look like anime, and every title in them, plus
/// titles elsewhere that tag themselves "(Anime)".
({List<Category> categories, List<MediaItem> items}) animeOf(
    Catalog c, MediaKind kind) {
  final cats = [
    for (final cat in c.categoriesFor(kind))
      if (isAnimeCategory(cat.name)) cat
  ];
  final ids = {for (final cat in cats) cat.id};
  final items = [
    for (final i in c.itemsFor(kind))
      if (ids.contains(i.categoryId) || _animeTitle.hasMatch(i.name)) i
  ];
  return (categories: cats, items: items);
}

/// How many anime titles there are in each kind, for the page's chips and for deciding whether to
/// show the page at all.
Map<MediaKind, int> animeCounts(Catalog c) => {
      for (final k in MediaKind.values) k: animeOf(c, k).items.length,
    };
