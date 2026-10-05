import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamboss/services/update_check.dart';

void main() {
  test('compareVersions', () {
    expect(compareVersions('0.2.0', '0.1.9') > 0, isTrue);
    expect(compareVersions('v1.0.0', '1.0.0'), 0);
    expect(compareVersions('0.1.1', '0.1.10') < 0, isTrue);
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('2', '1.9.9') > 0, isTrue);
  });

  test('betas order before their release: b1 < b2 < rc1 < release < next b1', () {
    const order = ['0.3.0b1', '0.3.0b2', '0.3.0b10', '0.3.0-rc1', '0.3.0', '0.3.1b1', '0.3.1'];
    for (var i = 0; i < order.length; i++) {
      for (var j = 0; j < order.length; j++) {
        expect(compareVersions(order[i], order[j]).sign, i.compareTo(j), reason: '${order[i]} vs ${order[j]}');
      }
    }
    expect(compareVersions('0.3.0-beta.2', '0.3.0b2'), 0, reason: 'b2 and -beta.2 are the same thing');
    expect(compareVersions('v0.3.0b2+7', '0.3.0b2'), 0, reason: 'build metadata is ignored');
    expect(isPrerelease('0.3.0b2'), isTrue);
    expect(isPrerelease('0.3.0'), isFalse);
  });

  test('a stable build ignores betas; a beta build is offered newer betas and the final release', () async {
    final list = jsonEncode([
      {'tag_name': 'v0.3.0b2', 'html_url': 'http://r/b2', 'prerelease': true},
      {'tag_name': 'v0.3.0b1', 'html_url': 'http://r/b1', 'prerelease': true},
      {'tag_name': 'v0.2.3', 'html_url': 'http://r/0.2.3'},
      {'tag_name': 'v9.9.9', 'html_url': 'http://r/draft', 'draft': true},
    ]);
    final seen = <Uri>[];
    final client = MockClient((r) async {
      seen.add(r.url);
      // /releases/latest only ever returns the newest stable release
      return r.url.path.endsWith('/latest')
          ? http.Response(jsonEncode({'tag_name': 'v0.2.3', 'html_url': 'http://r/0.2.3'}), 200)
          : http.Response(list, 200);
    });

    final stable = await checkForUpdate('0.2.2', client: client);
    expect((stable.latest, stable.newer), ('0.2.3', true));
    expect(seen.last.path, endsWith('/releases/latest'));

    final onB1 = await checkForUpdate('0.3.0b1', client: client);
    expect((onB1.latest, onB1.newer, onB1.url), ('0.3.0b2', true, 'http://r/b2'));

    final onB2 = await checkForUpdate('0.3.0b2', client: client);
    expect(onB2.newer, isFalse, reason: 'drafts are ignored');
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
