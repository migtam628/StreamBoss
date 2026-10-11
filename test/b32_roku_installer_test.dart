import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/roku_installer/roku.dart';

/// A stand-in for a Roku in developer mode: an installer on one port (digest sign-in, user rokudev) and the
/// remote-control port on another.
class FakeRoku {
  late HttpServer installer, ecp;
  final password = 'hunter2';
  final keys = <String>[];
  var launched = false;
  Uint8List? uploadedFile;
  String? uploadedSubmit;
  String result = '<font color="red">Install Success.</font>';
  var developerEnabled = true;
  final nonce = 'abc123nonce';

  Future<void> start() async {
    installer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    installer.listen((req) async {
      final body = BytesBuilder();
      await for (final c in req) {
        body.add(c);
      }
      final auth = req.headers.value('authorization');
      bool ok = false;
      if (auth != null) {
        final c = parseChallenge(auth);
        final ha1 =
            md5.convert(utf8.encode('rokudev:rokudev:$password')).toString();
        final ha2 = md5
            .convert(utf8.encode('${req.method}:${req.uri.path}'))
            .toString();
        final want = md5
            .convert(
                utf8.encode('$ha1:$nonce:${c['nc']}:${c['cnonce']}:auth:$ha2'))
            .toString();
        ok = c['response'] == want &&
            c['username'] == 'rokudev' &&
            c['uri'] == req.uri.path;
      }
      if (!ok) {
        req.response.statusCode = 401;
        req.response.headers.set('www-authenticate',
            'Digest realm="rokudev", nonce="$nonce", qop="auth", algorithm=MD5');
        await req.response.close();
        return;
      }
      if (req.method == 'POST') {
        final text = latin1.decode(body.toBytes());
        uploadedSubmit =
            RegExp(r'name="mysubmit"\r\n\r\n([^\r]*)').firstMatch(text)?[1];
        final start =
            text.indexOf('\r\n\r\n', text.indexOf('name="archive"')) + 4;
        final end = text.lastIndexOf('\r\n--');
        uploadedFile =
            Uint8List.fromList(latin1.encode(text.substring(start, end)));
        req.response.write('<html><body>$result</body></html>');
      } else {
        req.response.write('<html>installer</html>');
      }
      await req.response.close();
    });
    ecp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ecp.listen((req) async {
      await req.drain<void>();
      if (req.uri.path == '/query/device-info') {
        req.response.write(
            '<device-info><user-device-name>Living room</user-device-name><model-name>Roku Ultra</model-name>'
            '<developer-enabled>$developerEnabled</developer-enabled></device-info>');
      } else if (req.uri.path.startsWith('/keypress/')) {
        keys.add(req.uri.pathSegments.last);
      } else if (req.uri.path == '/launch/dev') {
        launched = true;
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  }

  RokuClient client() =>
      RokuClient('127.0.0.1', installerPort: installer.port, ecpPort: ecp.port);
  Future<void> stop() async {
    await installer.close(force: true);
    await ecp.close(force: true);
  }
}

void main() {
  group('digest sign-in', () {
    test('the example in RFC 2617 gives the same answer', () {
      final h = digestAuthorization(
        challenge: parseChallenge(
            'Digest realm="testrealm@host.com", qop="auth,auth-int", nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", opaque="5ccc069c403ebaf9f0171e9517f40e41"'),
        user: 'Mufasa',
        password: 'Circle Of Life',
        method: 'GET',
        uri: '/dir/index.html',
        cnonce: '0a4f113b',
      );
      expect(h, contains('response="6629fae49393a05397450978507c4ef1"'));
      expect(h, contains('nc=00000001'));
      expect(h, contains('opaque="5ccc069c403ebaf9f0171e9517f40e41"'));
    });
    test('a challenge without qop uses the older formula', () {
      final c = parseChallenge('Digest realm="r", nonce="n"');
      expect(c, {'realm': 'r', 'nonce': 'n'});
      final h = digestAuthorization(
          challenge: c, user: 'u', password: 'p', method: 'GET', uri: '/');
      expect(h, isNot(contains('qop')));
      final ha1 = md5.convert(utf8.encode('u:r:p')).toString();
      final ha2 = md5.convert(utf8.encode('GET:/')).toString();
      expect(
          h, contains('response="${md5.convert(utf8.encode('$ha1:n:$ha2'))}"'));
    });
  });

  test('a multipart body carries the fields and the file bytes untouched', () {
    final file = [0x50, 0x4b, 3, 4, 0, 255, 13, 10, 45, 45];
    final m = buildMultipart(
        fields: {'mysubmit': 'Install'},
        fileField: 'archive',
        fileName: 'a.zip',
        file: file,
        boundary: 'XX');
    expect(m.contentType, 'multipart/form-data; boundary=XX');
    final text = latin1.decode(m.body);
    expect(
        text,
        startsWith(
            '--XX\r\nContent-Disposition: form-data; name="mysubmit"\r\n\r\nInstall\r\n'));
    expect(text, contains('name="archive"; filename="a.zip"'));
    expect(text, endsWith('\r\n--XX--\r\n'));
    final at = latin1
            .decode(m.body)
            .indexOf('\r\n\r\n', text.indexOf('name="archive"')) +
        4;
    expect(m.body.sublist(at, at + file.length), file);
  });

  group('reading what the Roku says', () {
    test('install results', () {
      expect(
          parseInstallResult('<font color="red">Install Success.</font>')
              .outcome,
          InstallOutcome.installed);
      expect(
          parseInstallResult(
                  '<b>Identical to previous version -- not replacing.</b>')
              .outcome,
          InstallOutcome.identical);
      expect(
          parseInstallResult(
                  '<b>Identical to previous version -- not replacing.</b>')
              .ok,
          isTrue);
      final f = parseInstallResult(
          '<font>Install Failure: Compilation Failed.</font>');
      expect(f.outcome, InstallOutcome.failed);
      expect(f.message, contains('Compilation Failed'));
      expect(parseInstallResult('<html>hello</html>').outcome,
          InstallOutcome.unknown);
    });
    test('an SSDP answer gives the Roku\'s address', () {
      const answer =
          'HTTP/1.1 200 OK\r\nCache-Control: max-age=3600\r\nST: roku:ecp\r\nUSN: uuid:roku:ecp:X0001\r\nLOCATION: http://192.168.1.40:8060/\r\nServer: Roku/9.4.0\r\n\r\n';
      expect(parseSsdpHost(answer), '192.168.1.40');
      expect(parseSsdpHost('nothing'), isNull);
    });
    test('the newest channel file among the releases', () {
      final json = jsonEncode([
        {
          'tag_name': 'v9',
          'draft': true,
          'assets': [
            {
              'name': 'StreamBoss-9-roku.zip',
              'browser_download_url': 'http://x/draft'
            }
          ]
        },
        {
          'tag_name': 'v0.3.0b31',
          'assets': [
            {
              'name': 'StreamBoss-0.3.0b31-android.apk',
              'browser_download_url': 'http://x/apk'
            },
            {
              'name': 'StreamBoss-0.3.0b31-roku.zip',
              'browser_download_url': 'http://x/roku'
            }
          ]
        },
        {
          'tag_name': 'v0.3.0b30',
          'assets': [
            {
              'name': 'StreamBoss-0.3.0b30-roku.zip',
              'browser_download_url': 'http://x/old'
            }
          ]
        },
      ]);
      final p = pickRokuAsset(json)!;
      expect(p.tag, 'v0.3.0b31');
      expect(p.url, 'http://x/roku');
      expect(pickRokuAsset('[]'), isNull);
      expect(looksLikeZip([0x50, 0x4b, 3, 4, 0]), isTrue);
      expect(looksLikeZip(utf8.encode('<html>')), isFalse);
    });
  });

  group('against a Roku in developer mode', () {
    late FakeRoku roku;
    setUp(() async {
      roku = FakeRoku();
      await roku.start();
    });
    tearDown(() => roku.stop());

    test('it is found by name and model, and the installer is up', () async {
      final c = roku.client();
      final d = (await c.deviceInfo())!;
      expect(d.name, 'Living room');
      expect(d.model, 'Roku Ultra');
      expect(d.developerMode, isTrue);
      expect(d.label, 'Living room (Roku Ultra) 127.0.0.1');
      expect(await c.installerUp(), isTrue);
      c.close();
    });

    test('the channel file arrives whole, and the channel starts', () async {
      final zip = [
        0x50,
        0x4b,
        3,
        4,
        ...List.generate(3000, (i) => i % 251),
        13,
        10,
        45,
        45
      ];
      final c = roku.client();
      final r = await c.install(zip, 'hunter2');
      expect(r.outcome, InstallOutcome.installed);
      expect(roku.uploadedSubmit, 'Install');
      expect(roku.uploadedFile, zip);
      await c.launchDev();
      expect(roku.launched, isTrue);
      c.close();
    });

    test('a wrong password says whose password it is', () async {
      final c = roku.client();
      await expectLater(
          c.install([0x50, 0x4b, 3, 4], 'nope'),
          throwsA(isA<RokuException>().having(
              (e) => e.message, 'message', contains('refused the password'))));
      expect(roku.uploadedFile, isNull);
      c.close();
    });

    test('a failed install and an identical one are reported', () async {
      final c = roku.client();
      roku.result = 'Install Failure: Compilation Failed.';
      expect((await c.install([0x50, 0x4b], 'hunter2')).ok, isFalse);
      roku.result = 'Identical to previous version -- not replacing.';
      expect((await c.install([0x50, 0x4b], 'hunter2')).ok, isTrue);
      c.close();
    });

    test('the Developer Settings sequence is the remote\'s own', () async {
      final c = roku.client();
      await c.openDeveloperSettings(gap: Duration.zero);
      expect(roku.keys, [
        'Home',
        'Home',
        'Home',
        'Up',
        'Up',
        'Right',
        'Left',
        'Right',
        'Left',
        'Right'
      ]);
      c.close();
    });
  });

  test('a Roku with developer mode off has no installer', () async {
    final c = RokuClient('127.0.0.1', installerPort: 9, ecpPort: 9);
    expect(await c.installerUp(), isFalse);
    expect(await c.deviceInfo(), isNull);
    c.close();
  });
}
