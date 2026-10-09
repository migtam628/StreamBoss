import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/subtitle_search.dart';

MediaItem _item(String name, {MediaKind kind = MediaKind.movie}) =>
    MediaItem(id: '1', name: name, kind: kind, streamUrl: 'http://x/1.mp4');

void main() {
  group('queries', () {
    test('a movie is searched by title and year', () {
      final q = SubtitleSearch.queryFor(_item('Night Run (2019) 1080p'),
          language: 'EN');
      expect(q['type'], 'movie');
      expect(q['year'], '2019');
      expect(q['languages'], 'en');
      expect(q['query'], isNot(contains('2019')));
      expect(q.containsKey('season_number'), isFalse);
    });

    test('an episode is searched by season and episode', () {
      final se = parseSeasonEpisode('The Long Road S02E05 - Homecoming');
      expect(se, (2, 5));
      final q = SubtitleSearch.queryFor(
          _item('The Long Road S02E05 - Homecoming'),
          season: se!.$1,
          episode: se.$2);
      expect(q['type'], 'episode');
      expect(q['season_number'], '2');
      expect(q['episode_number'], '5');
      expect(q['query']!.toLowerCase(), contains('long road'));
      expect(q['query'], isNot(contains('Homecoming')));
    });

    test('season and episode in other styles, and none', () {
      expect(parseSeasonEpisode('Show 3x07'), (3, 7));
      expect(parseSeasonEpisode('s1e2 pilot'), (1, 2));
      expect(parseSeasonEpisode('Plain Movie'), isNull);
    });
  });

  group('against a loopback OpenSubtitles', () {
    late HttpServer server;
    late Uri base;
    final seen = <String>[];
    var downloadStatus = 200;

    setUp(() async {
      seen.clear();
      downloadStatus = 200;
      server = await HttpServer.bind('127.0.0.1', 0);
      base = Uri.parse('http://127.0.0.1:${server.port}/api/v1/');
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        seen.add(
            '${req.method} ${req.uri.path} key=${req.headers.value('api-key')} auth=${req.headers.value('authorization')}');
        final res = req.response;
        void json(Object o, [int code = 200]) {
          res.statusCode = code;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode(o));
        }

        if (req.uri.path.startsWith('/api/') &&
            req.headers.value('api-key') != 'goodkey') {
          json({'message': 'bad key'}, 401);
        } else if (req.uri.path.endsWith('/subtitles')) {
          json({
            'data': [
              {
                'attributes': {
                  'language': 'en',
                  'download_count': 1200,
                  'hearing_impaired': false,
                  'files': [
                    {'file_id': 111, 'file_name': 'Night.Run.2019.en.srt'}
                  ],
                }
              },
              {
                'attributes': {'language': 'es', 'files': []}
              },
              {
                'attributes': {
                  'language': 'fr',
                  'hearing_impaired': true,
                  'files': [
                    {'file_id': 222, 'file_name': 'Night.Run.fr.srt'}
                  ],
                }
              },
            ]
          });
        } else if (req.uri.path.endsWith('/login')) {
          final j = jsonDecode(body) as Map;
          if (j['password'] == 'pw') {
            json({'token': 'tok123'});
          } else {
            json({'message': 'no'}, 401);
          }
        } else if (req.uri.path.endsWith('/download')) {
          if (downloadStatus != 200) {
            json({'message': 'x'}, downloadStatus);
          } else {
            json({
              'link': 'http://127.0.0.1:${server.port}/files/111.srt',
              'file_name': 'a.srt'
            });
          }
        } else if (req.uri.path == '/files/111.srt') {
          res.write('1\n00:00:01,000 --> 00:00:02,000\nHello\n');
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('search lists files, skipping results without one', () async {
      final hits = await SubtitleSearch('goodkey', baseUri: base)
          .search(SubtitleSearch.queryFor(_item('Night Run (2019)')));
      expect(hits.map((h) => h.fileId), ['111', '222']);
      expect(hits.first.downloads, 1200);
      expect(hits.last.hearingImpaired, isTrue);
      expect(seen.single, contains('key=goodkey'));
    });

    test('a wrong key says so in words', () async {
      expect(
        () => SubtitleSearch('nope', baseUri: base).search({'query': 'x'}),
        throwsA(isA<SubtitleSearchError>()
            .having((e) => e.message, 'message', contains('API key'))),
      );
    });

    test('no key asks for one without calling out', () async {
      await expectLater(
          SubtitleSearch('', baseUri: base).search({'query': 'x'}),
          throwsA(isA<SubtitleSearchError>()));
      expect(seen, isEmpty);
    });

    test('download logs in when there is an account and returns the text',
        () async {
      final svc = SubtitleSearch('goodkey',
          username: 'me', password: 'pw', baseUri: base);
      final text = await svc.download(
          const SubtitleHit(fileId: '111', name: 'a', language: 'en'));
      expect(text, contains('Hello'));
      expect(seen.any((l) => l.contains('/login')), isTrue);
      expect(
          seen.any((l) =>
              l.contains('/download') && l.contains('auth=Bearer tok123')),
          isTrue);
    });

    test('a wrong password and a used-up limit are explained', () async {
      await expectLater(
        SubtitleSearch('goodkey',
                username: 'me', password: 'bad', baseUri: base)
            .download(
                const SubtitleHit(fileId: '111', name: 'a', language: 'en')),
        throwsA(isA<SubtitleSearchError>()
            .having((e) => e.message, 'm', contains('username'))),
      );
      downloadStatus = 406;
      await expectLater(
        SubtitleSearch('goodkey', username: 'me', password: 'pw', baseUri: base)
            .download(
                const SubtitleHit(fileId: '111', name: 'a', language: 'en')),
        throwsA(isA<SubtitleSearchError>()
            .having((e) => e.message, 'm', contains('limit'))),
      );
    });

    test(
        'without an account the download is tried anyway and a 401 says what to add',
        () async {
      downloadStatus = 401;
      await expectLater(
        SubtitleSearch('goodkey', baseUri: base).download(
            const SubtitleHit(fileId: '111', name: 'a', language: 'en')),
        throwsA(isA<SubtitleSearchError>()
            .having((e) => e.message, 'm', contains('username and password'))),
      );
    });
  });
}
