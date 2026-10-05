import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/http_client.dart';

void main() {
  late HttpServer server;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) {
      r.response
        ..statusCode = 200
        ..write('hi')
        ..close();
    });
  });
  tearDown(() => server.close(force: true));

  test('the shared client reaches a server over IPv4', () async {
    final res =
        await appHttp.get(Uri.parse('http://localhost:${server.port}/x'));
    expect(res.statusCode, 200);
    expect(res.body, 'hi');
  });

  test(
      'diagnoseConnection reports DNS, connect and HTTP steps without credentials',
      () async {
    final out = await diagnoseConnection(
        Uri.parse(
            'http://localhost:${server.port}/get.php?username=u&password=secret'),
        appHttp);
    expect(out, contains('DNS IPv4'));
    expect(out, contains('Connect 127.0.0.1: ok'));
    expect(out, contains('HTTP GET /: 200'));
    expect(out, isNot(contains('secret')));
  });

  test('a refused connection surfaces the IPv4 error', () async {
    final port = server.port;
    await server.close(force: true);
    await expectLater(
      appHttp.get(Uri.parse('http://127.0.0.1:$port/')),
      throwsA(predicate((e) => e.toString().contains('Connection refused'))),
    );
    server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0); // for tearDown
  });
}
