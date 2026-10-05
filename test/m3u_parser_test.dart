import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/m3u_parser.dart';

void main() {
  test('parses live channels and groups', () {
    const body = '''#EXTM3U
#EXTINF:-1 tvg-logo="http://x/logo.png" group-title="News",Channel One
http://host/live/1.m3u8
#EXTINF:-1 group-title="Films",Some Movie
http://host/movie/u/p/9.mp4
''';
    final c = parseM3u(body);
    expect(c.live.length, 1);
    expect(c.live.first.name, 'Channel One');
    expect(c.live.first.poster, 'http://x/logo.png');
    expect(c.movies.single.kind, MediaKind.movie);
    expect(c.liveCategories.map((e) => e.id), ['News']);
    expect(c.movieCategories.map((e) => e.id), ['Films']);
  });

  test('titles containing commas are kept whole', () {
    final c = parseM3u('#EXTINF:-1 group-title="Films, HD",Some, Movie\nhttp://h/movie/u/p/9.mkv\n');
    expect(c.movies.single.name, 'Some, Movie');
    expect(c.movies.single.categoryId, 'Films, HD');
  });
}
