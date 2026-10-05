import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/provider_url.dart';

void main() {
  test(
      'a failed DNS lookup is explained, names the host and does not suggest the decoder',
      () {
    final f = friendlyPlayerError(
        'tcp: Failed to resolve hostname cf.mytv-online.me: No address associated with hostname');
    expect(f.message, contains("'cf.mytv-online.me'"));
    expect(f.message, contains('Private DNS'));
    expect(f.decoderAdvice, false);
  });

  test('other network failures are passed through without decoder advice', () {
    final f = friendlyPlayerError('tcp: Connection refused');
    expect(f.message, 'tcp: Connection refused');
    expect(f.decoderAdvice, false);
  });

  test('unknown errors keep the decoder advice', () {
    final f = friendlyPlayerError('Could not open codec.');
    expect(f.message, 'Could not open codec.');
    expect(f.decoderAdvice, true);
  });
}
