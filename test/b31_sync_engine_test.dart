import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/services/sync/sync_api.dart';
import 'package:streamboss/services/sync/sync_engine.dart';
import 'package:streamboss/state/sync_state.dart';

/// A stand-in for the sync server (server/): accounts are not checked, values are kept with a revision that goes
/// up, and a write built on an old revision is refused, as the real one does.
class FakeServer {
  late final HttpServer http;
  final items = <String, ({String? value, int rev})>{};
  var requests = 0;
  var conflictOnce =
      <String>{}; // keys whose next write finds that "another device" got there first
  var signedOut = false;
  String registration = 'first';

  Future<void> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      requests++;
      final body = await utf8.decoder.bind(req).join();
      final j = body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      void reply(int status, Object? o) {
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        if (o != null) req.response.write(jsonEncode(o));
        req.response.close();
      }

      final path = req.uri.path;
      if (path == '/api/health') {
        return reply(200, {'ok': true, 'registration': registration});
      }
      if (path == '/api/register' || path == '/api/login') {
        if (j['password'] == 'wrong password') {
          return reply(401, {'error': 'The e-mail or the password is wrong.'});
        }
        return reply(200, {'token': 'T' * 43, 'email': j['email']});
      }
      if (signedOut) {
        return reply(401, {'error': 'You are signed out. Sign in again.'});
      }
      if (path == '/api/logout') return reply(204, null);
      if (path == '/api/data' && req.method == 'GET') {
        return reply(200, {
          'items': {
            for (final e in items.entries)
              e.key: {'value': e.value.value, 'rev': e.value.rev, 'updated': 0}
          },
        });
      }
      final m = RegExp(r'^/api/data/(.+)$').firstMatch(path);
      if (m != null && req.method == 'PUT') {
        final key = Uri.decodeComponent(m[1]!);
        final cur = items[key];
        if (conflictOnce.remove(key)) {
          // Another device writes first.
          final other = (
            value: jsonEncode({
              't': 'l',
              'v': ['from-another-device']
            }),
            rev: (cur?.rev ?? 0) + 1
          );
          items[key] = other;
          return reply(409, {
            'error': 'Changed elsewhere',
            'rev': other.rev,
            'value': other.value
          });
        }
        if ((cur?.rev ?? 0) != j['base']) {
          return reply(409, {
            'error': 'Changed elsewhere',
            'rev': cur?.rev ?? 0,
            'value': cur?.value
          });
        }
        items[key] = (value: j['value'] as String?, rev: (cur?.rev ?? 0) + 1);
        return reply(200, {'rev': items[key]!.rev});
      }
      reply(404, {'error': 'Not found.'});
    });
  }

  String get url => 'http://127.0.0.1:${http.port}';
  Future<void> stop() => http.close(force: true);

  /// What the server holds, as one text, to look for things that must not be in it.
  String get everything =>
      jsonEncode({for (final e in items.entries) e.key: e.value.value});
}

/// One device: its own preferences, kept apart from the others between runs.
class Device {
  Map<String, Object> data;
  Device([this.data = const {}]);

  Future<SharedPreferences> use() async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(Map.of(data));
    return SharedPreferences.getInstance();
  }

  Future<int> sync(FakeServer s, {void Function()? onChanged}) async {
    final p = await use();
    var changed = 0;
    final report = await SyncEngine(SyncApi(s.url, token: 'T' * 43),
        onLocalChanged: () => changed++).run();
    onChanged?.call();
    data = {for (final k in p.getKeys()) k: p.get(k)!};
    expect(changed, report.pulled > 0 ? greaterThan(0) : 0);
    return report.pulled;
  }

  /// A change made in the app: a preference written.
  Future<void> edit(void Function(SharedPreferences p) f) async {
    final p = await use();
    f(p);
    await Future<void>.delayed(Duration.zero);
    data = {for (final k in p.getKeys()) k: p.get(k)!};
  }

  List<String> list(String k) =>
      List<String>.from((data[k] as List?) ?? const []);
  Map<String, dynamic> map(String k) =>
      jsonDecode(data[k] as String? ?? '{}') as Map<String, dynamic>;
}

