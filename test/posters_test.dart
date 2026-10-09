import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/tmdb.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/media_tile.dart';
import 'package:streamboss/widgets/net_image.dart';

MediaItem film(String id, String name,
        {String? poster, MediaKind kind = MediaKind.movie}) =>
    MediaItem(
        id: id,
        name: name,
        kind: kind,
        poster: poster,
        streamUrl: 'http://x/$id');

void main() {
  group('TmdbService.posterFor', () {
    test(
        'finds the first result that has a poster, and asks with the year from the name',
        () async {
      Uri? asked;
      final c = MockClient((r) async {
        asked = r.url;
        return http.Response(
            jsonEncode({
              'results': [
                {'id': 1, 'poster_path': null},
                {'id': 2, 'poster_path': '/abc.jpg'},
              ]
            }),
            200);
      });
      final url = await TmdbService('KEY', client: c)
          .posterFor(film('1', 'Night Signal (2018) HD'));
      expect(url, 'https://image.tmdb.org/t/p/w342/abc.jpg');
      expect(asked!.path, '/3/search/movie');
      expect(asked!.queryParameters['query'], 'Night Signal');
      expect(asked!.queryParameters['primary_release_year'], '2018');
    });

    test('uses the tv search and year field for a series', () async {
      Uri? asked;
      final c = MockClient((r) async {
        asked = r.url;
        return http.Response(jsonEncode({'results': []}), 200);
      });
      await TmdbService('KEY', client: c)
          .posterFor(film('1', 'Harbor Lights 2020', kind: MediaKind.series));
      expect(asked!.path, '/3/search/tv');
      expect(asked!.queryParameters['first_air_date_year'], '2020');
    });

    test('says "none" with an empty answer and "could not ask" with null',
        () async {
      final none = MockClient(
          (r) async => http.Response(jsonEncode({'results': []}), 200));
      expect(
          await TmdbService('K', client: none).posterFor(film('1', 'Nothing')),
          '');
      final down = MockClient((r) async => http.Response('nope', 500));
      expect(await TmdbService('K', client: down).posterFor(film('1', 'X')),
          isNull);
      final broken =
          MockClient((r) async => throw http.ClientException('offline'));
      expect(await TmdbService('K', client: broken).posterFor(film('1', 'X')),
          isNull);
      expect(await TmdbService('', client: none).posterFor(film('1', 'X')),
          isNull);
      expect(
          await TmdbService('K', client: none)
              .posterFor(film('1', 'Chan', kind: MediaKind.live)),
          isNull);
    });
  });

  group('AppState.posterFor', () {
    Future<(AppState, SettingsState, List<Uri>)> setup(
        {String key = 'KEY',
        Map<String, Object> prefs = const {},
        int delayMs = 0}) async {
      SharedPreferences.setMockInitialValues({'tmdbKey': key, ...prefs});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      final asked = <Uri>[];
      app.useTmdbClientForTest(MockClient((r) async {
        asked.add(r.url);
        if (delayMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
        return http.Response(
            jsonEncode({
              'results': [
                {
                  'poster_path':
                      '/${r.url.queryParameters['query']!.replaceAll(' ', '_')}.jpg'
                }
              ]
            }),
            200);
      }));
      return (app, st, asked);
    }

    test('the provider\'s own poster is used and nothing is asked', () async {
      final (app, _, asked) = await setup();
      expect(await app.posterFor(film('1', 'A', poster: 'http://x/a.png')),
          'http://x/a.png');
      expect(asked, isEmpty);
    });

    test(
        'a missing poster is looked up once and remembered, also after a restart',
        () async {
      final (app, _, asked) = await setup();
      final it = film('1', 'Night Signal');
      expect(await app.posterFor(it),
          'https://image.tmdb.org/t/p/w342/Night_Signal.jpg');
      expect(await app.posterFor(it),
          'https://image.tmdb.org/t/p/w342/Night_Signal.jpg');
      expect(asked, hasLength(1));
      final saved =
          (await SharedPreferences.getInstance()).getString('posterCache');
      expect(saved, contains('movie:1'));

      SharedPreferences.setMockInitialValues(
          {'tmdbKey': 'KEY', 'posterCache': saved!});
      final st = SettingsState();
      await st.init();
      final again = AppState()..bindSettings(st);
      await again.init();
      final asked2 = <Uri>[];
      again.useTmdbClientForTest(MockClient((r) async {
        asked2.add(r.url);
        return http.Response('{}', 200);
      }));
      expect(await again.posterFor(it),
          'https://image.tmdb.org/t/p/w342/Night_Signal.jpg');
      expect(asked2, isEmpty);
    });

    test(
        'nothing is asked without the key, with the setting off, or for a channel',
        () async {
      var (app, st, asked) = await setup(key: '');
      expect(await app.posterFor(film('1', 'A')), isNull);
      (app, st, asked) = await setup();
      st.set('realPosters', false);
      expect(await app.posterFor(film('1', 'A')), isNull);
      st.set('realPosters', true);
      expect(
          await app.posterFor(film('2', 'Chan', kind: MediaKind.live)), isNull);
      expect(asked, isEmpty);
    });

    test('asks for no more than three at a time', () async {
      var live = 0, peak = 0;
      SharedPreferences.setMockInitialValues({'tmdbKey': 'KEY'});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      app.useTmdbClientForTest(MockClient((r) async {
        live++;
        if (live > peak) peak = live;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        live--;
        return http.Response(
            jsonEncode({
              'results': [
                {'poster_path': '/p.jpg'}
              ]
            }),
            200);
      }));
      final r = await Future.wait(
          [for (var i = 0; i < 10; i++) app.posterFor(film('$i', 'Title $i'))]);
      expect(r.every((e) => e != null), isTrue);
      expect(peak, lessThanOrEqualTo(3));
      expect(peak, greaterThan(1));
    });

    test('a title TMDB does not know is remembered as having none', () async {
      SharedPreferences.setMockInitialValues({'tmdbKey': 'KEY'});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      var n = 0;
      app.useTmdbClientForTest(MockClient((r) async {
        n++;
        return http.Response(jsonEncode({'results': []}), 200);
      }));
      expect(await app.posterFor(film('1', 'Obscure')), isNull);
      expect(await app.posterFor(film('1', 'Obscure')), isNull);
      expect(n, 1);
    });
  });

  group('MediaTile', () {
    Future<void> pumpTile(
        WidgetTester t, AppState app, SettingsState st, MediaItem item) async {
      t.view.physicalSize = const Size(400, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(
          theme: Boss.theme(),
          home: Scaffold(
              body: SizedBox(
                  width: 160,
                  height: 240,
                  child: MediaTile(item: item, onTap: () {}))),
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    testWidgets('shows the TMDB poster when the item has none', (t) async {
      SharedPreferences.setMockInitialValues({'tmdbKey': 'KEY'});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      app.useTmdbClientForTest(MockClient((r) async => http.Response(
          jsonEncode({
            'results': [
              {'poster_path': '/z.jpg'}
            ]
          }),
          200)));
      await pumpTile(t, app, st, film('1', 'Night Signal'));
      final art = t.widgetList<NetImage>(find.byType(NetImage)).toList();
      expect(art.map((e) => e.url), ['https://image.tmdb.org/t/p/w342/z.jpg']);
    });

    testWidgets('shows the icon when there is no key', (t) async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      await pumpTile(t, app, st, film('1', 'Night Signal'));
      expect(find.byType(NetImage), findsNothing);
      expect(find.byIcon(Icons.movie), findsOneWidget);
    });
  });
}
