import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/watch_screen.dart';
import 'package:streamboss/services/watch_logic.dart';
import 'package:streamboss/services/xtream_client.dart' show EpgEntry;
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

MediaItem channel(int n) => MediaItem(
    id: 'c$n',
    name: 'Channel $n',
    kind: MediaKind.live,
    categoryId: '1',
    streamUrl: 'http://x/c$n');

void main() {
  group('channel window', () {
    test('a short list is shown whole', () {
      expect(channelWindow(40, 30), (start: 0, end: 40));
      expect(channelWindow(0, 0), (start: 0, end: 0));
    });

    test('a long list shows 100 channels, starting a little before the one on',
        () {
      expect(channelWindow(5000, 2000), (start: 1992, end: 2092));
    });

    test('and stays inside the list at both ends', () {
      expect(channelWindow(5000, 3), (start: 0, end: 100));
      expect(channelWindow(5000, 4999), (start: 4900, end: 5000));
    });
  });

  group('now and next', () {
    final t0 = DateTime(2026, 10, 12, 20);
    EpgEntry e(String title, int fromMin, int toMin) => EpgEntry(title,
        t0.add(Duration(minutes: fromMin)), t0.add(Duration(minutes: toMin)));

    test('the programme on, the one after it, and how far through we are', () {
      final g = nowAndNext([
        e('Later', 90, 120),
        e('News', 0, 60),
        e('Film', 60, 90),
      ], t0.add(const Duration(minutes: 15)));
      expect(g.now?.title, 'News');
      expect(g.next?.title, 'Film');
      expect(g.progress, closeTo(0.25, 0.001));
    });

    test('between programmes there is only a next', () {
      final g =
          nowAndNext([e('Film', 30, 90)], t0.add(const Duration(minutes: 5)));
      expect(g.now, isNull);
      expect(g.next?.title, 'Film');
      expect(g.progress, 0);
    });

    test('no guide, nothing', () {
      final g = nowAndNext(const [], t0);
      expect((g.now, g.next, g.progress), (null, null, 0.0));
    });
  });

  group('the page for a live channel', () {
    final list = [for (var i = 1; i <= 5; i++) channel(i)];

    Future<AppState> pump(WidgetTester t, Widget page,
        {Size size = const Size(1280, 900)}) async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      app.catalog = Catalog(
        live: list,
        liveCategories: const [Category('1', 'News')],
      );
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(
            theme: Boss.theme(tv: false, layout: st.layout), home: page),
      ));
      await t.pump();
      await t.pump();
      return app;
    }

    Widget page() => WatchScreen(
          item: list[1],
          title: 'Channel 2',
          queue: list,
          stage: const Center(child: Text('VIDEO')),
        );

    testWidgets('the channel, its category, the actions and the channel list',
        (t) async {
      await pump(t, page());
      expect(find.text('VIDEO'), findsOneWidget);
      expect(find.text('Channel 2'), findsWidgets);
      expect(find.text('News'), findsWidgets);
      expect(find.text('My list'), findsOneWidget);
      expect(find.text('Full player'), findsOneWidget);
      expect(find.text('No guide for this channel.'), findsOneWidget);
      expect(find.text('Channels'), findsOneWidget);
      expect(find.text('Channel 1'), findsOneWidget);
      expect(find.text('Channel 5'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('choosing a channel from the list plays it in the same page',
        (t) async {
      final app = await pump(t, page());
      await t.tap(find.text('Channel 4'));
      await t.pump();
      await t.pump();
      expect(find.byType(WatchScreen), findsOneWidget);
      expect(find.text('Channel 4'), findsWidgets);
      expect(app.recents.first.key, list[3].key);
    });

    testWidgets('My list works for a channel', (t) async {
      final app = await pump(t, page());
      await t.tap(find.text('My list'));
      await t.pump();
      expect(app.isFavorite(list[1]), isTrue);
      expect(find.text('In My list'), findsOneWidget);
    });

    testWidgets('a phone held upright is one column and does not overflow',
        (t) async {
      await pump(t, page(), size: const Size(400, 800));
      expect(find.text('Channels'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
