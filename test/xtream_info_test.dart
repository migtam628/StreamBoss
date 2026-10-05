import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/tmdb.dart';
import 'package:streamboss/services/xtream_client.dart';

void main() {
  test('vodInfo parses a typical get_vod_info response', () async {
    final client = MockClient((req) async {
      expect(req.url.queryParameters['action'], 'get_vod_info');
      expect(req.url.queryParameters['vod_id'], '5');
      return http.Response(
        jsonEncode({
          'info': {
            'movie_image': 'http://x/poster.jpg',
            'backdrop_path': ['http://x/back.jpg'],
            'plot': 'A plot.',
            'cast': 'Ann, Bob , ,Cy',
            'releasedate': '2019-03-04',
            'duration_secs': 5400,
            'rating': '7.4',
            'youtube_trailer': 'https://www.youtube.com/watch?v=abc123',
          },
        }),
        200,
      );
    });
    final i = (await XtreamClient('http://h', 'u', 'p', client: client).vodInfo('5'))!;
    expect(i.overview, 'A plot.');
    expect(i.poster, 'http://x/poster.jpg');
    expect(i.backdrop, 'http://x/back.jpg');
    expect(i.cast, ['Ann', 'Bob', 'Cy']);
    expect(i.year, '2019');
    expect(i.runtimeMin, 90);
    expect(i.rating, 7.4);
    expect(i.trailerKey, 'abc123');
  });

  test('parseInfo copes with odd shapes and returns null when empty', () {
    expect(XtreamClient.parseInfo({'info': []}), isNull);
    expect(XtreamClient.parseInfo({'info': {'plot': '', 'rating': 0, 'backdrop_path': ''}}), isNull);
    expect(XtreamClient.parseInfo(null), isNull);
    final i = XtreamClient.parseInfo({'info': {'backdrop_path': 'http://x/b.jpg', 'rating': 8, 'youtube_trailer': 'xyz'}})!;
    expect(i.backdrop, 'http://x/b.jpg');
    expect(i.rating, 8.0);
    expect(i.trailerKey, 'xyz');
  });

  test('loadCatalog tolerates numeric ids, null icons and numeric ratings', () async {
    final data = <String, dynamic>{
      'get_live_categories': [{'category_id': 1, 'category_name': 'News'}],
      'get_live_streams': [{'stream_id': 101, 'name': 'One', 'stream_icon': null, 'category_id': 1, 'epg_channel_id': null}],
      'get_vod_categories': [{'category_id': '10', 'category_name': 'Action'}],
      'get_vod_streams': [{'stream_id': 500, 'name': 'M', 'stream_icon': '', 'rating': 7.5, 'category_id': 10, 'container_extension': 'mkv'}],
      'get_series_categories': [],
      'get_series': [{'series_id': 9, 'name': 'S', 'cover': null, 'category_id': '3', 'rating': '8'}],
    };
    final client = MockClient((req) async => http.Response(jsonEncode(data[req.url.queryParameters['action']] ?? []), 200));
    final c = await XtreamClient('http://h', 'u', 'p', client: client).loadCatalog();
    expect(c.live.single.streamUrl, 'http://h/live/u/p/101.m3u8');
    expect(c.movies.single.streamUrl, 'http://h/movie/u/p/500.mkv');
    expect(c.movies.single.rating, '7.5');
    expect(c.movies.single.categoryId, '10');
    expect(c.series.single.kind, MediaKind.series);
  });

  test('mergeInfo: first source wins, second fills gaps', () {
    const a = TmdbInfo(overview: 'tmdb plot', rating: 8.1);
    const b = TmdbInfo(overview: 'provider plot', poster: 'p.jpg', cast: ['X'], year: '2020');
    final m = mergeInfo(a, b)!;
    expect(m.overview, 'tmdb plot');
    expect(m.rating, 8.1);
    expect(m.poster, 'p.jpg');
    expect(m.cast, ['X']);
    expect(m.year, '2020');
    expect(mergeInfo(null, b), same(b));
    expect(mergeInfo(a, null), same(a));
  });
}
