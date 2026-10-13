import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/provider_url.dart';

void main() {
  test('extracts server and credentials from a pasted playlist link', () {
    final l = parseProviderLink(
        'http://example.test:8080/get.php?username=u1&password=p%401&type=m3u_plus&output=ts')!;
    expect(l.server, 'http://example.test:8080');
    expect(l.username, 'u1');
    expect(l.password, 'p@1');
  });

  test('plain server addresses are left alone', () {
    expect(parseProviderLink('http://example.test:8080'), isNull);
    expect(parseProviderLink('example.test'), isNull);
    expect(parseProviderLink(''), isNull);
  });

  test('credentials are redacted from error text', () {
    const e =
        "ClientException with SocketFailed host lookup: 'x' uri=http://x/get.php?username=abc&password=def&type=m3u";
    final r = redactSecrets(e);
    expect(r, isNot(contains('abc')));
    expect(r, isNot(contains('def')));
    expect(r, contains('username=***'));
    expect(r, contains('type=m3u'));
  });

  test('DNS failures get an actionable message without secrets', () {
    final m = friendlyError(Exception(
        "ClientException with SocketFailed host lookup: 'host.test' (OS Error: x), uri=http://host.test/get.php?username=a&password=b"));
    expect(m, startsWith("Couldn't look up 'host.test'"));
    expect(m, isNot(contains('password')));
  });

  test('explains an unreachable network without leaking credentials', () {
    final m = friendlyError(Exception(
        'ClientException with SocketNetwork is unreachable (OS Error: Network is unreachable, errno = 51), '
        'address = cf.host.test, port = 56789, uri=http://cf.host.test/player_api.php?username=u&password=p'));
    expect(m, contains("can't reach 'cf.host.test'"));
    expect(m, isNot(contains('password')));
  });

  group('what a browser blocks', () {
    const guide = 'ClientException: Failed to fetch, uri=https://worker.example.com/guide.xml.gz';
    const plain = 'ClientException: Failed to fetch, uri=http://cf.host.test/player_api.php?username=u&password=p';

    test('a server that does not allow websites is named, with what to do', () {
      final m = friendlyError(Exception(guide), web: true, secure: true);
      expect(m, contains("'worker.example.com'"));
      expect(m, contains('does not allow websites'));
      expect(m, contains('StreamBoss app'));
    });

    test('a plain http address on a secure page is said to be that', () {
      final m = friendlyError(Exception(plain), web: true, secure: true);
      expect(m, contains("'cf.host.test'"));
      expect(m, contains('plain http'));
      expect(m, isNot(contains('password')));
    });

    test('the same address on a page that is not secure is not called blocked for http', () {
      final m = friendlyError(Exception(plain), web: true, secure: false);
      expect(m, isNot(contains('plain http')));
    });

    test('outside a browser the text is left as it was', () {
      final m = friendlyError(Exception(guide), web: false);
      expect(m, isNot(contains('browser')));
    });
  });
}
