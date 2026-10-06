import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/free_playlists_screen.dart';
import 'package:streamboss/services/free_playlists.dart';
import 'package:streamboss/services/m3u_parser.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';

const _a = '#EXTM3U x-tvg-url="http://guide/a.xml"\n'
    '#EXTINF:-1 tvg-id="n1" group-title="News",News One\nhttp://s/1.m3u8\n'
    '#EXTINF:-1 group-title="Sports",Sports One\nhttp://s/2.m3u8\n';
const _b = '#EXTM3U\n'
    '#EXTINF:-1 group-title="News",News One (dup)\nhttp://s/1.m3u8\n'
    '#EXTINF:-1 group-title="Kids",Kids One\nhttp://s/3.m3u8\n'
    '#EXTINF:-1 group-title="Movies",Some Film\nhttp://s/movie/u/p/9.mp4\n';

class _FakeApp extends AppState {
  Source? added;
  @override
  Future<void> addSource(Source s) async => added = s;
}

void main() {
  group('catalog of public lists', () {
    test('categories, languages and collections point at the playlist files',
        () {
      expect(freeCategories.first.url,
          'https://iptv-org.github.io/iptv/categories/news.m3u');
      expect(
          freeLanguages.any((e) => e.url.endsWith('/languages/spa.m3u')), true);
      expect(freeCollections.where((e) => e.large).length, 1);
      final ids = [...freeCategories, ...freeLanguages, ...freeCollections]
          .map((e) => e.id)
          .toList();
      expect(ids.toSet().length, ids.length);
    });

    test(
        'countries come from countries.json, sorted, with the UK file named uk',
        () {
      final c = freeCountriesFrom([
        {'name': 'Zimbabwe', 'code': 'ZW'},
        {'name': 'United Kingdom', 'code': 'GB'},
        {'name': 'Albania', 'code': 'AL'},
        {'bad': 1},
      ]);
      expect(c.map((e) => e.name), ['Albania', 'United Kingdom', 'Zimbabwe']);
      expect(c[1].url, 'https://iptv-org.github.io/iptv/countries/uk.m3u');
      expect(c[0].url, 'https://iptv-org.github.io/iptv/countries/al.m3u');
      expect(freeCountriesFrom('nonsense'), isEmpty);
      expect(fallbackCountries, isNotEmpty);
    });

    test('source names say what was picked', () {
      expect(freeSourceName([freeCategories.first]), 'Free: News');
      expect(freeSourceName(freeCategories.take(3).toList()),
          'Free channels (3 lists)');
    });
  });

  group('merging playlists', () {
    test(
        'keeps a stream once, prefixes ids and keeps categories in first-seen order',
        () {
      final m = mergeCatalogs([parseM3u(_a), parseM3u(_b)]);
      expect(m.live.map((e) => e.name), ['News One', 'Sports One', 'Kids One']);
      expect(m.live.map((e) => e.id).toSet().length, 3);
      expect(m.liveCategories.map((e) => e.id), ['News', 'Sports', 'Kids']);
      expect(m.movies.map((e) => e.name), ['Some Film']);
      expect(m.movieCategories.map((e) => e.id), ['Movies']);
      expect(m.epgUrl, 'http://guide/a.xml');
    });
  });

  group('the screen', () {
    Future<_FakeApp> pump(WidgetTester t) async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final app = _FakeApp()..bindSettings(st);
      t.view.physicalSize = const Size(900, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(c).push(MaterialPageRoute(
                      builder: (_) => FreePlaylistsScreen(
                          loadCountries: () async => fallbackCountries))),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return app;
    }

    testWidgets('explains where the lists come from and starts empty',
        (t) async {
      await pump(t);
      expect(find.textContaining('third parties'), findsOneWidget);
      expect(find.text('Nothing selected'), findsOneWidget);
      expect(find.text('News'), findsWidgets);
    });

    testWidgets('one list becomes a single-address source', (t) async {
      final app = await pump(t);
      await t.tap(find.widgetWithText(CheckboxListTile, 'News').first);
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await t.pumpAndSettle();
      expect(app.added?.name, 'Free: News');
      expect(app.added?.url,
          'https://iptv-org.github.io/iptv/categories/news.m3u');
      expect(find.text('open'), findsOneWidget, reason: 'the screen closed');
    });

    testWidgets(
        'Select all picks everything shown and the sources are joined by newlines',
        (t) async {
      final app = await pump(t);
      await t.tap(find.textContaining('Select all'));
      await t.pumpAndSettle();
      expect(find.text('${freeCategories.length} selected'), findsOneWidget);
      await t.tap(find.widgetWithText(
          FilledButton, 'Add ${freeCategories.length} lists'));
      await t.pumpAndSettle();
      expect(find.text('This may take a while'), findsOneWidget);
      await t.tap(find.text('Add anyway'));
      await t.pumpAndSettle();
      expect(app.added?.url.split('\n').length, freeCategories.length);
      expect(app.added?.name, 'Free channels (${freeCategories.length} lists)');
    });

    testWidgets('the Countries tab lists countries and filters them',
        (t) async {
      await pump(t);
      await t.tap(find.text('Countries'));
      await t.pumpAndSettle();
      expect(find.text('Canada'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'spa');
      await t.pumpAndSettle();
      expect(find.text('Spain'), findsOneWidget);
      expect(find.text('Canada'), findsNothing);
    });
  });
}
