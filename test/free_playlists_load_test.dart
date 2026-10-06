import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/free_playlists.dart';
import 'package:streamboss/state/app_state.dart';

// Kept apart from the widget tests: once a widget test binding exists, flutter_test answers every
// HTTP request with a fake 400, so real loopback requests only work in a file without widget tests.

const _a = '#EXTM3U x-tvg-url="http://guide/a.xml"\n'
    '#EXTINF:-1 tvg-id="n1" group-title="News",News One\nhttp://s/1.m3u8\n'
    '#EXTINF:-1 group-title="Sports",Sports One\nhttp://s/2.m3u8\n';
const _b = '#EXTM3U\n'
    '#EXTINF:-1 group-title="News",News One (dup)\nhttp://s/1.m3u8\n'
    '#EXTINF:-1 group-title="Kids",Kids One\nhttp://s/3.m3u8\n'
    '#EXTINF:-1 group-title="Movies",Some Film\nhttp://s/movie/u/p/9.mp4\n';

void main() {
  group('loading several playlists', () {
    late HttpServer server;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) {
        final path = r.uri.path;
        if (path == '/a.m3u') {
          r.response.write(_a);
        } else if (path == '/b.m3u') {
          r.response.write(_b);
        } else {
          r.response.statusCode = 404;
        }
        r.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    String u(String p) => 'http://127.0.0.1:${server.port}$p';

    test('merges them and skips a list that fails', () async {
      final c = await loadMergedPlaylists(
          [u('/a.m3u'), u('/missing.m3u'), u('/b.m3u')]);
      expect(c.live.length, 3);
    });

    test('throws only when none loads', () async {
      await expectLater(
          loadMergedPlaylists([u('/x.m3u'), u('/y.m3u')]),
          throwsA(predicate((e) =>
              e.toString().contains('None of the 2 playlists') &&
              e.toString().contains('Playlist returned 404'))));
    });

    test('a source with several addresses activates as one library', () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppState();
      await app.activate(Source(
          name: 'Free',
          type: SourceType.m3u,
          url: '${u('/a.m3u')}\n${u('/b.m3u')}\n'));
      expect(app.error, isNull);
      expect(app.catalog.live.length, 3);
      expect(app.catalog.movies.length, 1);
    });
  });

}
