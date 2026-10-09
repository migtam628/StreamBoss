import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/recommend.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/profiles_state.dart';

MediaItem mv(String id, String name,
        {String cat = 'a', String? rating, MediaKind kind = MediaKind.movie}) =>
    MediaItem(
        id: id,
        name: name,
        kind: kind,
        categoryId: cat,
        rating: rating,
        streamUrl: 'http://x/$id');

void main() {
  final catalog = Catalog(
    movieCategories: const [
      Category('a', 'Thriller'),
      Category('b', 'Comedy'),
      Category('c', 'Drama')
    ],
    seriesCategories: const [Category('s', 'Shows')],
    movies: [
      mv('1', 'Night Signal', cat: 'a', rating: '7.0'),
      mv('2', 'Cold Case', cat: 'a', rating: '6.0'),
      mv('3', 'Funny Business', cat: 'b', rating: '9.0'),
      mv('4', 'Quiet Drama', cat: 'c', rating: '9.5'),
      mv('5', 'Signal Lost', cat: 'c', rating: '5.0'),
      mv('6', 'Another Thriller', cat: 'a', rating: '8.5'),
    ],
    series: [mv('20', 'Harbor Lights', cat: 's', kind: MediaKind.series)],
  );

  group('recommend', () {
    test('nothing to go on gives nothing', () {
      expect(
          recommend(
              catalog: catalog,
              recents: const [],
              favorites: const {},
              positions: const {}),
          isNull);
      expect(
          recommend(
              catalog: catalog,
              recents: [mv('9', 'Live', kind: MediaKind.live)],
              favorites: const {},
              positions: const {}),
          isNull);
    });

    test(
        'suggests a title with a shared word first, then the same category, and never what was watched',
        () {
      final r = recommend(
          catalog: catalog,
          recents: [catalog.movies[0]],
          favorites: const {},
          positions: const {})!;
      final ids = r.items.map((e) => e.id).toList();
      expect(ids, isNot(contains('1')));
      expect(ids.take(3), [
        '5',
        '6',
        '2'
      ]); // "Signal Lost" shares a word; then the other thrillers, better rated first
      expect(r.reason, 'Because you watched Night Signal');
    });

    test('a shared word counts, even in another category', () {
      final r = recommend(
          catalog: catalog,
          recents: [catalog.movies[0]],
          favorites: const {},
          positions: const {})!;
      expect(r.items.map((e) => e.id), contains('5')); // Signal Lost
      expect(r.items.map((e) => e.id),
          isNot(contains('3'))); // a comedy with nothing in common
    });

    test('favorites and half-watched titles count too', () {
      final r = recommend(
          catalog: catalog,
          recents: const [],
          favorites: {'movie:3'},
          positions: {'movie:2': 60000})!;
      expect(r.items.map((e) => e.id),
          containsAll(['1', '6'])); // thrillers like the half-watched one
      expect(r.items.map((e) => e.id), isNot(contains('3')));
      expect(r.items.map((e) => e.id), isNot(contains('2')));
    });

    test('respects the limit', () {
      final r = recommend(
          catalog: catalog,
          recents: [catalog.movies[0]],
          favorites: const {},
          positions: const {},
          limit: 1)!;
      expect(r.items, hasLength(1));
    });
  });

  group('collections', () {
    late AppState app;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      app = AppState();
      await app.init();
      app.catalog = catalog;
    });

    test('are made, filled, listed in the order added, and emptied', () {
      expect(app.createCollection('Friday'), isTrue);
      expect(app.createCollection('friday'), isFalse); // same name
      expect(app.createCollection('  '), isFalse);
      app.toggleInCollection('Friday', catalog.movies[2]);
      app.toggleInCollection('Friday', catalog.movies[0]);
      expect(app.collectionItems('Friday').map((e) => e.id), ['3', '1']);
      expect(app.inCollection('Friday', catalog.movies[0]), isTrue);
      app.toggleInCollection('Friday', catalog.movies[0]);
      expect(app.collectionItems('Friday').map((e) => e.id), ['3']);
    });

    test('can be renamed and deleted', () {
      app.createCollection('A');
      app.createCollection('B');
      app.toggleInCollection('A', catalog.movies[0]);
      expect(app.renameCollection('A', 'B'), isFalse);
      expect(app.renameCollection('A', 'Alpha'), isTrue);
      expect(app.collections.keys, ['B', 'Alpha']);
      expect(app.collectionItems('Alpha').single.id, '1');
      app.deleteCollection('B');
      expect(app.collections.keys, ['Alpha']);
    });

    test('an item missing from the library is just not shown', () {
      app.createCollection('Mix');
      app.toggleInCollection('Mix', catalog.movies[0]);
      app.catalog = const Catalog();
      expect(app.collectionItems('Mix'), isEmpty);
      expect(app.collections['Mix'], ['movie:1']); // still saved
    });

    test('are kept per profile and across a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final profiles = ProfilesState();
      await profiles.init();
      final a = AppState()..bindProfiles(profiles);
      await a.init();
      a.catalog = catalog;
      a.createCollection('Mine');
      a.toggleInCollection('Mine', catalog.movies[0]);
      final kid = profiles.add('Sam');
      profiles.select(kid.id);
      expect(a.collections, isEmpty);
      a.createCollection('Kids stuff');
      profiles.select('main');
      expect(a.collections.keys, ['Mine']);

      final again = AppState()..bindProfiles(profiles);
      await again.init();
      expect(again.collections['Mine'], ['movie:1']);
    });
  });
}
