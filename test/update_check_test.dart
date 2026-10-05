import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamboss/services/update_check.dart';

void main() {
  test('compareVersions', () {
    expect(compareVersions('0.2.0', '0.1.9') > 0, isTrue);
    expect(compareVersions('v1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.0.0-rc1', '1.0.0'), 0);
    expect(compareVersions('0.1.1', '0.1.10') < 0, isTrue);
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('2', '1.9.9') > 0, isTrue);
  });

  test('checkForUpdate reports newer / current / missing releases', () async {
    MockClient reply(int code, [Map<String, dynamic>? body]) =>
        MockClient((_) async => http.Response(jsonEncode(body ?? {}), code));

    final newer = await checkForUpdate('0.1.1',
        client: reply(200, {'tag_name': 'v0.2.0', 'html_url': 'http://r/0.2.0'}));
    expect(newer.newer, isTrue);
    expect(newer.latest, '0.2.0');
    expect(newer.url, 'http://r/0.2.0');

    final same = await checkForUpdate('0.2.0', client: reply(200, {'tag_name': 'v0.2.0'}));
    expect(same.newer, isFalse);

    expect(() => checkForUpdate('0.1.0', client: reply(404)), throwsException);
    expect(() => checkForUpdate('0.1.0', client: reply(500)), throwsException);
  });
}
