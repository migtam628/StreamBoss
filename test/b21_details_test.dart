import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/screens/detail_screen.dart';
import 'package:streamboss/screens/series_screen.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/details_logic.dart';
import 'package:streamboss/services/tmdb.dart';
import 'package:streamboss/services/xtream_client.dart';

MediaItem m(String id, String name, {String cat = '1', String? rating, MediaKind kind = MediaKind.movie}) =>
    MediaItem(id: id, name: name, kind: kind, categoryId: cat, rating: rating, streamUrl: 'http://x/$id');

void main() {
  pageTests();
  test('runtime reads like people say it', () {
    expect(formatRuntime(108), '1h 48m');
    expect(formatRuntime(52), '52m');
    expect(formatRuntime(120), '2h');
    expect(formatRuntime(0), '');
  });

  test('quality tags', () {
    expect(qualityTagOf('Harbor Lights 4K'), '4K');
    expect(qualityTagOf('Harbor Lights (2021) FHD'), '1080p');
    expect(qualityTagOf('Harbor Lights 720p'), '720p');
    expect(qualityTagOf('Harbor Lights'), isNull);
  });

  group('versions and similar', () {
    final lib = [
      m('1', 'EN - Harbor Lights (2021) 720p'),
      m('2', 'EN - Harbor Lights (2021) 4K', cat: '2'),
      m('3', 'Harbor Lights 2021 FHD', cat: '3'),
      m('4', 'Harbor Lights 1999'),
      m('5', 'Harbor Nights 2021'),
      m('6', 'Harbor Lights (2021)', kind: MediaKind.series),
    ];
    test('other copies of the same title, best quality first', () {
      final v = versionsOf(lib[0], lib);
      expect(v.map((e) => e.id), ['2', '3']);
    });
    test('a different year or another kind is not a copy', () {
      expect(versionsOf(lib[3], lib), isEmpty);
      expect(versionsOf(lib[5], lib), isEmpty);
    });
    test('similar: same category, best rated first, never itself', () {
      final cat = [
        m('a', 'A', rating: '5'),
        m('b', 'B', rating: '8'),
        m('c', 'C', rating: '7'),
        m('d', 'D', cat: '9', rating: '9'),
      ];
      expect(similarTo(cat[0], cat).map((e) => e.id), ['b', 'c']);
      expect(similarTo(cat[0], cat, limit: 1).map((e) => e.id), ['b']);
    });
  });

  group('next up', () {
    test('the first episode when nothing is started', () {
      expect(nextUpIndex([false, false], [false, false]), 0);
    });
    test('partway through an episode continues it', () {
      expect(nextUpIndex([true, true, false, false], [false, false, true, false]), 2);
    });
    test('after a finished episode comes the next one', () {
      expect(nextUpIndex([true, true, false], [false, false, false]), 2);
    });
    test('everything watched has no next', () {
      expect(nextUpIndex([true, true], [false, false]), isNull);
      expect(nextUpIndex(const [], const []), isNull);
    });
  });

  test('a new episode is one from the last two weeks', () {
    final now = DateTime(2026, 10, 10);
    expect(isRecentEpisode('2026-10-03', now: now), isTrue);
    expect(isRecentEpisode('2026-09-01', now: now), isFalse);
    expect(isRecentEpisode('2026-11-01', now: now), isFalse);
    expect(isRecentEpisode(null, now: now), isFalse);
    expect(isRecentEpisode('soon', now: now), isFalse);
  });

  group('provider info', () {
    test('movie: genres, director, age, and what the file is', () {
      final t = XtreamClient.parseInfo({
        'info': {
          'plot': 'p',
          'genre': 'Drama, Romance',
          'director': 'Mara Voss',
          'country': 'Spain',
          'mpaa_rating': 'PG-13',
          'bitrate': 4500,
          'video': {'codec_name': 'hevc', 'width': 1920, 'height': 1080},
          'audio': {'codec_name': 'eac3', 'channels': 6, 'tags': {'language': 'eng'}},
        },
        'movie_data': {'container_extension': 'mkv'},
      })!;
      expect(t.genres, ['Drama', 'Romance']);
      expect(t.directors, ['Mara Voss']);
      expect(t.certification, 'PG-13');
      expect(t.tech!.resolution, '1080p');
      expect(t.tech!.channels, '5.1');
      expect(t.tech!.container, 'mkv');
      expect(t.tech!.bitrateKbps, 4500);
    });
    test('a bare plot still parses, with no tech', () {
      final t = XtreamClient.parseInfo({'info': {'plot': 'only a plot'}})!;
      expect(t.tech, isNull);
      expect(t.genres, isEmpty);
    });
    test('episode length from seconds or from a clock', () {
      expect(XtreamClient.episodeMinutes({'duration_secs': 2460}), 41);
      expect(XtreamClient.episodeMinutes({'duration': '00:41:10'}), 41);
      expect(XtreamClient.episodeMinutes({'duration': '41'}), 41);
      expect(XtreamClient.episodeMinutes({}), isNull);
    });
  });

  test('merging keeps the first source and fills the gaps', () {
    const a = TmdbInfo(genres: ['Drama'], certification: 'R');
    const b = TmdbInfo(genres: ['Other'], directors: ['X'], certification: 'PG', tech: TechInfo(container: 'mp4'));
    final r = mergeInfo(a, b)!;
    expect(r.genres, ['Drama']);
    expect(r.directors, ['X']);
    expect(r.certification, 'R');
    expect(r.tech!.container, 'mp4');
  });

  test('TMDB age rating prefers the US one', () {
    expect(
        certificationOf({
          'release_dates': {
            'results': [
              {'iso_3166_1': 'ES', 'release_dates': [{'certification': '12'}]},
              {'iso_3166_1': 'US', 'release_dates': [{'certification': ''}, {'certification': 'PG-13'}]},
            ]
          }
        }, 'movie'),
        'PG-13');
    expect(certificationOf({'content_ratings': {'results': [{'iso_3166_1': 'GB', 'rating': '15'}]}}, 'tv'), '15');
    expect(certificationOf({}, 'movie'), isNull);
  });
}