void main() {
  late FakeServer server;
  setUp(() async {
    server = FakeServer();
    await server.start();
  });
  tearDown(() => server.stop());

  test('a new device receives what the first one saved', () async {
    final a = Device({
      'favorites': ['movie:1', 'movie:2'],
      'positions': jsonEncode({'movie:1': 60000}),
      'language': 'it',
      'speed': 1.5,
      'autoResume': false,
      'seekSecs': 30,
    });
    await a.sync(server);
    final b = Device();
    final pulled = await b.sync(server);
    expect(pulled, greaterThan(0));
    expect(b.list('favorites'), ['movie:1', 'movie:2']);
    expect(b.map('positions'), {'movie:1': 60000});
    expect(b.data['language'], 'it');
    expect(b.data['speed'], 1.5);
    expect(b.data['autoResume'], false);
    expect(b.data['seekSecs'], 30);
  });

  test('a second sync with nothing new does nothing', () async {
    final a = Device({
      'favorites': ['x']
    });
    await a.sync(server);
    final before = server.items['favorites']!.rev;
    expect(await a.sync(server), 0);
    expect(server.items['favorites']!.rev, before);
  });

  test('two devices that each add something while apart end up with both',
      () async {
    final a = Device({
      'favorites': ['base']
    });
    await a.sync(server);
    final b = Device();
    await b.sync(server);
    await a.edit((p) => p.setStringList('favorites', ['base', 'from-a']));
    await b.edit((p) => p.setStringList('favorites', ['base', 'from-b']));
    await a.sync(server);
    await b.sync(server);
    await a.sync(server);
    expect(a.list('favorites').toSet(), {'base', 'from-a', 'from-b'});
    expect(b.list('favorites').toSet(), {'base', 'from-a', 'from-b'});
  });

  test('removing something on one device removes it on the other', () async {
    final a = Device({
      'favorites': ['keep', 'drop']
    });
    await a.sync(server);
    final b = Device();
    await b.sync(server);
    await a.edit((p) => p.setStringList('favorites', ['keep']));
    await a.sync(server);
    await b.sync(server);
    expect(b.list('favorites'), ['keep']);
  });

  test('resume positions of different titles both survive', () async {
    final a = Device({
      'positions': jsonEncode({'movie:1': 1000})
    });
    await a.sync(server);
    final b = Device();
    await b.sync(server);
    await a.edit((p) => p.setString(
        'positions', jsonEncode({'movie:1': 1000, 'movie:2': 2000})));
    await b
        .edit((p) => p.setString('positions', jsonEncode({'movie:1': 5000})));
    await a.sync(server);
    await b.sync(server);
    await a.sync(server);
    expect(a.map('positions'), {'movie:1': 5000, 'movie:2': 2000});
    expect(b.map('positions'), {'movie:1': 5000, 'movie:2': 2000});
  });

  test(
      'personal data of another profile has its own keys and syncs the same way',
      () async {
    final a = Device({
      'favorites:p1abc': ['kid-movie'],
      'profiles': jsonEncode([
        {'id': 'main', 'name': 'Main'},
        {'id': 'p1abc', 'name': 'Kids'}
      ])
    });
    await a.sync(server);
    final b = Device();
    await b.sync(server);
    expect(b.list('favorites:p1abc'), ['kid-movie']);
    expect((jsonDecode(b.data['profiles'] as String) as List).length, 2);
  });

  group('what stays on the device', () {
    test('device settings, recents and caches are neither sent nor received',
        () async {
      final a = Device({
        'tvMode': 'on',
        'uiScale': 1.3,
        'decoder': 'software',
        'lastLive': 'live:9',
        'startOnBoot': true,
        'recents': [
          jsonEncode({'id': '1', 'url': 'http://h/movie/u/SeCrEt/1.mp4'})
        ],
        'posterCache': '{}',
        'osPass': 'os-secret',
        'language': 'pt',
      });
      await a.sync(server);
      expect(server.items.keys, ['language']);
      final b = Device({
        'tvMode': 'off',
        'recents': ['mine']
      });
      await b.sync(server);
      expect(b.data['tvMode'], 'off');
      expect(b.list('recents'), ['mine']);
      expect(b.data['language'], 'pt');
    });

    test('no password reaches the server, from a login or from a playlist link',
        () async {
      final a = Device({
        'sources': [
          jsonEncode({
            'name': 'Panel',
            'type': 'xtream',
            'url': 'http://panel',
            'user': 'u',
            'pass': ''
          }),
          jsonEncode({
            'name': 'Link',
            'type': 'm3u',
            'url': 'http://h/get.php?username=u&password=SeCrEt&type=m3u_plus',
            'user': '',
            'pass': ''
          }),
        ],
        'active': 'Panel',
      });
      await a.sync(server);
      expect(server.everything.contains('SeCrEt'), isFalse);
      expect(server.everything.contains('password=&type'), isTrue);
      // The device that sent them still has its own address.
      expect(a.list('sources').join().contains('SeCrEt'), isTrue);

      final b = Device();
      await b.sync(server);
      final got = [
        for (final s in b.list('sources')) jsonDecode(s) as Map<String, dynamic>
      ];
      expect(got.map((e) => e['name']), ['Panel', 'Link']);
      expect(got.map((e) => e['pass']), ['', '']);
      expect(
          got[1]['url'], 'http://h/get.php?username=u&password=&type=m3u_plus');
      expect(b.data['active'], 'Panel');

      // The first device syncing again does not lose its own address to the blanked copy.
      await a.sync(server);
      expect(a.list('sources').join().contains('SeCrEt'), isTrue);
    });
  });

  test('a write that finds the key changed meanwhile is merged and sent again',
      () async {
    final a = Device({
      'favorites': ['mine']
    });
    server.conflictOnce.add('favorites');
    await a.sync(server);
    expect(a.list('favorites').toSet(), {'mine', 'from-another-device'});
    final stored =
        jsonDecode(server.items['favorites']!.value!) as Map<String, dynamic>;
    expect((stored['v'] as List).toSet(), {'mine', 'from-another-device'});
  });

  test('being signed out surfaces as such', () async {
    server.signedOut = true;
    final a = Device({
      'favorites': ['x']
    });
    await expectLater(
        a.sync(server),
        throwsA(isA<SyncException>()
            .having((e) => e.signedOut, 'signedOut', true)));
  });

  test('a server that is not there says so in words', () async {
    final url = server.url;
    await server.stop();
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    await expectLater(
      SyncEngine(SyncApi(url, token: 'T' * 43), onLocalChanged: () {}).run(),
      throwsA(isA<SyncException>()
          .having((e) => e.message, 'message', contains('Could not reach'))),
    );
    server = FakeServer()
      ..http = await HttpServer.bind(
          InternetAddress.loopbackIPv4, 0); // for tearDown
  });

  group('addresses', () {
    test('a bare name becomes https; a full address is kept; junk is refused',
        () {
      expect(SyncApi.normalizeServer('sync.example.com'),
          'https://sync.example.com');
      expect(SyncApi.normalizeServer(' http://192.168.1.5:8080/ '),
          'http://192.168.1.5:8080');
      expect(() => SyncApi.normalizeServer(''), throwsA(isA<SyncException>()));
      expect(() => SyncApi.normalizeServer('ftp://x'),
          throwsA(isA<SyncException>()));
    });
  });

  group('SyncState', () {
    late FlutterSecureStorage secure;
    setUp(() {
      secure = const FlutterSecureStorage();
    });

    test('signing in keeps the account, syncs, and signing out forgets it',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({
        'favorites': ['a'],
        'language': 'es'
      });
      final s = SyncState(secure: secure, deviceName: 'test');
      await s.init();
      expect(s.signedIn, isFalse);
      var reloaded = 0;
      s.reload = () => reloaded++;
      expect(
          await s.signIn(server.url, 'me@example.com', 'wrong password',
              create: false),
          contains('wrong'));
      expect(s.signedIn, isFalse);
      expect(
          await s.signIn(server.url, 'me@example.com', 'right password',
              create: false),
          isNull);
      expect(s.signedIn, isTrue);
      expect(s.email, 'me@example.com');
      expect(s.lastSync, isNotNull);
      expect(server.items.keys, containsAll(['favorites', 'language']));

      // A new run of the app is still signed in.
      final again = SyncState(secure: secure, deviceName: 'test');
      await again.init();
      expect(again.signedIn, isTrue);
      expect(again.server, server.url);

      await s.signOut();
      expect(s.signedIn, isFalse);
      final p = await SharedPreferences.getInstance();
      expect(p.containsKey('syncBase'), isFalse);
      final third = SyncState(secure: secure, deviceName: 'test');
      await third.init();
      expect(third.signedIn, isFalse);
    });

    test('a closed server does not let an account be created', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      server.registration = 'closed';
      final s = SyncState(secure: secure);
      await s.init();
      expect(
          await s.signIn(server.url, 'me@example.com', 'right password',
              create: true),
          contains('not accepting'));
      expect(s.signedIn, isFalse);
    });
  });
}
