import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/state/app_state.dart';

void main() {
  test('backup round-trips and never carries passwords', () {
    final a = AppState()
      ..sources = [const Source(name: 'P', type: SourceType.xtream, url: 'http://h', username: 'u', password: 'secret')]
      ..favorites.add('movie:1')
      ..positions['movie:1'] = 12345;
    final data = a.exportData();
    expect(data.toString().contains('secret'), isFalse);

    final b = AppState()..importData(data);
    expect(b.sources.single.name, 'P');
    expect(b.sources.single.password, '');
    expect(b.favorites, {'movie:1'});
    expect(b.positions['movie:1'], 12345);
  });
}
