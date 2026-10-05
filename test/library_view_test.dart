import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/library_view.dart';

MediaItem m(String id, String name, String cat) =>
    MediaItem(id: id, name: name, kind: MediaKind.movie, streamUrl: 'u', categoryId: cat);

void main() {
  final c = Catalog(
    movieCategories: const [Category('1', 'Zombies'), Category('2', 'Adult | XXX'), Category('3', 'Action'), Category('4', '18+ Movies')],
    movies: [m('a', 'beta', '1'), m('b', 'hidden', '2'), m('c', 'Alpha', '3'), m('d', 'also hidden', '4')],
    epgUrl: 'http://guide',
  );

  test('no options returns the same catalog', () {
    expect(identical(buildView(c, hideAdult: false, sortAz: false), c), isTrue);
  });

  test('hideAdult removes adult categories and their items only', () {
    final v = buildView(c, hideAdult: true, sortAz: false);
    expect(v.movieCategories.map((e) => e.name), ['Zombies', 'Action']);
    expect(v.movies.map((e) => e.name), ['beta', 'Alpha']);
    expect(v.epgUrl, 'http://guide');
  });

  test('sortAz sorts categories and items case-insensitively', () {
    final v = buildView(c, hideAdult: false, sortAz: true);
    expect(v.movieCategories.first.name, '18+ Movies');
    expect(v.movies.map((e) => e.name).toList(), ['Alpha', 'also hidden', 'beta', 'hidden']);
  });

  test('adult detection avoids false positives', () {
    expect(isAdultCategory('Adult | XXX'), isTrue);
    expect(isAdultCategory('18+ Movies'), isTrue);
    expect(isAdultCategory('Adulthood (drama)'), isFalse);
    expect(isAdultCategory('Essex Daily'), isFalse);
    expect(isAdultCategory('Action'), isFalse);
  });
}
