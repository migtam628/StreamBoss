import '../models/media.dart';
import 'xmltv.dart';

/// The four tabs of Tonight's Home.
enum TonightDay {
  now('Now'),
  tonight('Tonight'),
  tomorrow('Tomorrow'),
  catchUp('Catch-up');

  final String label;
  const TonightDay(this.label);
}

enum TonightKind { live, upcoming, resume, saved, archive }

/// One line on the timeline: a programme on a channel, or a title that can be watched any time.
class TonightEntry {
  final TonightKind kind;

  /// The channel for a programme, the movie or series otherwise.
  final MediaItem item;
  final Programme? programme;

  /// Why it is on the list, in a sentence ("You watch this channel most evenings").
  final String reason;
  const TonightEntry(this.kind, this.item, this.reason, {this.programme});

  String get title => programme?.title ?? item.name;
  DateTime? get when => programme?.start;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Chooses what goes on Tonight's timeline for [day].
///
/// Programmes come from the channels the person favors or watched lately, plus a sample of the rest, so
/// a new install still gets a list. Each is scored (favorite channel, recent channel, a proper length,
/// an evening start) and the best few are kept, at most two per channel and one per title, in time order.
/// Titles that can be watched any time (what is half watched, what is in My List) follow the timed ones
/// on the Now and Tonight tabs. With no guide data at all, only those remain.
List<TonightEntry> buildTonight({
  required DateTime now,
  required TonightDay day,
  required List<MediaItem> channels,
  required List<MediaItem> favorites,
  required List<MediaItem> recents,
  required List<Programme> Function(MediaItem channel) programmesFor,
  bool Function(MediaItem channel, Programme p)? canCatchUp,
  Duration? Function(MediaItem item)? resumeFor,
  int max = 6,
}) {
  final local = now.toLocal();
  final midnight = DateTime(local.year, local.month, local.day);
  final tomorrowStart = midnight.add(const Duration(days: 1));
  // "Tonight" runs until 4 in the morning: a film that starts at 11 pm still counts.
  final tonightEnd = tomorrowStart.add(const Duration(hours: 4));

  final favKeys = {for (final f in favorites) f.key};
  final recentKeys = {for (final r in recents) r.key};
  int affinity(MediaItem c) =>
      favKeys.contains(c.key) ? 3 : (recentKeys.contains(c.key) ? 2 : 0);

  // Channels to look at: the ones the person has shown interest in, then a sample of the rest.
  final seen = <String>{};
  final pool = <MediaItem>[];
  void add(MediaItem c) {
    if (c.kind == MediaKind.live && seen.add(c.key)) {
      pool.add(c);
    }
  }

  for (final c in channels) {
    if (affinity(c) > 0) {
      add(c);
    }
  }
  for (final c in [...favorites, ...recents]) {
    add(c);
  }
  for (final c in channels) {
    if (pool.length >= 80) {
      break;
    }
    add(c);
  }

  final timed = <(double, TonightEntry)>[];
  for (final c in pool) {
    final a = affinity(c);
    for (final p in programmesFor(c)) {
      final mins = p.end.difference(p.start).inMinutes;
      if (mins < 5) {
        continue;
      }
      final TonightKind kind;
      switch (day) {
        case TonightDay.now:
          if (p.start.toLocal().isAfter(local) ||
              !p.end.toLocal().isAfter(local)) {
            continue;
          }
          kind = TonightKind.live;
        case TonightDay.tonight:
          final isNow = !p.start.toLocal().isAfter(local) &&
              p.end.toLocal().isAfter(local);
          if (!isNow &&
              (p.start.toLocal().isBefore(local) ||
                  !p.start.toLocal().isBefore(tonightEnd))) {
            continue;
          }
          kind = isNow ? TonightKind.live : TonightKind.upcoming;
        case TonightDay.tomorrow:
          // From where Tonight ends, so the small hours are not listed twice.
          final s = p.start.toLocal();
          if (s.isBefore(tonightEnd) ||
              !s.isBefore(tonightEnd.add(const Duration(days: 1)))) {
            continue;
          }
          kind = TonightKind.upcoming;
        case TonightDay.catchUp:
          final e = p.end.toLocal();
          if (e.isAfter(local) ||
              e.isBefore(local.subtract(const Duration(days: 1)))) {
            continue;
          }
          if (canCatchUp == null || !canCatchUp(c, p)) {
            continue;
          }
          kind = TonightKind.archive;
      }
      final hour = p.start.toLocal().hour;
      var score = a.toDouble();
      score += mins >= 75 ? 1.5 : (mins >= 25 ? 0.5 : -1);
      if (hour >= 18 && hour <= 23) {
        score += 0.5;
      }
      if (kind == TonightKind.live) {
        score += 0.5;
      }
      final reason = switch (kind) {
        TonightKind.live => a == 3
            ? 'It is on now, on a channel in your favorites.'
            : (a == 2
                ? 'It is on now, on a channel you watched lately.'
                : 'It is on now.'),
        TonightKind.archive => 'You can watch it from the provider\'s archive.',
        _ => a == 3
            ? 'On a channel in your favorites.'
            : (a == 2
                ? 'On a channel you watched lately.'
                : 'Starts ${_when(p.start.toLocal(), local)}.'),
      };
      timed.add((score, TonightEntry(kind, c, reason, programme: p)));
    }
  }

  // Best first; keep at most two per channel and one per title.
  timed.sort((x, y) {
    final c = y.$1.compareTo(x.$1);
    return c != 0 ? c : x.$2.programme!.start.compareTo(y.$2.programme!.start);
  });
  final perChannel = <String, int>{};
  final titles = <String>{};
  final chosen = <TonightEntry>[];
  for (final (_, e) in timed) {
    if (chosen.length >= max) {
      break;
    }
    if ((perChannel[e.item.key] ?? 0) >= 2) {
      continue;
    }
    if (!titles.add(_norm(e.programme!.title))) {
      continue;
    }
    perChannel[e.item.key] = (perChannel[e.item.key] ?? 0) + 1;
    chosen.add(e);
  }
  chosen.sort((a, b) => day == TonightDay.catchUp
      ? b.programme!.start.compareTo(a.programme!.start)
      : a.programme!.start.compareTo(b.programme!.start));

  // Anything that can be watched at any time follows the timed lines.
  final anytime = <TonightEntry>[];
  if (day == TonightDay.now || day == TonightDay.tonight) {
    final take = day == TonightDay.now ? 1 : 2;
    final used = <String>{};
    for (final r in recents) {
      if (r.kind == MediaKind.live || anytime.length >= take) {
        continue;
      }
      final at = resumeFor?.call(r);
      if (at == null && day == TonightDay.now) {
        continue;
      }
      if (used.add(r.key)) {
        anytime.add(TonightEntry(
            TonightKind.resume, r, 'You are partway through this.'));
      }
    }
    if (day == TonightDay.tonight) {
      var saved = 0;
      for (final f in favorites) {
        if (f.kind == MediaKind.live || used.contains(f.key) || saved >= 2) {
          continue;
        }
        used.add(f.key);
        saved++;
        anytime.add(
            TonightEntry(TonightKind.saved, f, 'You saved this to My List.'));
      }
    }
  }
  return [...chosen, ...anytime];
}

String _when(DateTime start, DateTime now) {
  final m = start.difference(now).inMinutes;
  if (m < 60) {
    return 'in $m min';
  }
  if (m < 24 * 60) {
    return 'in ${m ~/ 60} h ${m % 60} min';
  }
  return 'tomorrow';
}

/// A short label for the left of a timeline line: the start time, or "Any time".
String tonightTimeLabel(TonightEntry e, String Function(DateTime) fmt) {
  final w = e.when;
  return w == null ? 'Any time' : fmt(w);
}
