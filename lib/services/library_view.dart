import '../models/media.dart';
import 'channel_edits.dart';
import 'channel_merge.dart';

final _adult = RegExp(r'(\badult\b|\bxxx\b|\bporn|\b18\s*\+|\berotic|\bsex\b)', caseSensitive: false);

/// True for category names that are clearly adult content. This is a convenience filter
/// based on names, not a parental lock.
bool isAdultCategory(String name) => _adult.hasMatch(name);

final _kids = RegExp(r'(\bkids?\b|child|cartoon|animat|famil|junior|toddler|disney|nick)', caseSensitive: false);

/// True for category names that look made for children. Name based, so it is only as good as
/// the provider's naming.
bool isKidsCategory(String name) => _kids.hasMatch(name) && !_adult.hasMatch(name);

/// What the browse screens show: the loaded [c] minus hidden categories and channels, optionally
/// sorted A-Z. [hideKeys] are item keys to drop (channels that failed a check). [kidsOnly] keeps
/// only categories that look made for children. Returns [c] itself when no option is active.
Catalog buildView(Catalog c,
    {required bool hideAdult,
    required bool sortAz,
    Set<String> hideKeys = const {},
    bool kidsOnly = false,
    bool mergeDuplicates = false,
    Set<String> deadKeys = const {},
    ChannelEdits? channelEdits,
    Map<String, List<MediaItem>>? alternatesOut}) {
  final edited = channelEdits != null && !channelEdits.isEmpty;
  if (!hideAdult && !sortAz && hideKeys.isEmpty && !kidsOnly && !mergeDuplicates && !edited) return c;

  Set<String> blocked(List<Category> cs) => {
        for (final x in cs)
          if (((hideAdult || kidsOnly) && isAdultCategory(x.name)) || (kidsOnly && !isKidsCategory(x.name))) x.id
      };

  List<Category> cats(List<Category> cs, Set<String> b) {
    final r = cs.where((x) => !b.contains(x.id)).toList();
    if (sortAz) r.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return r;
  }

  List<MediaItem> items(List<MediaItem> l, Set<String> b) {
    final r = b.isEmpty && hideKeys.isEmpty && !kidsOnly
        ? [...l]
        : l.where((i) => !b.contains(i.categoryId) && !hideKeys.contains(i.key)).toList();
    if (sortAz) r.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return r;
  }

  // Kids' view is a whitelist, so an item whose category is not listed at all is dropped too.
  List<MediaItem> keepListed(List<MediaItem> l, List<Category> cs, Set<String> b) {
    if (!kidsOnly) return items(l, b);
    final ids = {for (final x in cs) x.id};
    return items(l.where((i) => ids.contains(i.categoryId)).toList(), b);
  }

  final bl = blocked(c.liveCategories);
  final bm = blocked(c.movieCategories);
  final bs = blocked(c.seriesCategories);
  var live = keepListed(c.live, c.liveCategories, bl);
  if (mergeDuplicates) {
    // Merge before sorting so the shown copy keeps its place in the provider's order.
    final m = mergeDuplicateChannels(live, deadKeys: deadKeys);
    live = m.channels;
    alternatesOut?.addAll(m.alternates);
  }
  // The viewer's own renames, hidden channels and pins come last, so they decide what is shown first.
  if (edited) live = applyChannelEdits(live, channelEdits);
  return Catalog(
    liveCategories: cats(c.liveCategories, bl),
    movieCategories: cats(c.movieCategories, bm),
    seriesCategories: cats(c.seriesCategories, bs),
    live: live,
    movies: keepListed(c.movies, c.movieCategories, bm),
    series: keepListed(c.series, c.seriesCategories, bs),
    epgUrl: c.epgUrl,
  );
}
