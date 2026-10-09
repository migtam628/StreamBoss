import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/library_view.dart';
import 'package:streamboss/services/stream_check.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';

// Real loopback requests, so this lives apart from the widget tests (flutter_test fakes HTTP there).

void main() {
  late HttpServer server;
  var live = 0, peak = 0;
  final seenRanges = <String?>[];
  final endlessClosed = Completer<void>();

  setUp(() async {
    live = peak = 0;
    seenRanges.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final res = r.response;
      switch (r.uri.path) {
        case '/ok.ts':
          res.headers.contentType = ContentType('video', 'mp2t');
          res.add(List.filled(3000, 0x47));
        case '/hls.m3u8':
          res.headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl');
          res.write('#EXTM3U\n#EXT-X-VERSION:3\n');
        case '/gone':
          res.statusCode = 404;
        case '/busy':
          res.statusCode = 429;
        case '/error-page':
          res.headers.contentType = ContentType.html;
          res.write('<html><body>Stream not found</body></html>');
        case '/html-no-type':
          res.headers.contentType = ContentType('application', 'octet-stream');
          res.write('<!DOCTYPE html><html></html>');
        case '/empty':
          break;
        case '/needs-header':
          if (r.headers.value('x-test') != 'yes') {
            res.statusCode = 403;
          } else {
            res.add(List.filled(100, 1));
          }
        case '/hang':
          return; // never answers
        case '/endless':
          seenRanges.add(r.headers.value('range'));
          final socket = await res.detachSocket(writeHeaders: false);
          socket.write(
              'HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\nConnection: close\r\n\r\n');
          // The client hanging up shows as the read side closing.
          socket.listen((_) {}, onDone: () {
            if (!endlessClosed.isCompleted) endlessClosed.complete();
          }, onError: (_) {
            if (!endlessClosed.isCompleted) endlessClosed.complete();
          });
          for (var i = 0; i < 4000 && !endlessClosed.isCompleted; i++) {
            try {
              socket.add(List.filled(16384, 0x47));
              await socket.flush();
            } catch (_) {
              if (!endlessClosed.isCompleted) endlessClosed.complete();
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          socket.destroy();
          return;
        case '/slow':
          live++;
          if (live > peak) peak = live;
          await Future<void>.delayed(const Duration(milliseconds: 60));
          res.add(List.filled(50, 1));
          live--;
        default:
          res.statusCode = 404;
      }
      await res.close();
    });
  });
  tearDown(() => server.close(force: true));

  String u(String p) => 'http://127.0.0.1:${server.port}$p';
  MediaItem ch(String path, {int n = 1, Map<String, String>? headers}) =>
      MediaItem(
          id: '$n',
          name: 'Ch $n',
          kind: MediaKind.live,
          streamUrl: u(path),
          categoryId: 'c',
          headers: headers);

  group('streamProblem', () {
    test('a stream that sends data is fine', () async {
      expect(await streamProblem(ch('/ok.ts')), isNull);
      expect(await streamProblem(ch('/hls.m3u8')), isNull);
    });

    test('names what is wrong with the others', () async {
      expect(await streamProblem(ch('/gone')), 'HTTP 404');
      expect(await streamProblem(ch('/error-page')), 'not a stream');
      expect(await streamProblem(ch('/html-no-type')), 'not a stream');
      expect(await streamProblem(ch('/empty')), 'no data');
      expect(
          await streamProblem(ch('/hang'),
              timeout: const Duration(milliseconds: 300)),
          'timed out');
      expect(
          await streamProblem(const MediaItem(
              id: 'x',
              name: 'x',
              kind: MediaKind.live,
              streamUrl: 'http://127.0.0.1:1/none')),
          'unreachable');
      expect(
          await streamProblem(const MediaItem(
              id: 'y',
              name: 'y',
              kind: MediaKind.live,
              streamUrl: 'not a url')),
          'bad address');
    });

    test('being told to slow down is not a dead channel', () async {
      expect(await streamProblem(ch('/busy')), isNull);
    });

    test('sends the headers the playlist asked for', () async {
      expect(await streamProblem(ch('/needs-header')), 'HTTP 403');
      expect(
          await streamProblem(
              ch('/needs-header', headers: const {'X-Test': 'yes'})),
          isNull);
    });

    test('asks for the start only and hangs up on a stream that never ends',
        () async {
      final sw = Stopwatch()..start();
      final problems = <String?>[];
      await checkStreams([ch('/endless')],
          parallel: 1, onResult: (_, p, __) => problems.add(p));
      expect(problems, [null]);
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(seenRanges.single, 'bytes=0-2047');
      await endlessClosed.future.timeout(const Duration(seconds: 5));
    });

    test('an item with no address (a series) is skipped', () async {
      expect(
          await streamProblem(
              const MediaItem(id: 's', name: 's', kind: MediaKind.series)),
          isNull);
    });
  });

  group('checkStreams', () {
    test('keeps to the number of parallel requests and reports every channel',
        () async {
      final items = [for (var i = 0; i < 9; i++) ch('/slow', n: i)];
      final done = <int>[];
      await checkStreams(items, parallel: 3, onResult: (_, p, d) {
        expect(p, isNull);
        done.add(d);
      });
      expect(done.length, 9);
      expect(done.last, 9);
      expect(peak, lessThanOrEqualTo(3));
      expect(peak, greaterThan(1));
    });

    test('stops when asked to', () async {
      final items = [for (var i = 0; i < 30; i++) ch('/slow', n: i)];
      var seen = 0;
      await checkStreams(items,
          parallel: 2,
          cancelled: () => seen >= 4,
          onResult: (_, __, ___) => seen++);
      expect(seen, inInclusiveRange(4, 6));
    });
  });

  group('AppState.checkLive', () {
    test('remembers dead channels, hides them on request and forgets them',
        () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState();
      await settings.init();
      final app = AppState()..bindSettings(settings);
      await app.init();
      app.active = const Source(
          name: 'Free', type: SourceType.m3u, url: 'http://x/y.m3u');
      final ok = ch('/ok.ts', n: 1),
          dead = ch('/gone', n: 2),
          page = ch('/error-page', n: 3);
      app.catalog = Catalog(
          live: [ok, dead, page],
          liveCategories: const [Category('c', 'News')]);

      await app.checkLive();
      expect(app.checking, isFalse);
      expect(app.checkedCount, 3);
      expect(app.deadKeys, {dead.key, page.key});
      expect(app.isDead(dead), isTrue);
      expect(app.isDead(ok), isFalse);

      // Still listed until the option is on.
      expect(app.shown.live.length, 3);
      settings.set('hideDead', true);
      expect(app.shown.live.map((e) => e.name), ['Ch 1']);
      // Other kinds are never hidden.
      expect(app.shown.movies, isEmpty);

      // The result survives a restart.
      final again = AppState();
      await again.init();
      again.active = app.active;
      expect(again.deadKeys, {dead.key, page.key});

      app.forgetCheck();
      expect(app.deadKeys, isEmpty);
      expect(app.shown.live.length, 3);
    });
  });

  group('buildView', () {
    const c = Catalog(
      liveCategories: [
        Category('1', 'News'),
        Category('2', 'Kids Cartoons'),
        Category('3', 'Adult XXX')
      ],
      live: [
        MediaItem(id: 'a', name: 'A', kind: MediaKind.live, categoryId: '1'),
        MediaItem(id: 'b', name: 'B', kind: MediaKind.live, categoryId: '2'),
        MediaItem(id: 'c', name: 'C', kind: MediaKind.live, categoryId: '3'),
        MediaItem(
            id: 'd', name: 'D', kind: MediaKind.live, categoryId: 'unlisted'),
      ],
    );

    test('hideKeys drops just those items', () {
      final v =
          buildView(c, hideAdult: false, sortAz: false, hideKeys: {'live:a'});
      expect(v.live.map((e) => e.id), ['b', 'c', 'd']);
    });

    test('a kids view keeps only kid categories and what sits in them', () {
      final v = buildView(c, hideAdult: false, sortAz: false, kidsOnly: true);
      expect(v.liveCategories.map((e) => e.name), ['Kids Cartoons']);
      expect(v.live.map((e) => e.id), ['b']);
    });

    test('no option returns the same catalog', () {
      expect(
          identical(buildView(c, hideAdult: false, sortAz: false), c), isTrue);
    });

    test('the kids matcher ignores adult names', () {
      expect(isKidsCategory('Kids'), isTrue);
      expect(isKidsCategory('Family Movies'), isTrue);
      expect(isKidsCategory('Adult Family XXX'), isFalse);
      expect(isKidsCategory('News'), isFalse);
    });
  });
}
