import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/provider_url.dart';

void main() {
  test('extracts server and credentials from a pasted playlist link', () {
    final l = parseProviderLink('http://example.test:8080/get.php?username=u1&password=p%401&type=m3u_plus&output=ts')!;
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
    const e = "ClientException with SocketFailed host lookup: 'x' uri=http://x/get.php?username=abc&password=def&type=m3u";
    final r = redactSecrets(e);
    expect(r, isNot(contains('abc')));
    expect(r, isNot(contains('def')));
    expect(r, contains('username=***'));
    expect(r, contains('type=m3u'));
  });

  test('DNS failures get an actionable message without secrets', () {
    final m = friendlyError(Exception("ClientException with SocketFailed host lookup: 'host.test' (OS Error: x), uri=http://host.test/get.php?username=a&password=b"));
    expect(m, startsWith("Couldn't look up 'host.test'"));
    expect(m, isNot(contains('password')));
  });
}
