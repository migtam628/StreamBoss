import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/search_screen.dart';
import 'package:streamboss/services/search.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

MediaItem m(String id, String name,
        {String cat = 'm1',
        String? rating,
        MediaKind kind = MediaKind.movie}) =>
    MediaItem(
        id: id,
        name: name,
        kind: kind,
        categoryId: cat,
        rating: rating,
        streamUrl: 'http://x/$id');

final catalog = Catalog(
  liveCategories: const [Category('l1', 'Sports'), Category('l2', 'News')],
  movieCategories: const [Category('m1', 'Thriller'), Category('m2', 'Sci-Fi')],
  seriesCategories: const [Category('s1', 'Shows')],
  live: [
    m('1', 'Arena Sports 1', cat: 'l1', kind: MediaKind.live),
    m('2', 'Metro News 24', cat: 'l2', kind: MediaKind.live),
    m('3', 'Sports Extra HD', cat: 'l1', kind: MediaKind.live),
  ],
  movies: [
    m('10', 'The Night Signal (2018)', rating: '7.4'),
    m('11', 'Signal Lost', rating: '5.1'),
    m('12', 'Amélie', cat: 'm2', rating: '8.3'),
    m('13', 'Night of the Living Dead', cat: 'm2', rating: '7.9'),
    m('14', 'Nightcrawler', rating: '7.8'),
  ],
  series: [
    m('20', 'Signal Hunters', cat: 's1', kind: MediaKind.series, rating: '6.2')
  ],
);

void main() {
  late SearchIndex idx;
  setUp(() => idx = SearchIndex.of(catalog));
  List<String> names(Iterable<MediaItem> l) => [for (final i in l) i.name];

  group('normalizeSearch', () {
    test('lowercases, removes accents and punctuation', () {
      expect(normalizeSearch('Amélie (2001)'), 'amelie 2001');
      expect(normalizeSearch('  Sports+HD!! '), 'sports hd');
      expect(normalizeSearch('ÀÉÎÕÜ'), 'aeiou');
      expect(normalizeSearch(''), '');
    });
  });

  group('search', () {
    test('needs two characters', () {
      expect(idx.search(''), isEmpty);
      expect(idx.search('a'), isEmpty);
    });

    test('every word must be found, in any order', () {
      expect(names(idx.search('signal night')), ['The Night Signal (2018)']);
      expect(names(idx.search('hd sports')), ['Sports Extra HD']);
    });

    test('ranks exact, then starts-with, then the rest', () {
      final r = names(idx.search('signal'));
      expect(r.first, 'Signal Lost');
      expect(r, containsAll(['The Night Signal (2018)', 'Signal Hunters']));
    });

    test('matches the start of a word and a part of one', () {
      expect(names(idx.search('metr')), ['Metro News 24']);
      expect(names(idx.search('crawl')), ['Nightcrawler']);
    });

    test('forgives a typo in a longer word, accents and punctuation', () {
      expect(names(idx.search('nigth')),
          containsAll(['The Night Signal (2018)', 'Nightcrawler']));
      expect(names(idx.search('amelie')), ['Amélie']);
      expect(names(idx.search('Amélie!')), ['Amélie']);
      expect(idx.search('xyzzy'), isEmpty);
      // Short words are not guessed at.
      expect(idx.search('nws'), isEmpty);
    });

    test('a year in the name can be searched', () {
      expect(names(idx.search('2018')), ['The Night Signal (2018)']);
    });

    test('the category name finds items in it, but a title match ranks higher',
        () {
      final r = names(idx.search('sports'));
      expect(r.toSet(), {'Arena Sports 1', 'Sports Extra HD'});
      expect(names(idx.search('sci fi')).toSet(),
          {'Amélie', 'Night of the Living Dead'});
    });

    test('filters by kind, category and rating', () {
      expect(
          names(idx.search('signal',
              filters: const SearchFilters(kinds: {MediaKind.series}))),
          ['Signal Hunters']);
      expect(
          names(idx.search('night',
              filters: const SearchFilters(category: 'Sci-Fi'))),
          ['Night of the Living Dead']);
      expect(
          names(idx.search('night',
              filters: const SearchFilters(minRating: 7.5))),
          ['Night of the Living Dead', 'Nightcrawler']);
    });

    test('sorts A to Z and by rating', () {
      final az = names(idx.search('night',
          filters: const SearchFilters(sort: SearchSort.az)));
      expect(
          az,
          [...az]
            ..sort((a, b) => normalizeSearch(a).compareTo(normalizeSearch(b))));
      final top = idx.search('night',
          filters: const SearchFilters(sort: SearchSort.rating));
      expect(top.first.name, 'Night of the Living Dead');
    });

    test('favorites and recent items edge ahead of equal matches', () {
      final plain = names(idx.search('night'));
      final boosted = names(idx.search('night', favorites: {'movie:14'}));
      expect(boosted.indexOf('Nightcrawler'),
          lessThanOrEqualTo(plain.indexOf('Nightcrawler')));
    });

    test('respects the limit', () {
      expect(idx.search('sports', limit: 1), hasLength(1));
    });

    test('lists the categories of each kind', () {
      expect(idx.categoryNames[MediaKind.movie], ['Thriller', 'Sci-Fi']);
    });
  });

  group('the search screen', () {
    Future<AppState> pump(WidgetTester t) async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      app.catalog = catalog;
      app.active = const Source(name: 'S', type: SourceType.demo);
      t.view.physicalSize = const Size(900, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(
            theme: Boss.theme(), home: const Scaffold(body: SearchScreen())),
      ));
      await t.pumpAndSettle();
      return app;
    }

    testWidgets('groups results by kind with counts', (t) async {
      await pump(t);
      expect(find.textContaining('at least two letters'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'signal');
      await t.pumpAndSettle();
      expect(find.text('Movies  ·  2'), findsOneWidget);
      expect(find.text('Series  ·  1'), findsOneWidget);
      expect(find.textContaining('Channels  ·'), findsNothing);
    });

    testWidgets('the kind chips narrow it, the filters panel opens', (t) async {
      await pump(t);
      await t.enterText(find.byType(TextField), 'sports');
      await t.pumpAndSettle();
      expect(find.text('Channels  ·  2'), findsOneWidget);
      await t.tap(find.text('Movies').first);
      await t.pumpAndSettle();
      expect(find.textContaining('Nothing matched'), findsOneWidget);
      expect(find.textContaining('with these filters'), findsOneWidget);
      await t.tap(find.text('Filters'));
      await t.pumpAndSettle();
      expect(find.text('Best match'), findsOneWidget);
      expect(find.text('Any category'), findsOneWidget);
    });

    testWidgets('submitting remembers the search and it comes back as a chip',
        (t) async {
      final app = await pump(t);
      await t.enterText(find.byType(TextField), 'night');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(app.recentSearches, ['night']);
      await t.tap(find.byIcon(Icons.close).first);
      await t.pumpAndSettle();
      expect(find.text('Recent searches'), findsOneWidget);
      await t.tap(find.text('night'));
      await t.pumpAndSettle();
      expect(find.textContaining('Movies  ·'), findsOneWidget);
      app.clearSearches();
      expect(app.recentSearches, isEmpty);
    });
  });
}
