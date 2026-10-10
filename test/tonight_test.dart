import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/shell_nav.dart';
import 'package:streamboss/layouts/tonight_view.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/tonight.dart';
import 'package:streamboss/services/xmltv.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/tv.dart';

MediaItem ch(String id, String name) => MediaItem(
    id: id,
    name: name,
    kind: MediaKind.live,
    streamUrl: 'http://x/$id',
    epgId: 'c$id');
MediaItem movie(String id, String name) => MediaItem(
    id: id, name: name, kind: MediaKind.movie, streamUrl: 'http://x/$id');

final now = DateTime(2026, 10, 9, 19, 42);
Programme prog(String t, int startMin, int len, {String? desc}) => Programme(
    t,
    now.add(Duration(minutes: startMin)),
    now.add(Duration(minutes: startMin + len)),
    desc: desc);

void main() {
  final news = ch('1', 'NewsOne'),
      sport = ch('2', 'Sports 2'),
      cine = ch('3', 'Cine Classics');
  final guide = <String, List<Programme>>{
    'c1': [
      prog('Harbor News at 7', -42, 78, desc: 'Headlines from the coast.'),
      prog('Weather Now', 36, 10),
      prog('Evening Edition', 46, 30),
      prog('Late News', 100, 30),
    ],
    'c2': [
      prog('Derby Night', 78, 120),
      prog('Derby Night', 400, 120), // same title again: only one line
      prog('Yesterday Highlights', -1200, 60),
    ],
    'c3': [
      prog('Casablanca', -30, 100),
      prog('Tomorrow Matinee', 24 * 60 + 60, 90),
    ],
  };
  List<Programme> programmesFor(MediaItem c) => guide[c.epgId] ?? const [];

  List<TonightEntry> build(
    TonightDay day, {
    List<MediaItem> favorites = const [],
    List<MediaItem> recents = const [],
    int max = 6,
    bool Function(MediaItem, Programme)? canCatchUp,
    Duration? Function(MediaItem)? resumeFor,
    List<MediaItem>? channels,
  }) =>
      buildTonight(
        now: now,
        day: day,
        channels: channels ?? [news, sport, cine],
        favorites: favorites,
        recents: recents,
        programmesFor: programmesFor,
        canCatchUp: canCatchUp,
        resumeFor: resumeFor,
        max: max,
      );

  group('buildTonight', () {
    test('Tonight lists what is on now and what starts later, in time order',
        () {
      final e = build(TonightDay.tonight);
      final times = [for (final x in e) x.programme!.start];
      expect(times, [...times]..sort());
      expect(e.first.kind, TonightKind.live);
      expect(
          e.any((x) =>
              x.title == 'Harbor News at 7' && x.kind == TonightKind.live),
          isTrue);
      expect(
          e.any((x) =>
              x.title == 'Derby Night' && x.kind == TonightKind.upcoming),
          isTrue);
    });

    test(
        'nothing from yesterday, tomorrow or the far future leaks into Tonight',
        () {
      final titles = build(TonightDay.tonight).map((e) => e.title);
      expect(titles, isNot(contains('Yesterday Highlights')));
      expect(titles, isNot(contains('Tomorrow Matinee')));
    });

    test('a title appears once even when it airs twice', () {
      final e = build(TonightDay.tonight);
      expect(e.where((x) => x.title == 'Derby Night').length, 1);
    });

    test('at most two lines per channel and never more than max', () {
      final e = build(TonightDay.tonight, favorites: [news]);
      expect(
          e.where((x) => x.item.key == news.key).length, lessThanOrEqualTo(2));
      expect(build(TonightDay.tonight, max: 2).length, 2);
    });

    test(
        'a favorite channel is chosen ahead of an unknown one when room is short',
        () {
      final e = build(TonightDay.tonight, favorites: [cine], max: 1);
      expect(e.single.item.key, cine.key);
      expect(e.single.reason, contains('favorites'));
    });

    test('Now shows only what is on now', () {
      final e = build(TonightDay.now);
      expect(e.every((x) => x.kind == TonightKind.live), isTrue);
      expect(e.map((x) => x.title).toSet(), {'Harbor News at 7', 'Casablanca'});
    });

    test('Tomorrow shows only tomorrow', () {
      final e = build(TonightDay.tomorrow);
      expect(e.map((x) => x.title), ['Tomorrow Matinee']);
    });

    test('Catch-up needs the provider to keep an archive for that channel', () {
      expect(build(TonightDay.catchUp), isEmpty);
      final e =
          build(TonightDay.catchUp, canCatchUp: (c, p) => c.key == sport.key);
      expect(e.map((x) => x.title), ['Yesterday Highlights']);
      expect(e.single.kind, TonightKind.archive);
    });

    test(
        'titles you are partway through and saved ones follow the timed lines on Tonight',
        () {
      final m1 = movie('10', 'Night Train'),
          m2 = movie('11', 'The Salt Cellar');
      final e = build(TonightDay.tonight,
          recents: [m1],
          favorites: [m2],
          resumeFor: (i) =>
              i.key == m1.key ? const Duration(minutes: 30) : null);
      final tail = e.reversed.take(2).toList().reversed.toList();
      expect(tail.map((x) => x.kind), [TonightKind.resume, TonightKind.saved]);
      expect(tail.first.when, isNull);
      expect(tonightTimeLabel(tail.first, (d) => 'x'), 'Any time');
      expect(tonightTimeLabel(e.first, (d) => 'x'), 'x');
    });

    test('Now adds only something you have actually started', () {
      final m1 = movie('10', 'Night Train'), m2 = movie('12', 'Never Started');
      final e = build(TonightDay.now,
          recents: [m2, m1],
          resumeFor: (i) =>
              i.key == m1.key ? const Duration(minutes: 5) : null);
      final resumes = e.where((x) => x.kind == TonightKind.resume).toList();
      expect(resumes.single.item.key, m1.key);
    });

    test('with no guide only the any-time titles remain, and tomorrow is empty',
        () {
      final m = movie('11', 'The Salt Cellar');
      final e = buildTonight(
          now: now,
          day: TonightDay.tonight,
          channels: [news],
          favorites: [m],
          recents: const [],
          programmesFor: (_) => const []);
      expect(e.single.kind, TonightKind.saved);
      expect(
          buildTonight(
              now: now,
              day: TonightDay.tomorrow,
              channels: [news],
              favorites: [m],
              recents: const [],
              programmesFor: (_) => const []),
          isEmpty);
    });

    test('channels the person has not touched still fill an empty list', () {
      final e = build(TonightDay.tonight);
      expect(e, isNotEmpty);
      expect(e.every((x) => x.reason.isNotEmpty), isTrue);
    });
  });

  group('Tonight screen', () {
    Future<(SettingsState, AppState)> setup() async {
      SharedPreferences.setMockInitialValues(
          {'layout': 'tonight', 'tvMode': 'on'});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      app.catalog = Catalog(
          live: [news, sport, cine], movies: [movie('10', 'Night Train')]);
      // Programmes relative to the real clock, since the screen reads it.
      final real = DateTime.now();
      Programme at(String t, int s, int l, {String? desc}) => Programme(
          t, real.add(Duration(minutes: s)), real.add(Duration(minutes: s + l)),
          desc: desc);
      app.guide = XmltvData({
        'c1': [
          at('Harbor News at 7', -20, 60, desc: 'Headlines from the coast.'),
          at('Weather Now', 41, 10)
        ],
        'c2': [at('Derby Night', 70, 120)],
        'c3': [at('Casablanca', -10, 100)],
      }, const {});
      app.toggleFavorite(news);
      return (st, app);
    }

    Future<void> pump(
        WidgetTester t, SettingsState st, AppState app, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final tv = st.isTv;
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(
          theme: Boss.theme(tv: tv, layout: UiLayout.tonight),
          builder: (context, child) => TvCanvas(
              enabled: tv,
              width: st.tvWidth,
              child: TvScope(tv: tv, child: child!)),
          home: const Scaffold(body: TonightHome()),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets(
        'TV: the heading, four day tabs, the timeline and a details panel',
        (t) async {
      final (st, app) = await setup();
      await pump(t, st, app, const Size(1920, 1080));
      expect(find.text('Tonight'), findsWidgets);
      for (final d in TonightDay.values) {
        expect(find.text(d.label), findsWidgets);
      }
      expect(find.text('Harbor News at 7'),
          findsWidgets); // the line and the panel
      expect(find.text('Derby Night'), findsOneWidget);
      expect(find.textContaining('Why it is here'), findsOneWidget);
      expect(find.text('Watch now'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('TV: moving down the list changes the details', (t) async {
      final (st, app) = await setup();
      await pump(t, st, app, const Size(1920, 1080));
      expect(find.text('Headlines from the coast.'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(find.text('Headlines from the coast.'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a day tab changes the list; an empty day says so', (t) async {
      final (st, app) = await setup();
      await pump(t, st, app, const Size(1920, 1080));
      await t.tap(find.text('Now').first);
      await t.pumpAndSettle();
      expect(find.text('Derby Night'), findsNothing,
          reason: 'it has not started');
      await t.tap(find.text('Catch-up').first);
      await t.pumpAndSettle();
      expect(find.textContaining('no TV guide'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'phone: the timeline fits without overflow and has no details panel',
        (t) async {
      SharedPreferences.setMockInitialValues({'layout': 'tonight'});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      app.catalog = Catalog(live: [news], movies: [movie('10', 'Night Train')]);
      app.toggleFavorite(movie('10', 'Night Train'));
      await pump(t, st, app, const Size(420, 900));
      expect(find.textContaining('Why it is here'), findsNothing);
      expect(find.text('MY LIST'), findsOneWidget);
      expect(find.text('Any time'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'the add button puts the highlighted title in My List and takes it out again',
        (t) async {
      final (st, app) = await setup();
      await pump(t, st, app, const Size(1920, 1080));
      app.toggleFavorite(news); // favorited in setup; start from not favorited
      await t.pumpAndSettle();
      expect(app.isFavorite(news), isFalse);
      await t.tap(find.byIcon(Icons.add));
      await t.pumpAndSettle();
      expect(app.isFavorite(news), isTrue);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });

  test('Tonight is a light layout with its own name in the nav', () {
    expect(LayoutPalette.forLayout(UiLayout.tonight).light, isTrue);
    expect(destLabel(UiLayout.tonight, 0), 'Tonight');
    expect(UiLayout.fromKey('tonight'), UiLayout.tonight);
  });
}
