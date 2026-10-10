import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/catalog_cache.dart';
import 'package:streamboss/services/m3u_parser.dart';
import 'package:streamboss/services/perf_log.dart';
import 'package:streamboss/services/xtream_client.dart';
import 'package:streamboss/state/app_state.dart';

// A tiny Xtream panel on the loopback interface, with a delay knob for the library answers.
class FakePanel {
  late final HttpServer server;
  Duration libraryDelay = Duration.zero;
  int libraryRequests = 0;
  bool failLibrary = false;
  String liveName = 'One';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final action = req.uri.queryParameters['action'] ?? '';
      Object body;
      switch (action) {
        case '':
          body = {'user_info': {'auth': 1, 'status': 'Active'}, 'server_info': {}};
        case 'get_live_categories':
          body = [{'category_id': '1', 'category_name': 'EN | News'}];
        case 'get_live_streams':
          libraryRequests++;
          body = [{'stream_id': 1, 'name': liveName, 'category_id': '1', 'tv_archive': 0}];
        case 'get_vod_categories':
          body = [{'category_id': '2', 'category_name': 'Movies'}];
        case 'get_vod_streams':
          body = [{'stream_id': 7, 'name': 'A Movie (2021)', 'category_id': '2', 'container_extension': 'mkv'}];
        case 'get_series_categories':
          body = [{'category_id': '3', 'category_name': 'Shows'}];
        case 'get_series':
          body = [{'series_id': 9, 'name': 'A Show', 'category_id': '3'}];
        default:
          body = [];
      }
      if (action.startsWith('get_') && libraryDelay > Duration.zero) await Future<void>.delayed(libraryDelay);
      if (failLibrary && action == 'get_live_streams') {
        req.response.statusCode = 503;
      } else {
        req.response.write(jsonEncode(body));
      }
      await req.response.close();
    });
  }

  String get url => 'http://127.0.0.1:${server.port}';
  Future<void> stop() => server.close(force: true);
}

