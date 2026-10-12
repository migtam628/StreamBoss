import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/watch_screen.dart';
import 'package:streamboss/services/tmdb.dart';
import 'package:streamboss/services/watch_logic.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

MediaItem movie(String id, String name, {String cat = '1', String? rating}) =>
    MediaItem(
        id: id,
        name: name,
        kind: MediaKind.movie,
        categoryId: cat,
        rating: rating,
        streamUrl: 'http://x/$id');

WatchEpisode ep(int season, int number, String title, {int? minutes}) =>
    WatchEpisode(
      Episode(
          '$season$number', season, number, title, 'http://x/e$season$number',
          minutes: minutes),
      MediaItem(
          id: 'ep$season$number',
          name: 'The Long Quiet – $title',
          kind: MediaKind.movie,
          streamUrl: 'http://x/e$season$number'),
    );

const info = TmdbInfo(
  overview: 'Two strangers share one last ferry ride.',
  year: '2021',
  runtimeMin: 108,
  rating: 7.8,
  certification: 'PG-13',
  genres: ['Drama', 'Romance'],
  directors: ['Mara Voss'],
  people: [Person('Ada Lin', 'Nora'), Person('Ben Ortiz', 'Sam')],
);

void main() {
  group('when the watch page is used', () {
    final film = movie('1', 'Harbor Lights');
    const channel = MediaItem(
        id: 'c', name: 'News', kind: MediaKind.live, streamUrl: 'http://x/c');

    test(
        'on by default for a movie, an episode or a channel, off on a TV, never for catch-up',
        () {
      expect(useWatchPage(enabled: true, isTv: false, item: film), isTrue);
      expect(useWatchPage(enabled: true, isTv: true, item: film), isFalse);
      expect(useWatchPage(enabled: false, isTv: false, item: film), isFalse);
      expect(useWatchPage(enabled: true, isTv: false, item: channel), isTrue);
      expect(useWatchPage(enabled: true, isTv: true, item: channel), isFalse);
      expect(
          useWatchPage(enabled: true, isTv: false, item: film, catchUp: true),
          isFalse);
    });

    test('side by side from 900 wide', () {
      expect(isWatchWide(899), isFalse);
      expect(isWatchWide(900), isTrue);
    });

    test('the setting is on until it is turned off', () async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      expect(st.watchPage, isTrue);
      st.set('watchPage', false);
      expect(st.watchPage, isFalse);
    });
  });

  group('episodes', () {
    final eps = [ep(1, 1, 'Pilot'), ep(1, 2, 'Low Tide'), ep(2, 1, 'Return')];

    test('seasons in order, and the episodes of one', () {
      expect(watchSeasons(eps), [1, 2]);
      expect(
          inSeason(eps, 1).map((e) => e.episode.title), ['Pilot', 'Low Tide']);
      expect(inSeason(eps, 3), isEmpty);
    });

    test('the season of the episode playing', () {
      expect(seasonOfItem(eps, eps[2].item.key), 2);
      expect(seasonOfItem(eps, 'nope'), 1);
      expect(seasonOfItem(const [], 'nope'), 1);
    });

    test('the heading names the series, with the episode under it', () {
      final h = watchHeading(
          item: eps[1].item,
          series: movie('s', 'The Long Quiet'),
          episode: eps[1].episode);
      expect(h.title, 'The Long Quiet');
      expect(h.subtitle, 'S1 · E2 · Low Tide');
      final bare = watchHeading(item: movie('1', 'Harbor Lights'));
      expect((bare.title, bare.subtitle), ('Harbor Lights', null));
      final untitled = watchHeading(
          item: eps[0].item,
          series: movie('s', 'X'),
          episode: const Episode('1', 1, 4, ' ', 'u'));
      expect(untitled.subtitle, 'S1 · E4');
    });
  });

  group('the page', () {
    final library = Catalog(
      movies: [
        movie('1', 'Harbor Lights', rating: '7.8'),
        movie('2', 'Night Ferry', rating: '8.1'),
        movie('3', 'Paper Moon', rating: '6.0'),
        movie('4', 'Elsewhere', cat: '2'),
      ],
      movieCategories: const [
        Category('1', 'EN | Drama'),
        Category('2', 'EN | Action')
      ],
      series: [
        const MediaItem(
            id: 's',
            name: 'The Long Quiet',
            kind: MediaKind.series,
            categoryId: '1'),
        const MediaItem(
            id: 's2',
            name: 'Salt Road',
            kind: MediaKind.series,
            categoryId: '1'),
      ],
      seriesCategories: const [Category('1', 'Shows')],
    );

    Future<AppState> pump(WidgetTester t, Widget page,
        {Size size = const Size(1280, 900)}) async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      app.catalog = library;
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

    Widget moviePage() => WatchScreen(
          item: library.movies[0],
          title: 'Harbor Lights',
          loadInfo: () async => info,
          stage: const Center(child: Text('VIDEO')),
        );

    Widget episodePage() {
      final eps = [
        ep(1, 1, 'Pilot', minutes: 42),
        ep(1, 2, 'Low Tide'),
        ep(2, 1, 'Return')
      ];
      return WatchScreen(
        item: eps[0].item,
        title: eps[0].item.name,
        series: library.series[0],
        episodes: eps,
        loadInfo: () async => info,
        stage: const Center(child: Text('VIDEO')),
      );
    }

    testWidgets('a movie: the video, the facts, the actions and the card',
        (t) async {
      await pump(t, moviePage());
      expect(find.text('VIDEO'), findsOneWidget);
      expect(find.text('Harbor Lights'), findsWidgets);
      expect(find.text('2021  ·  1h 48m  ·  ★ 7.8  ·  PG-13'), findsOneWidget);
      expect(find.text('My list'), findsOneWidget);
      expect(find.text('Mark watched'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Two strangers share one last ferry ride.'),
          findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
      expect(find.textContaining('Mara Voss'), findsOneWidget);
      expect(find.textContaining('Ada Lin'), findsOneWidget);
    });

    testWidgets(
        'More like this lists the same category, best rated first, not the movie itself',
        (t) async {
      await pump(t, moviePage());
      expect(find.text('More like this'), findsOneWidget);
      expect(find.text('Night Ferry'), findsOneWidget);
      expect(find.text('Paper Moon'), findsOneWidget);
      expect(find.text('Elsewhere'), findsNothing);
      expect(t.getTopLeft(find.text('Night Ferry')).dy,
          lessThan(t.getTopLeft(find.text('Paper Moon')).dy));
    });

    testWidgets('choosing another movie plays it in the same page', (t) async {
      await pump(t, moviePage());
      await t.tap(find.text('Night Ferry'));
      await t.pump();
      await t.pump();
      // The heading (and the top bar) changed, and the one that was playing is now on the list.
      expect(find.text('Night Ferry'), findsNWidgets(2));
      expect(find.text('Harbor Lights'), findsOneWidget);
      expect(find.byType(WatchScreen), findsOneWidget);
    });

    testWidgets('My list and Mark watched change and show it', (t) async {
      final app = await pump(t, moviePage());
      await t.tap(find.text('My list'));
      await t.pump();
      expect(app.isFavorite(library.movies[0]), isTrue);
      expect(find.text('In My list'), findsOneWidget);
      await t.tap(find.text('Mark watched'));
      await t.pump();
      expect(app.isWatched(library.movies[0]), isTrue);
      expect(find.text('Mark not watched'), findsOneWidget);
    });

    testWidgets('a long plot is cut short and opens with Show more', (t) async {
      final long = 'A very long story. ' * 30;
      await pump(
          t,
          WatchScreen(
            item: library.movies[0],
            title: 'Harbor Lights',
            loadInfo: () async => TmdbInfo(overview: long),
            stage: const SizedBox(),
          ));
      expect(find.text('Show more'), findsOneWidget);
      await t.tap(find.text('Show more'));
      await t.pump();
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets(
        'an episode: the series, the episode, its season and the other episodes',
        (t) async {
      await pump(t, episodePage());
      expect(find.text('The Long Quiet'), findsWidgets);
      expect(find.text('S1 · E1 · Pilot'), findsOneWidget);
      expect(find.text('Episodes'), findsOneWidget);
      expect(find.text('1. Pilot'), findsOneWidget);
      expect(find.text('2. Low Tide'), findsOneWidget);
      expect(find.text('1. Return'), findsNothing); // season 2 is not shown
      expect(find.text('42 min'), findsOneWidget);
      expect(find.text('Salt Road'),
          findsOneWidget); // More like this: other series of the category
      expect(find.text('Season 1'), findsOneWidget);
    });

    testWidgets(
        'choosing an episode plays it, the season picker shows the others',
        (t) async {
      await pump(t, episodePage());
      await t.tap(find.text('2. Low Tide'));
      await t.pump();
      await t.pump();
      expect(find.text('S1 · E2 · Low Tide'), findsOneWidget);
      await t.tap(find.text('Season 1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Season 2').last);
      await t.pumpAndSettle();
      expect(find.text('1. Return'), findsOneWidget);
      expect(find.text('2. Low Tide'), findsNothing);
    });

    testWidgets(
        'on a phone held upright it is one column with the video on top',
        (t) async {
      await pump(t, episodePage(), size: const Size(400, 800));
      final video = t.getTopLeft(find.text('VIDEO')).dy;
      expect(t.getTopLeft(find.text('S1 · E1 · Pilot')).dy, greaterThan(video));
      expect(t.getTopLeft(find.text('1. Pilot')).dx, lessThan(400));
      expect(find.text('Episodes'), findsOneWidget);
      expect(t.takeException(), isNull); // nothing overflowed
    });

    testWidgets('wide: the list is beside the video, not under it', (t) async {
      await pump(t, moviePage());
      final video = t.getTopLeft(find.text('VIDEO'));
      final list = t.getTopLeft(find.text('More like this'));
      expect(list.dx, greaterThan(video.dx + 400));
    });

    testWidgets(
        'a phone on its side scrolls: video, then the details, then the list',
        (t) async {
      await pump(t, moviePage(), size: const Size(800, 400));
      expect(find.text('VIDEO'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
