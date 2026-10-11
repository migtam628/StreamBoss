import 'dart:convert';

/// "Remind me when this programme starts": a programme on a channel, and when it begins.
class Reminder {
  final String channelKey, channelName, title;

  /// When the programme starts, in milliseconds since the epoch.
  final int startMs;
  const Reminder({required this.channelKey, required this.channelName, required this.title, required this.startMs});

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMs);

  /// A number for the system's notification list that is the same on every run, so the same reminder is
  /// never scheduled twice and can be cancelled later. (FNV-1a, 31 bits.)
  int get id {
    var h = 0x811c9dc5;
    for (final u in utf8.encode('$channelKey|$startMs')) {
      h ^= u;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  Map<String, dynamic> toJson() => {'ch': channelKey, 'name': channelName, 'title': title, 'at': startMs};

  static Reminder? fromJson(Object? j) {
    if (j is! Map) return null;
    final ch = j['ch'], name = j['name'], title = j['title'], at = j['at'];
    if (ch is! String || title is! String || at is! num) return null;
    return Reminder(channelKey: ch, channelName: name is String ? name : ch, title: title, startMs: at.toInt());
  }
}

/// The lead times Settings offers, in minutes before the programme starts.
const reminderLeadChoices = [1, 5, 10, 15, 30];

/// When the reminder should go off: [leadMins] before the start, but never in the past (a programme that
/// starts in three minutes, with a ten minute lead, is reminded about at once).
DateTime reminderFireTime(Reminder r, int leadMins, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final at = r.start.subtract(Duration(minutes: leadMins));
  return at.isAfter(n) ? at : n.add(const Duration(seconds: 2));
}

/// Reminders worth keeping: the ones whose programme has not started more than [grace] ago.
List<Reminder> keepCurrent(Iterable<Reminder> all, {DateTime? now, Duration grace = const Duration(minutes: 10)}) {
  final cut = (now ?? DateTime.now()).subtract(grace).millisecondsSinceEpoch;
  return [
    for (final r in all)
      if (r.startMs >= cut) r,
  ]..sort((a, b) => a.startMs.compareTo(b.startMs));
}

/// The first reminder that is due: within [leadMins] of starting (or just started) and not yet shown.
Reminder? dueReminder(Iterable<Reminder> all, Set<int> shown, int leadMins, {DateTime? now}) {
  final n = (now ?? DateTime.now()).millisecondsSinceEpoch;
  for (final r in all) {
    if (shown.contains(r.id)) continue;
    final from = r.startMs - leadMins * 60000;
    if (n >= from && n < r.startMs + 5 * 60000) return r;
  }
  return null;
}

/// "Starts in 5 min", "Starting now", "Started 2 min ago".
String startsIn(Reminder r, {DateTime? now}) {
  final m = (r.startMs - (now ?? DateTime.now()).millisecondsSinceEpoch) / 60000;
  if (m >= 1.5) return 'Starts in ${m.round()} min';
  if (m > -1) return 'Starting now';
  return 'Started ${(-m).round()} min ago';
}
