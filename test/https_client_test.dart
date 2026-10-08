import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/http_client_io.dart';

// Plain `test`s in their own file: once a widget test binding exists, flutter_test answers every
// HTTP request with a fake 400, so real loopback requests only work here.

void main() {
  late Directory tmp;
  late HttpServer server;
  late bool haveOpenssl;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('sb_tls');
    try {
      final r = await Process.run('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
        '-keyout', '${tmp.path}/k.pem', '-out', '${tmp.path}/c.pem',
        '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
      ]);
      haveOpenssl = r.exitCode == 0;
    } on ProcessException {
      haveOpenssl = false;
    }
    if (!haveOpenssl) return;
    final ctx = SecurityContext()
      ..useCertificateChain('${tmp.path}/c.pem')
      ..usePrivateKey('${tmp.path}/k.pem');
    // The client under test uses the default context, so trust the throwaway certificate there.
    SecurityContext.defaultContext.setTrustedCertificates('${tmp.path}/c.pem');
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
    server.listen((r) {
      r.response.write('#EXTM3U\n');
      r.response.close();
    });
  });

  tearDownAll(() async {
    if (haveOpenssl) await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  // Regression: HttpClient.connectionFactory returns a plain socket and Dart never upgrades it to TLS,
  // so every https URL got plaintext HTTP, and the server's TLS alert surfaced as
  // "Invalid request method". Free playlists (all https) and https providers failed on devices.
  test('the app client speaks TLS to https URLs', () async {
    if (!haveOpenssl) {
      markTestSkipped('openssl not available');
      return;
    }
    final c = makeHttpClient();
    final res =
        await c.get(Uri.parse('https://localhost:${server.port}/news.m3u'));
    expect(res.statusCode, 200);
    expect(res.body, startsWith('#EXTM3U'));
    c.close();
  });

  test('plain http still works', () async {
    final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    plain.listen((r) {
      r.response.write('ok');
      r.response.close();
    });
    final c = makeHttpClient();
    final res = await c.get(Uri.parse('http://127.0.0.1:${plain.port}/'));
    expect(res.body, 'ok');
    c.close();
    await plain.close(force: true);
  });
}