// ---- the pages ----------------------------------------------------------------------------

Future<AppState> _pump(WidgetTester t, Widget page, {Map<String, Object> prefs = const {}, Catalog? catalog}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final st = SettingsState();
  await st.init();
  final app = AppState()..bindSettings(st);
  app.catalog = catalog ??
      Catalog(
        movies: [m('1', 'Harbor Lights (2021)'), m('2', 'Harbor Lights (2021) 4K', cat: '2'), m('3', 'Other Movie')],
        movieCategories: const [Category('1', 'EN | Movies'), Category('2', 'EN | 4K Movies')],
        series: [m('s', 'The Long Quiet', kind: MediaKind.series)],
        seriesCategories: const [Category('1', 'Shows')],
      );
  t.view.physicalSize = const Size(1000, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<SettingsState>.value(value: st),
    ],
    child: MaterialApp(theme: Boss.theme(tv: false, layout: st.layout), home: page),
  ));
  await t.pump();
  await t.pump();
  return app;
}

const _info = TmdbInfo(
  overview: 'Two strangers share one last ferry ride.',
  year: '2021',
  runtimeMin: 108,
  rating: 7.8,
  certification: 'PG-13',
  genres: ['Drama', 'Romance'],
  directors: ['Mara Voss'],
  people: [Person('Ada Lin', 'Nora'), Person('Ben Ortiz', 'Sam')],
  tech: TechInfo(videoCodec: 'hevc', width: 1920, height: 1080, audioCodec: 'eac3', audioChannels: 6, container: 'mkv'),
);

