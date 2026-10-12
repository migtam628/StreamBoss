import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/discover_screen.dart';
import 'package:streamboss/services/discover_logic.dart';
import 'package:streamboss/services/tmdb.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

MediaItem movie(String id, String name) => MediaItem(
    id: id, name: name, kind: MediaKind.movie, streamUrl: 'http://x/$id');

DiscoverTitle t(String title, {int? year, bool tv = false}) =>
    DiscoverTitle(id: 1, title: title, tv: tv, year: year);

void main() {
  group('matching the library', () {
    final m = LibraryMatcher([
      movie('1', 'EN | Dune: Part Two (2024) 4K'),
      movie('2', 'Amélie'),
      movie('3', 'Heat (1995)'),
      movie('4', 'Heat (2023)'),
    ], [
      const MediaItem(id: 's', name: 'The Bear', kind: MediaKind.series),
    ]);

    test(
        'tags, brackets, punctuation, accents and the year in the name are ignored',
        () {
      expect(m.find(t('Dune: Part Two', year: 2024))?.id, '1');
      expect(m.find(t('Amelie', year: 2001))?.id, '2');
    });

    test('the same name is told apart by year', () {
      expect(m.find(t('Heat', year: 1995))?.id, '3');
      expect(m.find(t('Heat', year: 2023))?.id, '4');
    });

    test('a year too far off is not the same title', () {
      expect(m.find(t('Dune: Part Two', year: 1984)), isNull);
    });

    test('movies and series are kept apart', () {
      expect(m.find(t('The Bear', tv: true))?.id, 's');
      expect(m.find(t('The Bear')), isNull);
      expect(m.find(t('Nothing here')), isNull);
    });
  });

  test('the list is read from TMDB: title, year, poster, rating', () async {
    final svc = TmdbService('k', client: MockClient((r) async {
      expect(r.url.path, '/3/trending/movie/week');
      return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 5,
                'title': 'Harbor Lights',
                'release_date': '2021-05-01',
                'poster_path': '/a.jpg',
                'vote_average': 7.84,
                'overview': 'A ferry.'
              },
              {'id': 6, 'title': '', 'release_date': ''},
              {
                'id': 7,
                'title': 'Bare',
                'poster_path': null,
                'vote_average': 0
              },
            ]
          }),
          200);
    }));
    final l = await svc.discoverList('trending/movie/week', tv: false);
    expect(l!.length, 2);
    expect(l[0].title, 'Harbor Lights');
    expect(l[0].year, 2021);
    expect(l[0].poster, 'https://image.tmdb.org/t/p/w342/a.jpg');
    expect(l[0].rating, closeTo(7.84, 0.001));
    expect(l[1].poster, isNull);
    expect(l[1].rating, isNull);
    expect(await TmdbService('').discoverList('x', tv: false), isNull);
  });

  group('the page', () {
    Future<AppState> pump(WidgetTester t, {String key = 'k'}) async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      if (key.isNotEmpty) st.set('tmdbKey', key);
      final app = AppState()..bindSettings(st);
      app.catalog = Catalog(movies: [movie('1', 'Harbor Lights (2021)')]);
      app.useTmdbClientForTest(MockClient((r) async {
        final tv = r.url.path.contains('/tv');
        return http.Response(
            jsonEncode({
              'results': tv
                  ? [
                      {
                        'id': 9,
                        'name': 'Salt Road',
                        'first_air_date': '2022-01-01'
                      }
                    ]
                  : [
                      {
                        'id': 5,
                        'title': 'Harbor Lights',
                        'release_date': '2021-05-01'
                      },
                      {
                        'id': 6,
                        'title': 'Far Away',
                        'release_date': '2020-01-01'
                      },
                    ]
            }),
            200);
      }));
      t.view.physicalSize = const Size(1000, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(
            theme: Boss.theme(tv: false, layout: st.layout),
            home: const DiscoverScreen()),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      return app;
    }

    testWidgets('rows of titles, the ones in the library marked', (t) async {
      await pump(t);
      expect(find.text('Trending movies'), findsOneWidget);
      expect(find.text('Harbor Lights'), findsWidgets);
      expect(find.text('In your library'), findsWidgets);
      expect(find.text('Far Away'), findsWidgets);
      expect(find.text('Salt Road'), findsWidgets);
    });

    testWidgets('Only what I have hides the rest', (t) async {
      await pump(t);
      await t.tap(find.text('Only what I have'));
      await t.pump();
      expect(find.text('Harbor Lights'), findsWidgets);
      expect(find.text('Far Away'), findsNothing);
      expect(find.text('Salt Road'), findsNothing);
    });

    testWidgets('a title the library lacks opens its description', (t) async {
      await pump(t);
      await t.tap(find.text('Far Away').first);
      await t.pumpAndSettle();
      expect(find.text('Not in your library'), findsOneWidget);
    });

    testWidgets('without a TMDB key it says what to do', (t) async {
      await pump(t, key: '');
      expect(find.textContaining('needs a TMDB key'), findsOneWidget);
    });
  });
}
