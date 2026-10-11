import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/roku_installer/roku.dart';
import '../tool/roku_installer/ui.dart';
import 'support/fake_roku.dart';

/// The installer's window: the local server the page talks to, against a stand-in for a Roku.
void main() {
  late FakeRoku roku;
  late InstallerUi ui;
  late Uri base;
  final zip = [0x50, 0x4b, 3, 4, ...utf8.encode('channel')];

  Future<InstallerUi> open({
    Duration idle = const Duration(seconds: 30),
    RokuClient Function(String host)? clientFor,
    Future<List<String>> Function()? discover,
    bool launch = true,
  }) async {
    final u = InstallerUi(
      discover: discover ?? () async => ['127.0.0.1'],
      clientFor: clientFor ?? (_) => roku.client(),
      channel: () async => (bytes: zip, name: 'StreamBoss-test-roku.zip', tag: 'v0.0.0'),
      keyGap: Duration.zero,
      launchAfter: launch,
      idleTimeout: idle,
    );
    base = await u.start();
    return u;
  }

  /// A request to the window. Returns the status and the decoded JSON (or the text for a page).
  Future<({int status, Object? body})> call(String path,
      {Object? json, String? token, String? hostHeader}) async {
    final c = HttpClient();
    try {
      final uri = Uri(
          scheme: 'http', host: '127.0.0.1', port: base.port, path: path);
      final req = json == null ? await c.getUrl(uri) : await c.postUrl(uri);
      final t = token ?? ui.token;
      if (t.isNotEmpty) req.headers.set('x-token', t);
      if (hostHeader != null) req.headers.host = hostHeader;
      if (json != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(json));
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      Object? body = text;
      try {
        body = jsonDecode(text);
      } catch (_) {}
      return (status: res.statusCode, body: body);
    } finally {
      c.close(force: true);
    }
  }

  Future<Map> finished() async {
    for (var i = 0; i < 100; i++) {
      final r = await call('/api/status');
      final m = r.body as Map;
      if (m['state'] != 'running') return m;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('the install never finished');
  }

  setUp(() async {
    roku = FakeRoku();
    await roku.start();
  });
  tearDown(() async {
    await ui.stop();
    await roku.stop();
  });

  group('who may talk to it', () {
    test('the page opens only with the right token, on our own address', () async {
      ui = await open();
      final c = HttpClient();
      Future<int> page(String query, {String? host}) async {
        final req = await c.getUrl(Uri.parse('http://127.0.0.1:${base.port}/$query'));
        if (host != null) req.headers.host = host;
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      }

      expect(await page('?t=${ui.token}'), 200);
      expect(await page(''), 403);
      expect(await page('?t=wrong'), 403);
      expect(await page('?t=${ui.token}', host: 'evil.example'), 403,
          reason: 'a page on another site must not be able to use it');
      c.close(force: true);
      final r = await call('/');
      expect(r.status, 403);
    });

    test('the page is the installer and holds no outside address', () async {
      ui = await open();
      final c = HttpClient();
      final req = await c.getUrl(base);
      final res = await req.close();
      final html = await res.transform(utf8.decoder).join();
      c.close(force: true);
      expect(res.statusCode, 200);
      expect(html, contains('StreamBoss for Roku'));
      expect(html, isNot(contains('http://')));
      expect(html, isNot(contains('https://')));
      expect(res.headers.value('content-security-policy'), contains("default-src 'none'"));
    });

    test('the requests need the token too', () async {
      ui = await open();
      expect((await call('/api/status', token: 'nope')).status, 403);
      expect((await call('/api/scan', json: {}, token: 'nope')).status, 403);
      expect((await call('/api/other')).status, 404);
    });
  });

  group('finding the Roku', () {
    test('a scan lists what the network answered, with names', () async {
      ui = await open();
      final r = await call('/api/scan', json: {});
      expect(r.status, 200);
      final devices = (r.body as Map)['devices'] as List;
      expect(devices, hasLength(1));
      expect((devices.first as Map)['label'], contains('Living room'));
      expect((devices.first as Map)['host'], '127.0.0.1');
    });

    test('a scan that finds nothing is an empty list', () async {
      ui = await open(discover: () async => []);
      expect(((await call('/api/scan', json: {})).body as Map)['devices'], isEmpty);
    });

    test('a check says developer mode is on when the installer answers', () async {
      ui = await open();
      final r = (await call('/api/check', json: {'host': '127.0.0.1'})).body as Map;
      expect(r['reachable'], isTrue);
      expect(r['installerUp'], isTrue);
      expect(r['label'], contains('Roku Ultra'));
    });

    test('a check says developer mode is off when only the remote port answers', () async {
      ui = await open(
          clientFor: (_) => RokuClient('127.0.0.1', installerPort: 1, ecpPort: roku.ecp.port));
      final r = (await call('/api/check', json: {'host': '127.0.0.1'})).body as Map;
      expect(r['reachable'], isTrue);
      expect(r['installerUp'], isFalse);
    });

    test('a check says not found when nothing answers', () async {
      ui = await open(clientFor: (_) => RokuClient('127.0.0.1', installerPort: 1, ecpPort: 1));
      final r = (await call('/api/check', json: {'host': '127.0.0.1'})).body as Map;
      expect(r['reachable'], isFalse);
    });

    test('the address is cleaned up, and nonsense is refused', () async {
      final hosts = <String>[];
      ui = await open(clientFor: (h) {
        hosts.add(h);
        return roku.client();
      });
      await call('/api/check', json: {'host': ' http://192.168.1.40:8060/x '});
      expect(hosts, ['192.168.1.40']);
      for (final bad in ['', 'a b', 'x;rm', '../etc']) {
        final r = await call('/api/check', json: {'host': bad});
        expect(r.status, 400, reason: 'for "$bad"');
      }
    });

    test('it presses the remote\'s keys for Developer Settings', () async {
      ui = await open();
      final r = (await call('/api/devsettings', json: {'host': '127.0.0.1'})).body as Map;
      expect(r['ok'], isTrue);
      expect(roku.keys, ['Home', 'Home', 'Home', 'Up', 'Up', 'Right', 'Left', 'Right', 'Left', 'Right']);
    });

    test('a Roku that refuses the keys gets a plain sentence', () async {
      ui = await open(clientFor: (_) => RokuClient('127.0.0.1', installerPort: 1, ecpPort: 1));
      final r = (await call('/api/devsettings', json: {'host': '127.0.0.1'})).body as Map;
      expect(r['ok'], isFalse);
      expect(r['error'], contains('remote'));
    });
  });

  group('installing', () {
    test('it sends the channel, starts it, and shows each step', () async {
      ui = await open();
      final started = (await call('/api/install', json: {'host': '127.0.0.1', 'password': roku.password})).body as Map;
      expect(started['started'], isTrue);
      final st = await finished();
      expect(st['state'], 'done');
      expect(st['message'], contains('on your Roku'));
      final steps = (st['steps'] as List).cast<Map>();
      expect(steps.map((s) => s['state']), everyElement('done'));
      expect(steps.first['note'], contains('StreamBoss-test-roku.zip'));
      expect(roku.uploadedSubmit, 'Install');
      expect(roku.uploadedFile, zip);
      expect(roku.launched, isTrue);
    });

    test('with launch off it installs and does not start it', () async {
      ui = await open(launch: false);
      await call('/api/install', json: {'host': '127.0.0.1', 'password': roku.password});
      final st = await finished();
      expect(st['state'], 'done');
      expect((st['steps'] as List), hasLength(2));
      expect(roku.launched, isFalse);
    });

    test('a wrong password says so and can be tried again', () async {
      ui = await open();
      await call('/api/install', json: {'host': '127.0.0.1', 'password': 'wrong'});
      var st = await finished();
      expect(st['state'], 'failed');
      expect(st['message'], contains('password'));
      expect(((st['steps'] as List)[1] as Map)['state'], 'fail');
      expect(roku.launched, isFalse);

      await call('/api/install', json: {'host': '127.0.0.1', 'password': roku.password});
      st = await finished();
      expect(st['state'], 'done');
      expect(roku.launched, isTrue);
    });

    test('a failed install shows what the Roku said', () async {
      roku.result = '<font color="red">Install Failure: Compilation Failed.</font>';
      ui = await open();
      await call('/api/install', json: {'host': '127.0.0.1', 'password': roku.password});
      final st = await finished();
      expect(st['state'], 'failed');
      expect(st['message'], contains('Compilation'));
    });

    test('a download that fails stops at the first step', () async {
      final u = InstallerUi(
        discover: () async => [],
        clientFor: (_) => roku.client(),
        channel: () async => throw const RokuException('No release has a Roku channel file yet.'),
      );
      ui = u;
      base = await u.start();
      await call('/api/install', json: {'host': '127.0.0.1', 'password': 'x'});
      final st = await finished();
      expect(st['state'], 'failed');
      expect(st['message'], contains('No release'));
      expect(((st['steps'] as List).first as Map)['state'], 'fail');
      expect(roku.uploadedFile, isNull);
    });

    test('no password is asked for before anything is sent', () async {
      ui = await open();
      final r = await call('/api/install', json: {'host': '127.0.0.1', 'password': ''});
      expect(r.status, 400);
      expect(roku.uploadedFile, isNull);
    });

    test('the password is not in anything the page can read back', () async {
      ui = await open();
      await call('/api/install', json: {'host': '127.0.0.1', 'password': roku.password});
      final st = await finished();
      expect(jsonEncode(st), isNot(contains(roku.password)));
    });
  });

  group('closing', () {
    test('Close the installer ends the program', () async {
      ui = await open();
      var ended = false;
      unawaited(ui.done.then((_) => ended = true));
      expect((await call('/api/quit', json: {})).status, 200);
      await ui.done.timeout(const Duration(seconds: 3));
      expect(ended, isTrue);
    });

    test('closing the tab ends it after a while', () async {
      ui = await open(idle: const Duration(milliseconds: 600));
      await call('/api/ping');
      await ui.done.timeout(const Duration(seconds: 5));
    });

    test('it keeps running while the page keeps pinging', () async {
      ui = await open(idle: const Duration(milliseconds: 900));
      var ended = false;
      unawaited(ui.done.then((_) => ended = true));
      for (var i = 0; i < 6; i++) {
        await call('/api/ping');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(ended, isFalse);
    });

    test('with no page ever opened it waits (the address is on the console)', () async {
      ui = await open(idle: const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      var ended = false;
      unawaited(ui.done.then((_) => ended = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ended, isFalse);
    });
  });

  test('errors are told in plain words', () {
    expect(describeError(const SocketException('Connection refused')), contains('same network'));
    expect(describeError(TimeoutException('x')), contains('did not answer'));
    expect(describeError(const RokuException('Nope.')), 'Nope.');
  });
}
