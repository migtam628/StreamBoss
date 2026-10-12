import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamboss/app_info.dart';
import 'package:streamboss/services/update_check.dart';
import '../tool/roku_installer/roku.dart';

/// The release list now comes from the website (the repository is private), in the shape of GitHub's list.
Map<String, Object?> rel(String tag,
        {bool? pre, List<String> files = const []}) =>
    {
      'tag_name': tag,
      'draft': false,
      if (pre != null) 'prerelease': pre,
      'html_url': 'https://streamboss.site/downloads/$tag/',
      'body': 'notes for $tag',
      'assets': [
        for (final f in files)
          {
            'name': f,
            'size': 3,
            'browser_download_url': 'https://streamboss.site/downloads/$tag/$f',
            'digest': 'sha256:AB'
          },
      ],
    };

void main() {
  group('update check', () {
    Future<UpdateInfo> check(String current, List<Map<String, Object?>> list,
            {List<Uri>? asked}) =>
        checkForUpdate(current, client: MockClient((r) async {
          asked?.add(r.url);
          return http.Response(jsonEncode(list), 200);
        }));

    test('asks the website, not GitHub', () async {
      final asked = <Uri>[];
      await check('0.3.0b1', [rel('v0.3.0b2')], asked: asked);
      expect(asked.single.toString(), kReleasesFeed);
      expect(kReleasesFeed, 'https://streamboss.site/releases.json');
      expect(asked.single.host, isNot(contains('github')));
    });

    test('a beta build is offered the newest of everything', () async {
      final u = await check('0.3.0b1', [
        rel('v0.3.0b3', pre: true),
        rel('v0.3.0b2', pre: true),
        rel('v0.2.9', pre: false)
      ]);
      expect(u.latest, '0.3.0b3');
      expect(u.newer, isTrue);
      expect(u.url, 'https://streamboss.site/downloads/v0.3.0b3/');
      expect(u.notes, 'notes for v0.3.0b3');
    });

    test('a stable build is only offered stable releases', () async {
      final list = [
        rel('v0.4.0b1', pre: true),
        rel('v0.3.1', pre: false),
        rel('v0.3.0b9')
      ];
      final u = await check('0.3.0', list);
      expect(u.latest, '0.3.1');
      expect(u.newer, isTrue);
      final none = await check('0.3.1', list);
      expect(none.newer, isFalse);
    });

    test('a prerelease is recognised by its tag when the list does not say',
        () async {
      final u = await check('0.3.0', [rel('v0.3.1b2'), rel('v0.3.0')]);
      expect(u.latest, '0.3.0');
      expect(u.newer, isFalse);
    });

    test(
        'only betas published so far: a stable build is told there is nothing yet',
        () async {
      await expectLater(check('0.3.0', [rel('v0.3.0b5', pre: true)]),
          throwsA(predicate((e) => '$e'.contains('No releases'))));
    });

    test('files and their checksums come through', () async {
      final u = await check('0.3.0b1', [
        rel('v0.3.0b2', files: ['StreamBoss-0.3.0b2-macos.zip'])
      ]);
      expect(u.assets.single.name, 'StreamBoss-0.3.0b2-macos.zip');
      expect(u.assets.single.url,
          'https://streamboss.site/downloads/v0.3.0b2/StreamBoss-0.3.0b2-macos.zip');
      expect(u.assets.single.sha256, 'ab');
    });

    test('a server that fails is a plain sentence', () async {
      final bad = checkForUpdate('0.3.0b1',
          client: MockClient((_) async => http.Response('nope', 500)));
      await expectLater(
          bad,
          throwsA(
              predicate((e) => '$e'.contains('update server answered 500'))));
      final none = checkForUpdate('0.3.0b1',
          client: MockClient((_) async => http.Response('', 404)));
      await expectLater(
          none, throwsA(predicate((e) => '$e'.contains('No releases'))));
    });
  });

  group('Roku installer download', () {
    test('reads the website list and downloads the newest channel from it',
        () async {
      final zip = [0x50, 0x4b, 3, 4, 1, 2, 3];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        if (req.uri.path == '/releases.json') {
          req.response.write(jsonEncode([
            {
              'tag_name': 'v0.3.0b2',
              'assets': [
                {
                  'name': 'StreamBoss-0.3.0b2-macos.zip',
                  'browser_download_url': '$base/x.zip'
                }
              ]
            },
            {
              'tag_name': 'v0.3.0b1',
              'assets': [
                {
                  'name': 'StreamBoss-0.3.0b1-roku.zip',
                  'browser_download_url': '$base/roku.zip'
                }
              ]
            },
          ]));
        } else if (req.uri.path == '/roku.zip') {
          req.response.add(zip);
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      final got = await downloadLatest(feed: '$base/releases.json');
      expect(got.tag, 'v0.3.0b1');
      expect(got.name, 'StreamBoss-0.3.0b1-roku.zip');
      expect(got.bytes, zip);
    });
  });
}
