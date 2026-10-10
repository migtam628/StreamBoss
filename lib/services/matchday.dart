import '../models/media.dart';
import 'channel_merge.dart' show channelQuality;
import 'search.dart' show normalizeSearch;
import 'xmltv.dart';

/// The sports Matchday sorts events into, in the order its tabs show them.
enum Sport {
  football('Football', r'(football|soccer|fútbol|futbol|liga|premier league|bundesliga|serie a|ligue 1|champions league|europa league|uefa|fifa|copa|eredivisie|mls)'),
  basketball('Basketball', r'(basketball|\bnba\b|euroleague|\bwnba\b|ncaa basketball)'),
  tennis('Tennis', r'(tennis|atp|wta|roland garros|wimbledon|davis cup|us open|australian open)'),
  racing('Racing', r'(formula|\bf1\b|motogp|nascar|indycar|rally|racing|grand prix)'),
  fighting('Fighting', r'(\bufc\b|boxing|\bwwe\b|\bmma\b|wrestling)'),
  american('American football', r'(\bnfl\b|ncaa football|super bowl)'),
  baseball('Baseball', r'(baseball|\bmlb\b)'),
  hockey('Hockey', r'(hockey|\bnhl\b)'),
  other('Other sport', r'(sport|golf|cricket|rugby|cycling|athletics|olympic|darts|snooker|handball|volleyball)');

  final String label;
  final String pattern;
  const Sport(this.label, this.pattern);

  RegExp get regex => RegExp(pattern, caseSensitive: false);
}

/// One event in the day's schedule and the channels that carry it.
class MatchEvent {
  final String title;
  final Sport sport;
  final DateTime start, end;

  /// Best first: favorites, then picture quality, then the guide's own order.
  final List<MediaItem> channels;
  const MatchEvent(this.title, this.sport, this.start, this.end, this.channels);

  bool isLive(DateTime now) => !now.isBefore(start) && now.isBefore(end);
  Duration startsIn(DateTime now) => start.difference(now);
}

final _versus = RegExp(r'\b(v|vs|vs\.|x)\b|\s-\s|\s–\s', caseSensitive: false);

/// True for category names that hold sport.
bool isSportCategory(String name) {
  final n = name.toLowerCase();
  return Sport.values.any((s) => s.regex.hasMatch(n));
}

/// Which sport a title (or its category) is about, or null for something that is not sport.
Sport? sportOf(String title, String category) {
  // The title decides first: a tennis match on a channel in "Premier League Sports" is still tennis.
  for (final text in [title, category]) {
    for (final s in Sport.values) {
      if (s != Sport.other && s.regex.hasMatch(text)) return s;
    }
  }
  if (Sport.other.regex.hasMatch(title) || Sport.other.regex.hasMatch(category)) {
    return Sport.other;
  }
  return null;
}

/// The day's sport from the guide, soonest first: every programme on a channel in a sport category (or
/// whose title is clearly sport) that is on now, or starts before [until]. The same event on several
/// channels (same title, starting within ten minutes) is one line with all its channels. Events that
/// ended more than [pastMinutes] ago are left out. Any programme on a sports channel counts. On any
/// other channel it needs an "A v B" title that also names a sport, so a news show or a debate is not
/// mistaken for a match.
List<MatchEvent> buildMatchday({
  required DateTime now,
  required DateTime until,
  required List<MediaItem> channels,
  required String Function(MediaItem) categoryName,
  required List<Programme> Function(MediaItem) programmesFor,
  bool Function(MediaItem)? isFavorite,
  int pastMinutes = 0,
}) {
  final cut = now.subtract(Duration(minutes: pastMinutes));
  final byKey = <String, List<(MediaItem, Programme, Sport)>>{};
  for (final ch in channels) {
    final cat = categoryName(ch);
    final sportsChannel = isSportCategory(cat) || Sport.values.any((s) => s.regex.hasMatch(ch.name));
    for (final p in programmesFor(ch)) {
      if (p.end.isBefore(cut) || !p.start.isBefore(until)) continue;
      final sport = sportOf(p.title, sportsChannel ? '$cat ${ch.name}' : '');
      if (sport == null) continue;
      if (!sportsChannel && !_versus.hasMatch(p.title)) continue;
      // Ten-minute buckets so "starts 19:00" and "starts 19:05" meet.
      final bucket = p.start.millisecondsSinceEpoch ~/ (10 * 60 * 1000);
      byKey.putIfAbsent('${normalizeSearch(p.title)}|$bucket', () => []).add((ch, p, sport));
    }
  }
  final out = <MatchEvent>[];
  for (final group in byKey.values) {
    final first = group.first.$2;
    final seen = <String>{};
    final chans = [
      for (final g in group)
        if (seen.add(g.$1.key)) g.$1
    ];
    final order = {for (var i = 0; i < chans.length; i++) chans[i].key: i};
    chans.sort((a, b) {
      final fa = (isFavorite?.call(a) ?? false) ? 1 : 0;
      final fb = (isFavorite?.call(b) ?? false) ? 1 : 0;
      if (fa != fb) return fb - fa;
      final q = channelQuality(b.name) - channelQuality(a.name);
      return q != 0 ? q : order[a.key]! - order[b.key]!;
    });
    out.add(MatchEvent(first.title, group.first.$3, first.start, first.end, chans));
  }
  out.sort((a, b) {
    final live = (b.isLive(now) ? 1 : 0) - (a.isLive(now) ? 1 : 0);
    if (live != 0) return live;
    return a.start.compareTo(b.start);
  });
  return out;
}

/// "12 min", "in 3 h" or "tomorrow" style text is left to the screen; this is the clock label.
String matchTimeLabel(MatchEvent e, DateTime now, {required bool use24h}) {
  if (e.isLive(now)) return 'NOW';
  final t = e.start.toLocal();
  final h = use24h ? t.hour : (t.hour % 12 == 0 ? 12 : t.hour % 12);
  final m = t.minute.toString().padLeft(2, '0');
  return use24h ? '${h.toString().padLeft(2, '0')}:$m' : '$h:$m';
}