Source panelSource(FakePanel p) => Source(name: 'T', type: SourceType.xtream, url: p.url, username: 'u', password: 'secret-pass');

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('sbcache');
    CatalogCache.directory = dir;
    PerfLog.start();
  });
  tearDown(() {
    CatalogCache.directory = null;
    dir.deleteSync(recursive: true);
  });

  group('CatalogCache', () {
    final blobs = [for (var i = 0; i < 6; i++) Uint8List.fromList(utf8.encode('blob $i ${'x' * (i * 100)}'))];
    const src = Source(name: 'S', type: SourceType.xtream, url: 'http://h', username: 'u', password: 'p');

    test('what is saved is read back, byte for byte', () async {
      await CatalogCache.save(src, 'x', blobs);
      final r = await CatalogCache.load(src);
      expect(r, isNotNull);
      expect(r!.kind, 'x');
      expect([for (final b in r.blobs) utf8.decode(b)], [for (final b in blobs) utf8.decode(b)]);
      expect(DateTime.now().difference(r.savedAt).inMinutes, lessThan(1));
    });

    test('the key follows the address and login but never the password', () {
      final a = CatalogCache.keyOf(src);
      expect(CatalogCache.keyOf(const Source(name: 'other name', type: SourceType.xtream, url: 'http://h', username: 'u', password: 'different')), a);
      expect(CatalogCache.keyOf(const Source(name: 'S', type: SourceType.xtream, url: 'http://h2', username: 'u', password: 'p')), isNot(a));
      expect(CatalogCache.keyOf(const Source(name: 'S', type: SourceType.xtream, url: 'http://h', username: 'v', password: 'p')), isNot(a));
    });

    test('nothing saved, or a damaged file, is simply no copy', () async {
      expect(await CatalogCache.load(src), isNull);
      await CatalogCache.save(src, 'x', blobs);
      final f = dir.listSync().whereType<File>().firstWhere((e) => e.path.endsWith('.lib'));
      f.writeAsBytesSync([1, 2, 3, 4]);
      expect(await CatalogCache.load(src), isNull);
    });

    test('size and clear', () async {
      await CatalogCache.save(src, 'x', blobs);
      expect(await CatalogCache.size(), greaterThan(0));
      await CatalogCache.clear();
      expect(await CatalogCache.size(), 0);
      expect(await CatalogCache.load(src), isNull);
    });

    test('a half written file is never left behind', () async {
      await CatalogCache.save(src, 'x', blobs);
      expect(dir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    });
  });

  group('parsing off the UI thread', () {
    final raw = [
      utf8.encode(jsonEncode([{'category_id': '1', 'category_name': 'News'}])),
      utf8.encode(jsonEncode([{'stream_id': 1, 'name': 'One', 'category_id': '1'}])),
      utf8.encode('[]'),
      utf8.encode('[]'),
      utf8.encode('[]'),
      utf8.encode('[]'),
    ].map(Uint8List.fromList).toList();

    test('the job holds only plain data, so a background isolate accepts it', () async {
      final c = await inBackground(xtreamParseJob('http://h', 'u', 'p', raw));
      expect(c.live.single.streamUrl, 'http://h/live/u/p/1.m3u8');
      expect(c.liveCategories.single.name, 'News');
    });

    test('a big answer is parsed in the background, a small one inline, with the same result', () async {
      final small = await parseAway('t', 10, xtreamParseJob('http://h', 'u', 'p', raw));
      final big = await parseAway('t', 10 * 1024 * 1024, xtreamParseJob('http://h', 'u', 'p', raw));
      expect(big.live.single.key, small.live.single.key);
      expect(PerfLog.factOf('t'), isNotNull);
    });

    test('a playlist parses the same way', () async {
      final bytes = Uint8List.fromList(utf8.encode('#EXTM3U\n#EXTINF:-1 group-title="News",One\nhttp://x/1.ts\n'));
      final c = await parseAway('m', 10 * 1024 * 1024, m3uParseJob(bytes));
      expect(c.live.single.name, 'One');
    });
  });

  group('start-up with a saved library', () {
    late FakePanel panel;
    setUp(() async {
      panel = FakePanel();
      await panel.start();
    });
    tearDown(() => panel.stop());

    /// Waits (briefly) until [app] has a library on screen, however it got there.
    Future<void> ready(AppState app) async {
      for (var i = 0; i < 200 && app.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    Future<AppState> boot(Source src, {bool waitForLibrary = false}) async {
      SharedPreferences.setMockInitialValues({
        'sources': [jsonEncode(src.toJson())],
        'active': src.name,
      });
      final app = AppState();
      await app.init(waitForLibrary: waitForLibrary);
      return app;
    }

    test('the first start fetches the library and saves it', () async {
      final src = panelSource(panel);
      final app = await boot(src, waitForLibrary: true);
      expect(app.catalog.live.single.name, 'One');
      expect(app.libraryFrom, isNull);
      // saving happens behind the scenes
      for (var i = 0; i < 50 && await CatalogCache.size() == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(await CatalogCache.size(), greaterThan(0));
      expect(PerfLog.factOf('library from'), 'provider');
      expect(PerfLog.factOf('fetch library'), isNotNull);
    });

    test('the next start shows the saved library before the provider answers, then refreshes it', () async {
      final src = panelSource(panel);
      await boot(src, waitForLibrary: true);
      for (var i = 0; i < 50 && await CatalogCache.size() == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      panel
        ..libraryDelay = const Duration(milliseconds: 600)
        ..liveName = 'One (renamed)';

      final sw = Stopwatch()..start();
      final app = await boot(src); // does not wait for the library at all
      expect(sw.elapsedMilliseconds, lessThan(300), reason: 'the app is up before the library is');
      expect(app.loading, isTrue);
      await ready(app);
      final shownAfter = sw.elapsedMilliseconds;
      expect(app.catalog.live.single.name, 'One', reason: 'the saved copy is on screen');
      expect(app.loading, isFalse);
      expect(app.refreshing, isTrue);
      expect(app.libraryFrom, isNotNull);
      expect(shownAfter, lessThan(550), reason: 'it must not have waited for the delayed provider');
      expect(app.catalog.live.single.streamUrl, startsWith('${panel.url}/live/u/'));

      // Then the provider's answer replaces it.
      for (var i = 0; i < 100 && app.refreshing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(app.refreshing, isFalse);
      expect(app.catalog.live.single.name, 'One (renamed)');
      expect(app.libraryFrom, isNull);
      expect(app.refreshError, isNull);
    });

    test('if the refresh fails the saved library stays and says so', () async {
      final src = panelSource(panel);
      await boot(src, waitForLibrary: true);
      for (var i = 0; i < 50 && await CatalogCache.size() == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      panel.failLibrary = true;
      final app = await boot(src);
      await ready(app);
      for (var i = 0; i < 100 && (app.refreshing || app.refreshError == null); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(app.catalog.live.single.name, 'One');
      expect(app.error, isNull);
      expect(app.refreshError, isNotNull);
    });

    test('with no saved copy the start-up does not wait either, and the library arrives', () async {
      panel.libraryDelay = const Duration(milliseconds: 300);
      final sw = Stopwatch()..start();
      final app = await boot(panelSource(panel));
      expect(sw.elapsedMilliseconds, lessThan(250));
      expect(app.loading, isTrue);
      for (var i = 0; i < 100 && app.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(app.catalog.live.single.name, 'One');
    });

    test('a saved library for a changed password still opens (the password is not part of it)', () async {
      final src = panelSource(panel);
      await boot(src, waitForLibrary: true);
      for (var i = 0; i < 50 && await CatalogCache.size() == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      panel.libraryDelay = const Duration(milliseconds: 400);
      final changed = Source(name: 'T', type: SourceType.xtream, url: panel.url, username: 'u', password: 'new-pass');
      final app = await boot(changed);
      await ready(app);
      expect(app.catalog.live, isNotEmpty);
      expect(app.catalog.live.single.streamUrl, contains('/u/'));
    });
  });

  group('PerfLog', () {
    test('a mark keeps its first time, facts keep their latest, and the report lists both', () async {
      PerfLog.mark('first frame');
      final first = PerfLog.at('first frame');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      PerfLog.mark('first frame');
      expect(PerfLog.at('first frame'), first);
      PerfLog.fact('library from', 'provider');
      PerfLog.fact('library from', 'saved copy');
      final r = await PerfLog.time('parse', () async => 42);
      expect(r, 42);
      final lines = PerfLog.report();
      expect(lines.any((l) => l.startsWith('first frame: ')), isTrue);
      expect(lines, contains('library from: saved copy'));
      expect(lines.any((l) => RegExp(r'^parse: \d+ ms$').hasMatch(l)), isTrue);
    });

    test('start clears the last run', () {
      PerfLog.mark('x');
      PerfLog.start();
      expect(PerfLog.at('x'), isNull);
      expect(PerfLog.report(), isEmpty);
    });
  });
}

Future<T> inBackground<T>(T Function() job) => Future(() async => parseAway('x', 10 * 1024 * 1024, job));
