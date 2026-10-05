import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/pairing_io.dart';

Future<(int, String)> _post(PairingSession s, Map<String, String> form) async {
  final c = HttpClient();
  try {
    final req = await c.postUrl(Uri.parse('${s.url}/add'));
    req._write(form);
    final res = await req.close();
    return (res.statusCode, await res.transform(utf8.decoder).join());
  } finally {
    c.close(force: true);
  }
}

extension on HttpClientRequest {
  void _write(Map<String, String> f) {
    headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    write(f.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));
  }
}

void main() {
  late PairingSession s;
  setUp(() async => s = (await startPairing(host: '127.0.0.1'))!);
  tearDown(() => s.close());

  test('serves a form without revealing the PIN, and the PIN is 4 digits', () async {
    expect(s.pin, matches(RegExp(r'^\d{4}$')));
    final c = HttpClient();
    final res = await (await c.getUrl(Uri.parse(s.url))).close();
    final body = await res.transform(utf8.decoder).join();
    c.close();
    expect(res.statusCode, 200);
    expect(body, contains('<form'));
    expect(body, isNot(contains(s.pin)));
  });

  test('a correct Xtream login arrives as a Source', () async {
    final got = s.sources.first;
    final (code, body) = await _post(s, {'pin': s.pin, 'type': 'xtream', 'name': 'Home', 'url': 'host.test:8080', 'user': 'u', 'pass': 'p w'});
    expect(code, 200);
    expect(body, contains('Sent to your TV'));
    final src = await got.timeout(const Duration(seconds: 2));
    expect(src.type, SourceType.xtream);
    expect(src.name, 'Home');
    expect(src.url, 'http://host.test:8080');
    expect(src.username, 'u');
    expect(src.password, 'p w');
  });

  test('a pasted get.php link fills in the login; M3U keeps just the link', () async {
    final first = s.sources.first;
    await _post(s, {'pin': s.pin, 'type': 'xtream', 'url': 'http://h.test:25461/get.php?username=aa&password=bb&type=m3u_plus'});
    final a = await first;
    expect((a.url, a.username, a.password), ('http://h.test:25461', 'aa', 'bb'));

    final second = s.sources.first;
    await _post(s, {'pin': s.pin, 'type': 'm3u', 'url': 'https://h.test/list.m3u?token=1', 'user': 'ignored'});
    final b = await second;
    expect(b.type, SourceType.m3u);
    expect(b.url, 'https://h.test/list.m3u?token=1');
    expect(b.username, '');
  });

  test('wrong PIN is refused and nothing is delivered; five misses lock the session', () async {
    var delivered = false;
    s.sources.listen((_) => delivered = true);
    final base = {'type': 'xtream', 'url': 'http://h.test', 'user': 'u', 'pass': 'p'};
    for (var i = 0; i < 5; i++) {
      final (code, body) = await _post(s, {...base, 'pin': '0000x'});
      expect(code, 403);
      expect(body, contains(i < 4 ? 'Wrong PIN' : 'Too many wrong PINs'));
    }
    final (code, _) = await _post(s, {...base, 'pin': s.pin});
    expect(code, 429, reason: 'locked even with the right PIN');
    expect(delivered, false);
  });

  test('bad input is rejected with a message', () async {
    var (code, body) = await _post(s, {'pin': s.pin, 'type': 'xtream', 'url': 'ftp://h.test', 'user': 'u', 'pass': 'p'});
    expect(code, 400);
    expect(body, contains('does not look right'));
    (code, body) = await _post(s, {'pin': s.pin, 'type': 'xtream', 'url': 'http://h.test'});
    expect(code, 400);
    expect(body, contains('username and password'));
  });

  test('HTML in the form is escaped, not executed', () async {
    final (_, body) = await _post(s, {'pin': 'bad', 'url': '<script>x</script>'});
    expect(body, isNot(contains('<script>x')));
  });

  test('close stops the server', () async {
    final url = Uri.parse(s.url);
    await s.close();
    await expectLater(
      HttpClient().getUrl(url).then((r) => r.close()),
      throwsA(isA<SocketException>()),
    );
  });

  test('the session ends by itself after its lifetime', () async {
    final short = (await startPairing(host: '127.0.0.1', lifetime: const Duration(milliseconds: 150)))!;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await expectLater(HttpClient().getUrl(Uri.parse(short.url)).then((r) => r.close()), throwsA(isA<SocketException>()));
  });
}
