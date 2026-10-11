import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/roku_installer/roku.dart';
import 'support/fake_roku.dart';

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
      expect(roku.uploadedSubmit, 'Replace');
      expect(roku.uploadedPasswd, '');
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

    group('a Roku that is particular about the upload', () {
      final zip = [0x50, 0x4b, 3, 4, 1, 2, 3];

      test('a 400 is answered by trying the other button name', () async {
        roku.acceptSubmits = {'Install'};
        final c = roku.client();
        final r = await c.install(zip, 'hunter2');
        expect(r.ok, isTrue);
        expect(roku.attempts, ['Replace+passwd', 'Install+passwd']);
        expect(roku.uploadedFile, zip);
        c.close();
      });

      test('a 400 for the empty passwd field is answered by leaving it out', () async {
        roku.rejectPasswdField = true;
        final c = roku.client();
        expect((await c.install(zip, 'hunter2')).ok, isTrue);
        expect(roku.attempts.last, isNot(contains('passwd')));
        expect(roku.uploadedFile, zip);
        c.close();
      });

      test('a Roku that wants the passwd field gets it on the first try', () async {
        roku.requirePasswdField = true;
        final c = roku.client();
        expect((await c.install(zip, 'hunter2')).ok, isTrue);
        expect(roku.attempts, ['Replace+passwd']);
        c.close();
      });

      test('a wrong password is not retried', () async {
        roku.acceptSubmits = {'Install'};
        final c = roku.client();
        await expectLater(c.install(zip, 'wrong'), throwsA(isA<RokuException>()));
        expect(roku.attempts, isEmpty);
        c.close();
      });

      test('when every way gets a 400 the answer says so, with what the Roku said', () async {
        roku.alwaysBadRequest = true;
        final c = roku.client();
        await expectLater(
            c.install(zip, 'hunter2'),
            throwsA(isA<RokuException>().having((e) => e.message, 'message',
                allOf(contains('400'), contains('Bad Request'), contains('upload page')))));
        expect(roku.attempts, hasLength(4));
        c.close();
      });
    });

    group('the Roku\'s own words after a failed install', () {
      final zip = [0x50, 0x4b, 3, 4, 1, 2, 3];

      test('a compile error from the debug console comes with the result', () async {
        roku.result = 'Application Received: 7 bytes stored.<br>Install Failure: Compilation Failed. MainScene';
        roku.consoleText =
            "------ Compiling dev 'StreamBoss' ------\r\n"
            'Syntax Error. (compile error &h02) in pkg:/components/MainScene.brs(27)\r\n'
            '------ Running dev ------\r\n';
        final c = roku.client();
        final r = await c.installWithLog(zip, 'hunter2');
        expect(r.ok, isFalse);
        expect(r.message, contains('Compilation Failed'));
        expect(r.details, contains('MainScene.brs(27)'));
        expect(r.details, isNot(contains('Running dev')));
        c.close();
      });

      test('a good install carries no details', () async {
        roku.consoleText = 'Something harmless\r\n';
        final c = roku.client();
        final r = await c.installWithLog(zip, 'hunter2');
        expect(r.ok, isTrue);
        expect(r.details, isEmpty);
        c.close();
      });

      test('a Roku with no console still installs and still reports', () async {
        roku.result = 'Install Failure: Compilation Failed.';
        final c = RokuClient('127.0.0.1',
            installerPort: roku.installer.port,
            ecpPort: roku.ecp.port,
            consolePort: 1);
        final r = await c.installWithLog(zip, 'hunter2');
        expect(r.ok, isFalse);
        expect(r.details, isEmpty);
        c.close();
      });

      test('the lines worth showing are picked out of a noisy console', () {
        const log = 'boot noise\r\nmore noise\r\n'
            'Syntax Error. (compile error &h02) in pkg:/components/MainScene.brs(27)\r\n'
            'Syntax Error. (compile error &h02) in pkg:/components/MainScene.brs(27)\r\n'
            'Dev: Compilation failed\r\nlast line\r\n';
        expect(consoleErrors(log), 'Syntax Error. (compile error &h02) in pkg:/components/MainScene.brs(27)\nDev: Compilation failed');
        expect(consoleErrors('one\ntwo\nthree'), 'one\ntwo\nthree');
        expect(consoleErrors(''), '');
      });
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
