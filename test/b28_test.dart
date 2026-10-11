import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/settings/settings_pages.dart';
import 'package:streamboss/services/reminder_notifier.dart';
import 'package:streamboss/services/reminders.dart';
import 'package:streamboss/services/xmltv.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/programme_sheet.dart';
import 'package:streamboss/widgets/reminder_banner.dart';

class FakeNotifier implements ReminderNotifier {
  bool allowed = true;
  final scheduled = <(int, DateTime, String)>[];
  final cancelled = <int>[];
  int cancelAlls = 0;
  @override
  bool get supported => allowed;
  @override
  Future<bool> ensurePermission() async => allowed;
  @override
  Future<void> schedule(Reminder r, DateTime at, String body) async => scheduled.add((r.id, at, body));
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
  @override
  Future<void> cancelAll() async => cancelAlls++;
}

MediaItem chan(String id, String name) =>
    MediaItem(id: id, name: name, kind: MediaKind.live, categoryId: 'c', streamUrl: 'http://x/$id');

Reminder rem(String ch, int minsFromNow, {String title = 'Match'}) => Reminder(
    channelKey: ch, channelName: 'Sportsline', title: title, startMs: DateTime.now().add(Duration(minutes: minsFromNow)).millisecondsSinceEpoch);

Future<(AppState, SettingsState, FakeNotifier)> boot({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final st = SettingsState();
  await st.init();
  final app = AppState()..bindSettings(st);
  await app.init();
  final n = FakeNotifier();
  app.notifier = n;
  return (app, st, n);
}

void main() {
  group('reminder logic', () {
    test('the id is the same on every run and differs per channel and time', () {
      const a = Reminder(channelKey: 'live:1', channelName: 'A', title: 'x', startMs: 1700000000000);
      const same = Reminder(channelKey: 'live:1', channelName: 'renamed', title: 'y', startMs: 1700000000000);
      const other = Reminder(channelKey: 'live:2', channelName: 'A', title: 'x', startMs: 1700000000000);
      const later = Reminder(channelKey: 'live:1', channelName: 'A', title: 'x', startMs: 1700000060000);
      expect(a.id, same.id);
      expect(a.id, isNot(other.id));
      expect(a.id, isNot(later.id));
      expect(a.id, inInclusiveRange(0, 0x7fffffff));
      expect(a.id, 490178174, reason: 'pinned so a change to the hash is noticed: it would orphan scheduled notifications');
    });

    test('json round trip, and junk is refused', () {
      final r = rem('live:1', 30);
      final back = Reminder.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(back!.title, r.title);
      expect(back.startMs, r.startMs);
      expect(Reminder.fromJson('nope'), isNull);
      expect(Reminder.fromJson({'ch': 1}), isNull);
    });

    test('it fires the lead time before the start, never in the past', () {
      final now = DateTime(2026, 10, 10, 20, 0);
      final r = Reminder(channelKey: 'k', channelName: 'c', title: 't', startMs: now.add(const Duration(minutes: 30)).millisecondsSinceEpoch);
      expect(reminderFireTime(r, 5, now: now), now.add(const Duration(minutes: 25)));
      expect(reminderFireTime(r, 60, now: now), now.add(const Duration(seconds: 2)));
    });

    test('old reminders are dropped, the rest kept in time order', () {
      final now = DateTime(2026, 10, 10, 20, 0);
      Reminder at(int m) => Reminder(channelKey: 'k$m', channelName: 'c', title: 't', startMs: now.add(Duration(minutes: m)).millisecondsSinceEpoch);
      final kept = keepCurrent([at(40), at(-30), at(5), at(-5)], now: now);
      expect(kept.map((e) => e.channelKey), ['k-5', 'k5', 'k40']);
    });

    test('due means within the lead time and not yet shown', () {
      final now = DateTime(2026, 10, 10, 20, 0);
      final r = Reminder(channelKey: 'k', channelName: 'c', title: 't', startMs: now.add(const Duration(minutes: 4)).millisecondsSinceEpoch);
      expect(dueReminder([r], {}, 5, now: now)?.channelKey, 'k');
      expect(dueReminder([r], {r.id}, 5, now: now), isNull);
      expect(dueReminder([r], {}, 1, now: now), isNull, reason: 'lead is one minute and it is four away');
      expect(dueReminder([r], {}, 5, now: now.add(const Duration(minutes: 20))), isNull, reason: 'long over');
    });

    test('startsIn reads plainly', () {
      final now = DateTime(2026, 10, 10, 20, 0);
      Reminder at(int sec) => Reminder(channelKey: 'k', channelName: 'c', title: 't', startMs: now.add(Duration(seconds: sec)).millisecondsSinceEpoch);
      expect(startsIn(at(300), now: now), 'Starts in 5 min');
      expect(startsIn(at(20), now: now), 'Starting now');
      expect(startsIn(at(-180), now: now), 'Started 3 min ago');
    });
  });

  group('reminders in the app', () {
    final ch = chan('1', 'Sportsline');
    Programme soon(int mins, {String title = 'Arsenal v Chelsea'}) =>
        Programme(title, DateTime.now().add(Duration(minutes: mins)), DateTime.now().add(Duration(minutes: mins + 90)));

    test('adding schedules a notification the lead time before, and survives a restart', () async {
      final (app, st, n) = await boot();
      final p = soon(30);
      final res = await app.addReminder(ch, p);
      expect(res.added, isTrue);
      expect(res.system, isTrue);
      expect(app.hasReminder(ch, p), isTrue);
      expect(n.scheduled.single.$1, app.reminders.single.id);
      expect(n.scheduled.single.$2.difference(p.start).inMinutes, -5);
      expect(n.scheduled.single.$3, contains('Sportsline'));
      expect(st.reminderLead, 5);

      // a second app on the same storage sees it
      final again = AppState()..bindSettings(st);
      await again.init();
      expect(again.reminders.single.title, 'Arsenal v Chelsea');
    });

    test('a programme that has started cannot be reminded about', () async {
      final (app, _, n) = await boot();
      final res = await app.addReminder(ch, Programme('x', DateTime.now().subtract(const Duration(minutes: 5)), DateTime.now().add(const Duration(minutes: 30))));
      expect(res.added, isFalse);
      expect(app.reminders, isEmpty);
      expect(n.scheduled, isEmpty);
    });

    test('asking twice keeps one', () async {
      final (app, _, n) = await boot();
      final p = soon(30);
      await app.addReminder(ch, p);
      await app.addReminder(ch, p);
      expect(app.reminders.length, 1);
      expect(n.scheduled.length, 1);
    });

    test('without notification permission it is still added, for the banner', () async {
      final (app, _, n) = await boot();
      n.allowed = false;
      final res = await app.addReminder(ch, soon(30));
      expect(res.added, isTrue);
      expect(res.system, isFalse);
      expect(n.scheduled, isEmpty);
    });

    test('removing cancels the notification', () async {
      final (app, _, n) = await boot();
      await app.addReminder(ch, soon(30));
      final r = app.reminders.single;
      await app.removeReminder(r);
      expect(app.reminders, isEmpty);
      expect(n.cancelled, [r.id]);
    });

    test('changing the lead time schedules everything again', () async {
      final (app, st, n) = await boot();
      await app.addReminder(ch, soon(60));
      st.set('reminderLead', 15);
      await app.rescheduleReminders();
      expect(n.cancelAlls, 1);
      expect(n.scheduled.length, 2);
      expect(n.scheduled.last.$2.difference(app.reminders.single.start).inMinutes, -15);
    });

    test('the banner comes once when the time is near, and not again after it is dismissed', () async {
      final (app, _, _) = await boot();
      await app.addReminder(ch, soon(30));
      app.checkReminders();
      expect(app.bannerReminder, isNull, reason: 'thirty minutes away');
      final near = DateTime.now().add(const Duration(minutes: 27));
      app.checkReminders(now: near);
      expect(app.bannerReminder?.title, 'Arsenal v Chelsea');
      app.dismissBanner();
      app.checkReminders(now: near);
      expect(app.bannerReminder, isNull);
    });

    test('a backup carries them, and restoring puts them back and schedules them', () async {
      final (app, _, _) = await boot();
      await app.addReminder(ch, soon(30));
      final data = jsonDecode(jsonEncode(app.exportData())) as Map<String, dynamic>;
      final (fresh, _, n) = await boot();
      expect(fresh.reminders, isEmpty);
      fresh.importData(data);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fresh.reminders.single.title, 'Arsenal v Chelsea');
      expect(n.scheduled, isNotEmpty);
    });

    test('profiles each have their own reminders', () async {
      final (app, st, _) = await boot();
      await app.addReminder(ch, soon(30));
      expect(app.reminders.length, 1);
      // another storage key (another profile) starts empty
      SharedPreferences.setMockInitialValues({});
      final other = AppState()..bindSettings(st);
      await other.init();
      expect(other.reminders, isEmpty);
    });
  });

  group('the screens', () {
    Future<(AppState, FakeNotifier)> pump(WidgetTester t, Widget page) async {
      final (app, st, n) = await boot();
      t.view.physicalSize = const Size(1000, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(theme: Boss.theme(tv: false, layout: st.layout), home: Scaffold(body: Stack(children: [page, const ReminderHost()]))),
      ));
      await t.pump();
      return (app, n);
    }

    final ch = chan('1', 'Sportsline');

    testWidgets('the programme sheet offers Remind me and sets it', (t) async {
      final p = Programme('Arsenal v Chelsea', DateTime.now().add(const Duration(minutes: 40)), DateTime.now().add(const Duration(minutes: 130)));
      final (app, n) = await pump(t, Builder(builder: (c) => TextButton(onPressed: () => showProgrammeSheet(c, ch, p), child: const Text('open'))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Remind me'), findsOneWidget);
      await t.tap(find.text('Remind me'));
      await t.pumpAndSettle();
      expect(app.reminders.length, 1);
      expect(n.scheduled.length, 1);
      expect(find.textContaining('Reminder set'), findsOneWidget);
      // and again: now it offers to remove it
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Remove the reminder'), findsOneWidget);
    });

    testWidgets('a programme already on has no reminder button', (t) async {
      final p = Programme('Now', DateTime.now().subtract(const Duration(minutes: 10)), DateTime.now().add(const Duration(minutes: 50)));
      await pump(t, Builder(builder: (c) => TextButton(onPressed: () => showProgrammeSheet(c, ch, p), child: const Text('open'))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Remind me'), findsNothing);
    });

    testWidgets('the banner shows a due reminder, with Watch and Dismiss', (t) async {
      final (app, _) = await pump(t, const SizedBox());
      app.reminders.add(rem(ch.key, 3, title: 'Late Show'));
      app.checkReminders();
      await t.pump();
      expect(find.text('Late Show'), findsOneWidget);
      expect(find.text('Watch'), findsOneWidget);
      expect(find.textContaining('Sportsline'), findsOneWidget);
      await t.tap(find.byTooltip('Dismiss'));
      await t.pump();
      expect(find.text('Late Show'), findsNothing);
      expect(app.bannerReminder, isNull);
    });

    testWidgets('Settings lists reminders and deletes one', (t) async {
      final (app, n) = await pump(t, const RemindersPage());
      await app.addReminder(ch, Programme('Arsenal v Chelsea', DateTime.now().add(const Duration(minutes: 40)), DateTime.now().add(const Duration(minutes: 130))));
      await t.pump();
      expect(find.text('Arsenal v Chelsea'), findsOneWidget);
      expect(find.textContaining('Notifications are on'), findsOneWidget);
      await t.tap(find.byTooltip('Remove'));
      await t.pump();
      expect(app.reminders, isEmpty);
      expect(n.cancelled, isNotEmpty);
      expect(find.textContaining('Open a programme in the guide'), findsOneWidget);
    });

    testWidgets('changing how long before reschedules', (t) async {
      final (app, n) = await pump(t, const RemindersPage());
      await app.addReminder(ch, Programme('x', DateTime.now().add(const Duration(minutes: 90)), DateTime.now().add(const Duration(minutes: 150))));
      await t.pump();
      await t.tap(find.text('5 min before'));
      await t.pumpAndSettle();
      await t.tap(find.text('15 min before').last);
      await t.pumpAndSettle();
      expect(app.reminderLead, 15);
      expect(n.cancelAlls, greaterThan(0));
    });
  });
}