void pageTests() {
  group('movie page', () {
    final item = m('1', 'Harbor Lights (2021)');

    testWidgets('title, facts and the play buttons', (t) async {
      await _pump(t, DetailScreen(item: item, loadInfo: () async => _info));
      expect(find.text('Harbor Lights (2021)'), findsOneWidget);
      for (final c in ['2021', '1h 48m', '★ 7.8', 'PG-13', '1080p', '5.1', 'English']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Play options'), findsOneWidget);
      expect(find.text('Mark watched'), findsOneWidget);
      expect(find.textContaining('Two strangers'), findsOneWidget);
    });

    testWidgets('tabs: cast, details with the file and the other copy', (t) async {
      await _pump(t, DetailScreen(item: item, loadInfo: () async => _info));
      await t.tap(find.text('Cast'));
      await t.pump();
      expect(find.text('Ada Lin'), findsOneWidget);
      expect(find.text('Nora'), findsOneWidget);
      await t.tap(find.text('Details'));
      await t.pump();
      expect(find.text('THE FILE'), findsOneWidget);
      expect(find.text('1080p · HEVC'), findsOneWidget);
      expect(find.text('MKV'), findsOneWidget);
      expect(find.text('OTHER COPIES IN YOUR LIBRARY'), findsOneWidget);
      expect(find.text('4K'), findsWidgets);
    });

    testWidgets('a started movie offers to resume, with how much is left', (t) async {
      final app = await _pump(t, DetailScreen(item: item, loadInfo: () async => _info), prefs: {'autoResume': true});
      app.positions[item.key] = const Duration(minutes: 42, seconds: 10).inMilliseconds;
      app.durations[item.key] = const Duration(minutes: 108).inMilliseconds;
      app.setWatched([], false); // notifies
      await t.pump();
      expect(find.text('Resume 42:10'), findsOneWidget);
      expect(find.text('Start over'), findsOneWidget);
      expect(find.textContaining('left'), findsOneWidget);
    });

    testWidgets('Mark watched flips and is remembered', (t) async {
      final app = await _pump(t, DetailScreen(item: item, loadInfo: () async => _info));
      await t.tap(find.text('Mark watched'));
      await t.pump();
      expect(app.isWatched(item), isTrue);
      expect(find.text('Mark not watched'), findsOneWidget);
      expect(find.text('Watch again'), findsOneWidget);
    });

    testWidgets('Play options lists the other copy and Settings defaults', (t) async {
      await _pump(t, DetailScreen(item: item, loadInfo: () async => _info));
      await t.ensureVisible(find.text('Play options'));
      await t.tap(find.text('Play options'));
      await t.pumpAndSettle();
      expect(find.text('COPY'), findsOneWidget);
      expect(find.text('AUDIO'), findsOneWidget);
      expect(find.text('SUBTITLES'), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('Spanish'), findsWidgets);
    });

    testWidgets('no provider details: still a page, with a hint', (t) async {
      await _pump(t, DetailScreen(item: item, loadInfo: () async => null));
      expect(find.text('No description from your provider yet.'), findsOneWidget);
      await t.tap(find.text('Cast'));
      await t.pump();
      expect(find.textContaining('No cast listed'), findsOneWidget);
    });
  });

  group('series page', () {
    final series = m('s', 'The Long Quiet', kind: MediaKind.series);
    Future<List<Episode>> eps() async => [
          const Episode('11', 1, 1, 'Pilot', 'http://x/11', minutes: 47, plot: 'It begins.'),
          const Episode('12', 1, 2, 'The Signal', 'http://x/12', minutes: 44),
          const Episode('21', 2, 1, 'Cold Open', 'http://x/21', minutes: 46),
          const Episode('22', 2, 2, 'Low Tide', 'http://x/22', minutes: 41, airDate: '2099-01-01'),
        ];
    MediaItem ep(String id) => MediaItem(id: 'ep$id', name: 'x', kind: MediaKind.movie, categoryId: '');

    testWidgets('Continue starts at the first episode, with season chips', (t) async {
      await _pump(t, SeriesScreen(series: series, loadEpisodes: eps, loadInfo: () async => _info));
      expect(find.text('Continue S1 · E1'), findsOneWidget);
      expect(find.text('2 seasons'), findsOneWidget);
      expect(find.text('4 episodes'), findsOneWidget);
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Pilot'), findsOneWidget);
      expect(find.textContaining('47 min'), findsWidgets);
    });

    testWidgets('Continue moves on after finished episodes, and the season follows', (t) async {
      final app = await _pump(t, SeriesScreen(series: series, loadEpisodes: eps, loadInfo: () async => _info));
      app.setWatched([ep('11'), ep('12')], true);
      await t.pump();
      expect(find.text('Continue S2 · E1'), findsOneWidget);
      expect(find.text('Cold Open'), findsOneWidget);
    });

    testWidgets('Mark season watched', (t) async {
      final app = await _pump(t, SeriesScreen(series: series, loadEpisodes: eps, loadInfo: () async => _info));
      await t.tap(find.text('Mark season watched'));
      await t.pump();
      expect(app.isWatched(ep('11')), isTrue);
      expect(app.isWatched(ep('12')), isTrue);
      expect(app.isWatched(ep('21')), isFalse);
      expect(find.text('Mark season not watched'), findsOneWidget);
      expect(find.text('Continue S2 · E1'), findsOneWidget);
      expect(find.text('Pilot'), findsOneWidget); // still looking at season 1
    });

    testWidgets('everything watched offers to start again', (t) async {
      final app = await _pump(t, SeriesScreen(series: series, loadEpisodes: eps, loadInfo: () async => _info));
      app.setWatched([ep('11'), ep('12'), ep('21'), ep('22')], true);
      await t.pump();
      expect(find.text('Watch again from the start'), findsOneWidget);
    });

    testWidgets('a half watched episode shows its progress', (t) async {
      final app = await _pump(t, SeriesScreen(series: series, loadEpisodes: eps, loadInfo: () async => _info));
      app.positions[ep('11').key] = const Duration(minutes: 20).inMilliseconds;
      app.durations[ep('11').key] = const Duration(minutes: 47).inMilliseconds;
      app.setWatched([], false);
      await t.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Continue S1 · E1'), findsOneWidget);
    });

    testWidgets('another season, and the Details tab totals', (t) async {
      await _pump(t, SeriesScreen(series: series, loadEpisodes: eps, loadInfo: () async => _info));
      await t.tap(find.text('Season 2'));
      await t.pump();
      expect(find.text('Low Tide'), findsOneWidget);
      expect(find.text('Pilot'), findsNothing);
      await t.tap(find.text('Details'));
      await t.pump();
      expect(find.text('2h 58m'), findsOneWidget);
    });

    testWidgets('a provider with no episodes says so', (t) async {
      await _pump(t, SeriesScreen(series: series, loadEpisodes: () async => [], loadInfo: () async => null));
      expect(find.text('No episodes listed by your provider.'), findsOneWidget);
    });
  });
}
