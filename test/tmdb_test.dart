import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/tmdb.dart';

void main() {
  test('cleanTitle strips provider noise', () {
    expect(cleanTitle('EN - The Matrix (1999) [4K] HEVC'), 'The Matrix');
    expect(cleanTitle('Dune 2021 1080p'), 'Dune');
  });
}
