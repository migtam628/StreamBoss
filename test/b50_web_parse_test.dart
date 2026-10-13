import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/catalog_cache.dart';

void main() {
  test(
      'a big library goes to an isolate, a small one does not, and the web app never does',
      () {
    expect(useIsolateFor(50 * 1024, web: false), isFalse);
    expect(useIsolateFor(200 * 1024, web: false), isTrue);
    expect(useIsolateFor(8 * 1024 * 1024, web: false), isTrue);
    expect(useIsolateFor(8 * 1024 * 1024, web: true), isFalse);
  });

  test('parseAway gives the job\'s answer, small or big', () async {
    expect(await parseAway('t', 10, () => 7), 7);
    expect(await parseAway('t', 500 * 1024, () => 8), 8);
  });
}
