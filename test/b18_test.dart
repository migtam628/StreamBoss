import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/easy_view.dart';
import 'package:streamboss/layouts/madlib_view.dart';
import 'package:streamboss/layouts/matchday_view.dart';
import 'package:streamboss/layouts/shell_nav.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/layouts/wall_view.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/anime_screen.dart';
import 'package:streamboss/screens/browse_screen.dart';
import 'package:streamboss/services/anime.dart';
import 'package:streamboss/services/madlib.dart';
import 'package:streamboss/services/matchday.dart';
import 'package:streamboss/services/vod_filter.dart';
import 'package:streamboss/services/xmltv.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/tv.dart';

MediaItem movie(String id, String name, {String? rating, String cat = 'm1', String? plot}) => MediaItem(
    id: id, name: name, kind: MediaKind.movie, streamUrl: 'http://x/$id', categoryId: cat, rating: rating, plot: plot);
MediaItem show(String id, String name, {String? rating, String cat = 's1'}) =>
    MediaItem(id: id, name: name, kind: MediaKind.series, categoryId: cat, rating: rating);
MediaItem live(String id, String name, {String cat = 'l1', String? epg}) =>
    MediaItem(id: id, name: name, kind: MediaKind.live, streamUrl: 'http://x/$id', categoryId: cat, epgId: epg);

