import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/xmltv.dart';
import 'package:streamboss/services/xtream_client.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/programme_sheet.dart';

MediaItem ch({int days = 3, String id = '101'}) => MediaItem(
    id: id,
    name: 'News One',
    kind: MediaKind.live,
    streamUrl: 'http://h/live/u/p/$id.m3u8',
    archiveDays: days);

void main() {
  group('archive days from the provider', () {
    test('need the flag and say how many days', () {
      expect(archiveDaysOf('1', '3'), 3);
      expect(archiveDaysOf(1, 7), 7);
      expect(archiveDaysOf('1', null), 1);
      expect(archiveDaysOf('1', '0'), 1);
      expect(archiveDaysOf('0', '3'), 0);
      expect(archiveDaysOf('', ''), 0);
      expect(archiveDaysOf(null, null), 0);
    });

    test('are read from the live channel list and survive saving', () async {
      final client = MockClient((req) async {
        final a = req.url.queryParameters['action'];
        Object body = switch (a) {
          'get_live_streams' => [
              {
                'stream_id': 1,
                'name': 'A',
                'category_id': '1',
                'tv_archive': 1,
                'tv_archive_duration': '4'
              },
              {
                'stream_id': 2,
                'name': 'B',
                'category_id': '1',
                'tv_archive': 0,
                'tv_archive_duration': '0'
              },
              {'stream_id': 3, 'name': 'C', 'category_id': '1'},
            ],
          _ => [],
        };
        return http.Response(jsonEncode(body), 200);
      });
      final cat = await XtreamClient('http://h', 'u', 'p', client: client)
          .loadCatalog();
      expect(cat.live.map((e) => e.archiveDays), [4, 0, 0]);
      final back = MediaItem.fromJson(cat.live.first.toJson());
      expect(back.archiveDays, 4);
      expect(back.copyWith(epgId: 'x').archiveDays, 4);
      expect(cat.live[1].toJson().containsKey('arch'), isFalse);
    });
  });

  group('the provider clock', () {
    test('is read as a whole offset from UTC', () {
      final utc =
          DateTime.utc(2026, 10, 9, 20, 0, 0).millisecondsSinceEpoch ~/ 1000;
      expect(
          serverClockOffset(
              {'timestamp_now': utc, 'time_now': '2026-10-09 22:00:03'}),
          const Duration(hours: 2));
      expect(
          serverClockOffset(
              {'timestamp_now': '$utc', 'time_now': '2026-10-09 15:30:00'}),
          const Duration(hours: -4, minutes: -30));
      expect(
          serverClockOffset(
              {'timestamp_now': utc, 'time_now': '2026-10-09 20:00:00'}),
          Duration.zero);
    });

    test('is zero when the provider does not say or says nonsense', () {
      expect(serverClockOffset(null), Duration.zero);
      expect(serverClockOffset({'time_now': 'soon'}), Duration.zero);
      expect(
          serverClockOffset(
              {'timestamp_now': 1, 'time_now': '2026-10-09 20:00:00'}),
          Duration.zero);
    });
  });

  group('archive addresses', () {
    test('write the start in the provider clock', () {
      final c = XtreamClient('http://h:8080/', 'u', 'p')
        ..serverOffset = const Duration(hours: 2);
      expect(
          c.timeshiftUrl('101', DateTime.utc(2026, 10, 9, 18, 30),
              const Duration(minutes: 90)),
          'http://h:8080/timeshift/u/p/90/2026-10-09:20-30/101.ts');
      expect(
          c.timeshiftUrl('7', DateTime.utc(2026, 10, 9, 23, 5),
              const Duration(minutes: 30)),
          'http://h:8080/timeshift/u/p/30/2026-10-10:01-05/7.ts');
    });

    test('ask for at least a minute', () {
      final c = XtreamClient('http://h', 'u', 'p');
      expect(c.timeshiftUrl('1', DateTime.utc(2026, 1, 2, 3, 4), Duration.zero),
          'http://h/timeshift/u/p/1/2026-01-02:03-04/1.ts');
    });
  });

  group('in the app', () {
    late AppState app;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      app = AppState();
      await app.init();
    });
    final now = DateTime.utc(2026, 10, 9, 20);
    Programme p(Duration from, Duration to) =>
        Programme('Show', now.add(from), now.add(to));

    test('there is no catch-up without an Xtream source', () {
      expect(app.canCatchUp(ch()), isFalse);
      expect(app.catchUpUrl(ch(), p(const Duration(hours: -1), Duration.zero)),
          isNull);
    });

    test(
        'a programme can be caught up when it has started and is inside the days kept',
        () {
      app.useXtreamForTest(XtreamClient('http://h', 'u', 'p'));
      expect(app.canCatchUp(ch()), isTrue);
      expect(app.canCatchUp(ch(days: 0)), isFalse);
      expect(
          app.catchUpFor(
              ch(), p(const Duration(hours: -2), const Duration(hours: -1)),
              now: now),
          isTrue);
      expect(
          app.catchUpFor(ch(),
              p(const Duration(minutes: -20), const Duration(minutes: 40)),
              now: now),
          isTrue); // on now
      expect(
          app.catchUpFor(
              ch(), p(const Duration(hours: 1), const Duration(hours: 2)),
              now: now),
          isFalse); // not yet
      expect(
          app.catchUpFor(ch(),
              p(const Duration(days: -4), const Duration(days: -4, hours: 1)),
              now: now),
          isFalse); // too old
      expect(
          app.catchUpFor(ch(days: 0),
              p(const Duration(hours: -2), const Duration(hours: -1)),
              now: now),
          isFalse);
    });

    test('the address covers the whole programme', () {
      app.useXtreamForTest(XtreamClient('http://h', 'u', 'p'));
      final prog = Programme('Late News', DateTime.utc(2026, 10, 9, 18, 0),
          DateTime.utc(2026, 10, 9, 18, 45));
      expect(app.catchUpUrl(ch(), prog),
          'http://h/timeshift/u/p/45/2026-10-09:18-00/101.ts');
    });
  });

  group('programme details', () {
    test('the guide description is kept and cut short', () {
      final long = 'x' * 400;
      final d = parseXmltv(
          '<tv><programme start="20240101100000 +0000" stop="20240101110000 +0000" channel="a"><title>T</title><desc>Short one</desc></programme>'
          '<programme start="20240101110000 +0000" stop="20240101120000 +0000" channel="a"><title>U</title><desc>$long</desc></programme>'
          '<programme start="20240101120000 +0000" stop="20240101130000 +0000" channel="a"><title>V</title></programme></tv>',
          from: DateTime.utc(2024, 1, 1),
          to: DateTime.utc(2024, 1, 2));
      final l = d.programmes['a']!;
      expect(l[0].desc, 'Short one');
      expect(l[1].desc!.length, 300);
      expect(l[1].desc, endsWith('...'));
      expect(l[2].desc, isNull);
    });

    Future<AppState> open(WidgetTester t, MediaItem channel, Programme prog,
        {bool xtream = true}) async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      if (xtream) app.useXtreamForTest(XtreamClient('http://h', 'u', 'p'));
      t.view.physicalSize = const Size(900, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(
          theme: Boss.theme(),
          home: Builder(
            builder: (c) => Scaffold(
                body: TextButton(
                    onPressed: () => showProgrammeSheet(c, channel, prog),
                    child: const Text('open'))),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return app;
    }

    testWidgets('a past programme on an archive channel offers catch-up',
        (t) async {
      final start = DateTime.now().subtract(const Duration(hours: 5));
      await open(
          t,
          ch(),
          Programme('Late News', start, start.add(const Duration(hours: 1)),
              desc: 'The day in review.'));
      expect(find.text('Late News'), findsOneWidget);
      expect(find.text('The day in review.'), findsOneWidget);
      expect(find.text('Watch from the archive'), findsOneWidget);
      expect(find.text('Watch News One now'), findsNothing);
    });

    testWidgets('the programme on now offers the start and live', (t) async {
      final start = DateTime.now().subtract(const Duration(minutes: 20));
      await open(t, ch(),
          Programme('Breakfast', start, start.add(const Duration(hours: 1))));
      expect(find.text('Watch from the start'), findsOneWidget);
      expect(find.text('Watch live'), findsOneWidget);
      expect(find.textContaining('no description'), findsOneWidget);
    });

    testWidgets('a future programme only offers the channel', (t) async {
      final start = DateTime.now().add(const Duration(hours: 2));
      await open(
          t,
          ch(),
          Programme('Tonight', start, start.add(const Duration(hours: 1)),
              desc: 'Later on.'));
      expect(find.text('Later on.'), findsOneWidget);
      expect(find.text('Watch News One now'), findsOneWidget);
      expect(find.textContaining('archive'), findsNothing);
    });

    testWidgets('without catch-up a past programme explains why', (t) async {
      final start = DateTime.now().subtract(const Duration(hours: 5));
      await open(t, ch(days: 0),
          Programme('Old', start, start.add(const Duration(hours: 1))),
          xtream: false);
      expect(find.text('This channel has no catch-up'), findsOneWidget);
    });
  });
}
