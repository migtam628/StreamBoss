import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../screens/open_item.dart';
import '../services/time_format.dart';
import '../services/xmltv.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';

String _day(DateTime d) {
  final l = d.toLocal(), n = DateTime.now();
  if (l.year == n.year && l.month == n.month && l.day == n.day) return 'Today';
  final t = n.add(const Duration(days: 1));
  if (l.year == t.year && l.month == t.month && l.day == t.day) {
    return 'Tomorrow';
  }
  final y = n.subtract(const Duration(days: 1));
  if (l.year == y.year && l.month == y.month && l.day == y.day) {
    return 'Yesterday';
  }
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${names[l.weekday - 1]} ${l.day}/${l.month}';
}

/// What a programme is: its time, what the guide says about it, and what can be done with it.
/// [queue] lets "Watch live" zap through the other channels.
Future<void> showProgrammeSheet(BuildContext context, MediaItem ch, Programme p,
    {List<MediaItem>? queue}) {
  final app = context.read<AppState>();
  final use24h = context.read<SettingsState>().use24h;
  final pal = LayoutPalette.of(context);
  final now = DateTime.now();
  final live = !p.start.isAfter(now) && p.end.isAfter(now);
  final past = !p.end.isAfter(now);
  final catchUp = app.catchUpFor(ch, p);
  final mins = p.end.difference(p.start).inMinutes;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.surface,
    constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85, maxWidth: 640),
    builder: (sheet) => SafeArea(
      child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(p.title,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: pal.text)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${ch.name}  ·  ${_day(p.start)}  ${fmtTime(p.start, use24h: use24h)} to ${fmtTime(p.end, use24h: use24h)}'
                '${mins > 0 ? '  ·  $mins min' : ''}${live ? '  ·  on now' : ''}',
                style:
                    TextStyle(color: pal.accent2, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Text(
                  p.desc ?? 'The guide has no description for this programme.',
                  style: TextStyle(
                      color: p.desc == null ? pal.muted : pal.text,
                      height: 1.4,
                      fontSize: 15)),
            ),
            if (!live && !past) _ReminderTile(channel: ch, programme: p, sheet: sheet, outer: context, use24h: use24h),
            if (catchUp)
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.history),
                title: Text(
                    live ? 'Watch from the start' : 'Watch from the archive'),
                subtitle: Text(
                    'The provider keeps ${ch.archiveDays} day${ch.archiveDays == 1 ? '' : 's'} of ${ch.name}'),
                onTap: () {
                  Navigator.pop(sheet);
                  openCatchUp(context, ch, p);
                },
              ),
            if (!past)
              ListTile(
                autofocus: !catchUp,
                leading: const Icon(Icons.live_tv),
                title: Text(live ? 'Watch live' : 'Watch ${ch.name} now'),
                onTap: () {
                  Navigator.pop(sheet);
                  openItem(context, ch, queue: queue);
                },
              )
            else if (!catchUp)
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.live_tv),
                title: Text('Watch ${ch.name} now'),
                subtitle: Text(app.canCatchUp(ch)
                    ? 'This programme is older than the ${ch.archiveDays} days the provider keeps'
                    : 'This channel has no catch-up'),
                onTap: () {
                  Navigator.pop(sheet);
                  openItem(context, ch, queue: queue);
                },
              ),
          ]),
    ),
  );
}

/// Remind me / Remove the reminder, for a programme that has not started.
class _ReminderTile extends StatelessWidget {
  final MediaItem channel;
  final Programme programme;
  final BuildContext sheet, outer;
  final bool use24h;
  const _ReminderTile(
      {required this.channel, required this.programme, required this.sheet, required this.outer, required this.use24h});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final set = app.hasReminder(channel, programme);
    return ListTile(
      autofocus: true,
      leading: Icon(set ? Icons.notifications_active : Icons.notifications_none),
      title: Text(set ? 'Remove the reminder' : 'Remind me'),
      subtitle: Text(set
          ? 'You will be told ${app.reminderLead} min before it starts'
          : 'A notification ${app.reminderLead} min before ${fmtTime(programme.start, use24h: use24h)}'),
      onTap: () async {
        final messenger = ScaffoldMessenger.maybeOf(outer);
        Navigator.pop(sheet);
        if (set) {
          final r = app.reminders.firstWhere((e) => e.channelKey == channel.key && e.startMs == programme.start.millisecondsSinceEpoch);
          await app.removeReminder(r);
          messenger?.showSnackBar(const SnackBar(content: Text('Reminder removed')));
        } else {
          final res = await app.addReminder(channel, programme);
          messenger?.showSnackBar(SnackBar(
              content: Text(!res.added
                  ? 'That programme has already started'
                  : res.system
                      ? 'Reminder set for ${fmtTime(programme.start, use24h: use24h)}'
                      : 'Reminder set. It shows in the app while it is open (allow notifications to get it when it is closed)')));
        }
      },
    );
  }
}