void main() {
  final titles = [
    movie('1', 'Harbor Lights (2021)', rating: '7.8'),
    movie('2', 'Night Shift 2015', rating: '6.1'),
    movie('3', 'The Long Way (2003)', rating: '8.4'),
    movie('4', 'Untitled'),
    movie('5', 'Zed (1987)', rating: '55'),
  ];
  List<MediaItem> filt(VodFilter f, {Set<String> fav = const {}, Set<String> started = const {}}) => applyVodFilter(
        titles,
        f,
        categoryName: (_) => 'Action',
        isFavorite: (i) => fav.contains(i.key),
        started: (i) => started.contains(i.key),
      );
  List<String> ids(List<MediaItem> l) => [for (final i in l) i.id];

  group('VodFilter', () {
    test('no filter returns the list itself', () {
      expect(identical(filt(VodFilter.none), titles), isTrue);
      expect(VodFilter.none.active, isFalse);
    });

    test('the year is read from the title, the last one wins', () {
      expect(yearOf(titles[0]), 2021);
      expect(yearOf(titles[1]), 2015);
      expect(yearOf(titles[3]), isNull);
      expect(yearOf(movie('9', '2012 (2009)')), 2009);
      expect(yearOf(movie('9', 'Room 1408 Edit')), isNull);
    });

    test('ratings out of 100 are read as out of 10', () {
      expect(ratingOf(titles[4]), 5.5);
      expect(ratingOf(titles[3]), 0);
    });

    test('words, rating and era narrow the list, and filters combine', () {
      expect(ids(filt(const VodFilter(text: 'night'))), ['2']);
      expect(ids(filt(const VodFilter(text: 'action'))), ['1', '2', '3', '4', '5']);
      expect(ids(filt(const VodFilter(minRating: 7))), ['1', '3']);
      expect(ids(filt(const VodFilter(era: Era.y2020))), ['1']);
      expect(ids(filt(const VodFilter(era: Era.y2010))), ['2']);
      expect(ids(filt(const VodFilter(era: Era.older))), ['5']);
      expect(ids(filt(const VodFilter(minRating: 7, era: Era.y2000))), ['3']);
    });

    test('favorites and not-watched toggles', () {
      expect(ids(filt(const VodFilter(favoritesOnly: true), fav: {'movie:2'})), ['2']);
      expect(ids(filt(const VodFilter(unwatchedOnly: true), started: {'movie:1', 'movie:2'})), ['3', '4', '5']);
    });

    test('orders: A to Z, best rated, newest (no year last)', () {
      expect(ids(filt(const VodFilter(sort: VodSort.name))), ['1', '2', '3', '4', '5']);
      expect(ids(filt(const VodFilter(sort: VodSort.rating))), ['3', '1', '2', '5', '4']);
      expect(ids(filt(const VodFilter(sort: VodSort.newest))), ['1', '2', '3', '5', '4']);
    });

    test('count and active', () {
      const f = VodFilter(text: 'x', minRating: 6, favoritesOnly: true);
      expect(f.count, 3);
      expect(const VodFilter(sort: VodSort.name).active, isTrue);
      expect(const VodFilter(sort: VodSort.name).count, 0);
    });
  });

  group('Anime', () {
    final c = Catalog(
      liveCategories: const [Category('l1', 'Anime TV'), Category('l2', 'News')],
      movieCategories: const [Category('m1', 'Action'), Category('m2', 'Anime Movies')],
      seriesCategories: const [Category('s1', 'Drama'), Category('s2', 'Shonen'), Category('s3', 'Comedy')],
      live: [live('1', 'Toon One', cat: 'l1'), live('2', 'News 24', cat: 'l2')],
      movies: [movie('1', 'Action Man', cat: 'm1'), movie('2', 'Spirit Valley', cat: 'm2')],
      series: [show('1', 'Dramatic'), show('2', 'Sky Pirates', cat: 's2'), show('3', 'Office (Anime)', cat: 's3')],
    );

    test('categories are recognised by name', () {
      for (final n in ['Anime', 'Shonen Series', 'MANGA', 'Donghua', 'Isekai', 'Seinen', 'Crunchyroll']) {
        expect(isAnimeCategory(n), isTrue, reason: n);
      }
      for (final n in ['Animals', 'Drama', 'Cartoons', 'Animation']) {
        expect(isAnimeCategory(n), isFalse, reason: n);
      }
    });

    test('titles come from anime categories and from a (Anime) tag', () {
      expect(animeOf(c, MediaKind.series).items.map((e) => e.name), ['Sky Pirates', 'Office (Anime)']);
      expect(animeOf(c, MediaKind.series).categories.map((e) => e.name), ['Shonen']);
      expect(animeOf(c, MediaKind.movie).items.map((e) => e.name), ['Spirit Valley']);
      expect(animeOf(c, MediaKind.live).items.map((e) => e.name), ['Toon One']);
      expect(animeCounts(c), {MediaKind.live: 1, MediaKind.movie: 1, MediaKind.series: 2});
      expect(animeCounts(const Catalog()).values.every((n) => n == 0), isTrue);
    });
  });

  group('Madlib', () {
    final c = Catalog(
      movieCategories: const [Category('m1', 'Comedy'), Category('m2', 'Horror'), Category('m3', 'Drama')],
      movies: [
        movie('1', 'Laugh Track (2021)', rating: '7.2', cat: 'm1'),
        movie('2', 'Dark House (2010)', rating: '8.1', cat: 'm2'),
        movie('3', 'Tears (2022)', rating: '6.0', cat: 'm3', plot: 'A moving family story.'),
        movie('4', 'Giggles (2004)', rating: '5.0', cat: 'm1'),
      ],
      series: [show('9', 'Sitcom Days', rating: '9.0', cat: 's1')],
      live: [live('7', 'Comedy Central')],
    );
    String cat(MediaItem i) => switch (i.categoryId) { 'm1' => 'Comedy', 'm2' => 'Horror', 'm3' => 'Drama', _ => '' };
    List<String> names(MadSentence s) => [for (final i in madlibMatches(s, c, categoryName: cat)) i.name];

    test('the default sentence is every movie, best rated first', () {
      expect(names(const MadSentence()), ['Dark House (2010)', 'Laugh Track (2021)', 'Tears (2022)', 'Giggles (2004)']);
    });

    test('mood words match the category, the title or the plot', () {
      expect(names(const MadSentence(mood: MadMood.funny)), ['Laugh Track (2021)', 'Giggles (2004)']);
      expect(names(const MadSentence(mood: MadMood.scary)), ['Dark House (2010)']);
      expect(names(const MadSentence(mood: MadMood.moving)), ['Tears (2022)']);
    });

    test('rating and era blanks narrow it, and live channels have neither', () {
      expect(names(const MadSentence(rating: MadRating.good)), ['Dark House (2010)', 'Laugh Track (2021)']);
      expect(names(const MadSentence(rating: MadRating.great)), ['Dark House (2010)']);
      expect(names(const MadSentence(era: Era.y2000)), ['Giggles (2004)']);
      expect(names(const MadSentence(kind: MadKind.live)), ['Comedy Central']);
      expect(names(const MadSentence(kind: MadKind.live, rating: MadRating.good)), isEmpty);
      expect(names(const MadSentence(kind: MadKind.series, mood: MadMood.funny)), ['Sitcom Days']);
    });
  });

  group('Matchday', () {
    final now = DateTime(2026, 10, 10, 19, 0);
    final until = DateTime(2026, 10, 11, 4, 0);
    final chans = [
      live('1', 'Sports One HD', cat: 'sp', epg: 'a'),
      live('2', 'Sports One', cat: 'sp', epg: 'b'),
      live('3', 'Metro News', cat: 'n', epg: 'c'),
      live('4', 'Movies 4K', cat: 'mv', epg: 'd'),
    ];
    String cat(MediaItem i) => switch (i.categoryId) { 'sp' => 'Premier League Sports', 'n' => 'News', _ => 'Movies' };
    Programme p(String t, int h, int m, {int len = 120}) =>
        Programme(t, DateTime(2026, 10, 10, h, m), DateTime(2026, 10, 10, h, m).add(Duration(minutes: len)));
    final guide = {
      'a': [p('Arsenal v Chelsea', 18, 0), p('Highlights', 22, 0, len: 30)],
      'b': [p('Arsenal v Chelsea', 18, 5), p('Tennis: Davis Cup', 20, 0)],
      'c': [p('Madrid v Girona', 21, 0), p('Evening news', 19, 0)],
      'd': [p('Film Night', 19, 0), p('Lakers v Celtics NBA', 20, 0)],
    };
    List<MatchEvent> events({bool Function(MediaItem)? fav}) => buildMatchday(
          now: now,
          until: until,
          channels: chans,
          categoryName: cat,
          programmesFor: (c) => guide[c.epgId] ?? const [],
          isFavorite: fav,
        );

    test('the same match on two channels is one event, best channel first', () {
      final e = events();
      final m = e.firstWhere((e) => e.title == 'Arsenal v Chelsea');
      expect(m.channels.map((c) => c.name), ['Sports One HD', 'Sports One']);
      expect(m.sport, Sport.football);
      expect(m.isLive(now), isTrue);
      expect(e.first.title, 'Arsenal v Chelsea', reason: 'the match on now comes first');
    });

    test('a favorite channel beats a better picture', () {
      final m = events(fav: (c) => c.name == 'Sports One').firstWhere((e) => e.title == 'Arsenal v Chelsea');
      expect(m.channels.first.name, 'Sports One');
    });

    test('a "v" title that names a sport counts on any channel; news and films do not', () {
      final titlesOut = events().map((e) => e.title).toList();
      expect(titlesOut, isNot(contains('Madrid v Girona')), reason: 'a v title with no sport named is not enough on a news channel');
      expect(titlesOut, contains('Lakers v Celtics NBA'));
      expect(titlesOut, isNot(contains('Evening news')));
      expect(titlesOut, isNot(contains('Film Night')));
    });

    test('sports come out right, and finished programmes are left out', () {
      final e = events();
      expect(e.firstWhere((x) => x.title.startsWith('Lakers')).sport, Sport.basketball);
      expect(e.firstWhere((x) => x.title.startsWith('Tennis')).sport, Sport.tennis);
      expect(e.where((x) => x.end.isBefore(now)), isEmpty);
      final times = e.skip(1).map((x) => x.start).toList();
      expect([...times]..sort(), times, reason: 'the rest are in time order');
    });

    test('time labels', () {
      final e = events();
      expect(matchTimeLabel(e.first, now, use24h: true), 'NOW');
      final later = e.firstWhere((x) => x.title.startsWith('Tennis'));
      expect(matchTimeLabel(later, now, use24h: true), '20:00');
      expect(matchTimeLabel(later, now, use24h: false), '8:00');
    });
  });

  group('screens', () {
    Future<(SettingsState, AppState)> setup(Catalog c, [Map<String, Object> prefs = const {}]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      app.catalog = c;
      return (st, app);
    }

    Future<void> pump(WidgetTester t, SettingsState st, AppState app, Widget home, Size size) async {
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
          theme: Boss.theme(tv: tv, layout: st.layout),
          builder: (context, child) => TvCanvas(enabled: tv, width: st.tvWidth, child: TvScope(tv: tv, child: child!)),
          home: Scaffold(body: home),
        ),
      ));
      await t.pumpAndSettle();
    }

    final cat = Catalog(
      liveCategories: const [Category('l1', 'Premier League Sports')],
      movieCategories: const [Category('m1', 'Action'), Category('m2', 'Anime Movies')],
      seriesCategories: const [Category('s1', 'Shonen')],
      live: [live('1', 'Arena Sports', epg: 'a')],
      movies: [
        movie('1', 'Harbor Lights (2021)', rating: '7.8'),
        movie('2', 'Night Shift (2015)', rating: '6.1'),
        movie('3', 'Spirit Valley (2019)', rating: '8.0', cat: 'm2'),
      ],
      series: [show('1', 'Sky Pirates', cat: 's1')],
    );

    testWidgets('the Movies page has a filter box that narrows the list', (t) async {
      final (st, app) = await setup(cat);
      await pump(t, st, app, BrowseScreen(kind: MediaKind.movie, catalog: app.shown), const Size(900, 900));
      expect(find.text('Harbor Lights (2021)'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'night');
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.text('Harbor Lights (2021)'), findsNothing);
      expect(find.text('Night Shift (2015)'), findsOneWidget);
      // The Filters sheet: rating 7+ leaves nothing that also matches "night", and Clear all brings it back.
      await t.tap(find.byTooltip('Clear filters'));
      await t.pumpAndSettle();
      expect(find.text('Harbor Lights (2021)'), findsOneWidget);
      await t.tap(find.text('Filters'));
      await t.pumpAndSettle();
      await t.tap(find.text('7+'));
      await t.pumpAndSettle();
      expect(app.vodFilter('movie').minRating, 7);
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      expect(find.text('Night Shift (2015)'), findsNothing);
      expect(find.text('Harbor Lights (2021)'), findsOneWidget);
      expect(find.text('Filters · 1'), findsOneWidget);
    });

    testWidgets('Movies and Series keep separate filters', (t) async {
      final (st, app) = await setup(cat);
      app.setVodFilter('movie', const VodFilter(text: 'x'));
      expect(app.vodFilter('series'), VodFilter.none);
      app.setVodFilter('movie', VodFilter.none);
      expect(app.vodFilters, isEmpty);
    });

    testWidgets('the Anime page lists what is anime, by kind, with its own categories', (t) async {
      final (st, app) = await setup(cat);
      await pump(t, st, app, const AnimeScreen(), const Size(900, 900));
      expect(find.text('Sky Pirates'), findsOneWidget);
      expect(find.text('Harbor Lights (2021)'), findsNothing);
      await t.tap(find.textContaining('Movies'));
      await t.pumpAndSettle();
      expect(find.text('Spirit Valley (2019)'), findsOneWidget);
      expect(find.text('Night Shift (2015)'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('the Anime page says so when there is none', (t) async {
      final (st, app) = await setup(Catalog(movies: [movie('1', 'A')], movieCategories: const [Category('m1', 'Action')]));
      await pump(t, st, app, const AnimeScreen(), const Size(420, 800));
      expect(find.text('No anime found'), findsOneWidget);
    });

    testWidgets('Easy: three buttons, the greeting and settings; nothing scrolls on TV', (t) async {
      final (st, app) = await setup(cat, {'layout': 'easy', 'tvMode': 'on'});
      await pump(t, st, app, const EasyHome(), const Size(1920, 1080));
      expect(find.text('Watch TV'), findsOneWidget);
      expect(find.text('Movies and shows'), findsOneWidget);
      expect(find.text('Find'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Pick one. Press OK.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Easy: phone stacks the buttons without overflow', (t) async {
      final (st, app) = await setup(cat, {'layout': 'easy'});
      await pump(t, st, app, const EasyHome(), const Size(390, 800));
      expect(find.text('Watch TV'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Madlib: the sentence, a count, and a blank that changes it', (t) async {
      final (st, app) = await setup(cat, {'layout': 'madlib', 'tvMode': 'on'});
      await pump(t, st, app, const MadlibHome(), const Size(1920, 1080));
      expect(find.text('Tonight I feel like a'), findsOneWidget);
      expect(find.text('movie'), findsOneWidget);
      expect(find.text('3 titles match. Best first:'), findsOneWidget);
      await t.tap(find.text('any rating'));
      await t.pumpAndSettle();
      await t.tap(find.text('top rated'));
      await t.pumpAndSettle();
      expect(find.text('1 title matches. Best first:'), findsOneWidget);
      expect(find.text('Spirit Valley (2019)'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('Madlib: phone has no overflow', (t) async {
      final (st, app) = await setup(cat, {'layout': 'madlib'});
      await pump(t, st, app, const MadlibHome(), const Size(390, 800));
      expect(find.text('movie'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Wall: kinds, a poster wall and details of the first title', (t) async {
      final (st, app) = await setup(cat, {'layout': 'wall', 'tvMode': 'on'});
      await pump(t, st, app, const WallHome(), const Size(1920, 1080));
      expect(find.text('Movies'), findsOneWidget);
      expect(find.text('Series'), findsOneWidget);
      expect(find.text('Harbor Lights (2021)'), findsWidgets);
      await t.tap(find.text('Series'));
      await t.pumpAndSettle();
      expect(find.text('Sky Pirates'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('Wall: phone, the first tap selects and shows details', (t) async {
      final (st, app) = await setup(cat, {'layout': 'wall'});
      await pump(t, st, app, const WallHome(), const Size(390, 800));
      await t.tap(find.text('Night Shift (2015)').first);
      await t.pumpAndSettle();
      expect(find.text('Night Shift (2015)'), findsWidgets);
      expect(find.byTooltip('Add to My List'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Matchday without a guide falls back to the sports channels', (t) async {
      final (st, app) = await setup(cat, {'layout': 'matchday', 'tvMode': 'on'});
      await pump(t, st, app, const MatchdayHome(), const Size(1920, 1080));
      expect(find.text('MATCHDAY'), findsOneWidget);
      expect(find.text('Arena Sports'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  test('the roster', () {
    expect(UiLayout.values.length, 21);
    for (final gone in ['mood', 'orbit', 'library', 'coverflow']) {
      expect(UiLayout.values.any((l) => l.name == gone), isFalse, reason: gone);
      expect(UiLayout.fromKey(gone), UiLayout.marquee, reason: 'a stored $gone falls back to Marquee');
    }
    for (final n in ['madlib', 'matchday', 'easy', 'wall']) {
      expect(UiLayout.fromKey(n).name, n);
    }
    expect(kDests.last.label, 'Anime');
    expect(kDests.length, 8);
  });
}
