import '../models/media.dart';
import 'search.dart' show normalizeSearch;

// Words that say how a channel is delivered, not which channel it is.
final _quality = RegExp(
    r'\b(?:uhd|fhd|hd|sd|4k|8k|hevc|h ?26[45]|2160p?|1080[pi]?|720p?|576p?|480p?|50 ?fps|60 ?fps|raw|backup|alt)\b');

/// The name of a channel with the delivery words removed, so "Sky Sports 1 HD", "Sky Sports 1 [FHD]"
/// and "Sky Sports 1 SD" all come out as "sky sports 1". A country or language tag is kept, so
/// "US: Fox" and "UK: Fox" stay two channels. Numbers are kept too: "Sports 1" is not "Sports 2".
String channelBase(String name) {
  final full = normalizeSearch(name);
  final base =
      full.replaceAll(_quality, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return base.isEmpty ? full : base;
}

/// 4 = 4K, 3 = Full HD, 2 = HD, 1 = nothing said, 0 = SD. The best copy is shown.
int channelQuality(String name) {
  final n = normalizeSearch(name);
  if (RegExp(r'\b(?:uhd|4k|8k|2160p?)\b').hasMatch(n)) return 4;
  if (RegExp(r'\b(?:fhd|1080[pi]?)\b').hasMatch(n)) return 3;
  if (RegExp(r'\b(?:hd|720p?)\b').hasMatch(n)) return 2;
  if (RegExp(r'\b(?:sd|576p?|480p?)\b').hasMatch(n)) return 0;
  return 1;
}

class MergedChannels {
  /// One entry per channel, in the order the first copy appeared.
  final List<MediaItem> channels;

  /// Other copies of a channel, best first, by the key of the entry shown.
  final Map<String, List<MediaItem>> alternates;
  const MergedChannels(this.channels, this.alternates);
}

/// Collapses channels that are the same channel under another name (HD, SD, a backup, a different
/// panel) into one entry. The copy shown is the best one that is not in [deadKeys]; the others are
/// kept as [MergedChannels.alternates] to fall back on when it will not play.
MergedChannels mergeDuplicateChannels(List<MediaItem> live,
    {Set<String> deadKeys = const {}}) {
  final groups = <String, List<MediaItem>>{};
  final order = <String>[];
  for (final c in live) {
    final k = channelBase(c.name);
    final g = groups[k];
    if (g == null) {
      groups[k] = [c];
      order.add(k);
    } else {
      g.add(c);
    }
  }
  final out = <MediaItem>[];
  final alts = <String, List<MediaItem>>{};
  for (final k in order) {
    final g = groups[k]!;
    if (g.length == 1) {
      out.add(g.single);
      continue;
    }
    final index = {for (var i = 0; i < g.length; i++) g[i].key: i};
    final ranked = [...g]..sort((a, b) {
        final da = deadKeys.contains(a.key) ? 1 : 0,
            db = deadKeys.contains(b.key) ? 1 : 0;
        if (da != db) return da - db;
        final q = channelQuality(b.name) - channelQuality(a.name);
        return q != 0 ? q : index[a.key]! - index[b.key]!;
      });
    final best = ranked.first;
    // What the best copy lacks, another copy often has.
    final epg = best.epgId ??
        ranked.map((e) => e.epgId).whereType<String>().firstOrNull;
    final poster = best.poster ??
        ranked.map((e) => e.poster).whereType<String>().firstOrNull;
    final shown = epg == best.epgId && poster == best.poster
        ? best
        : best.copyWith(epgId: epg, poster: poster);
    out.add(shown);
    alts[shown.key] = ranked.skip(1).toList();
  }
  return MergedChannels(out, alts);
}
