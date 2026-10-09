import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/state/settings_state.dart';

void main() {
  test('OpenSubtitles details stay out of backups', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsState();
    await s.init();
    s.set('osKey', 'k');
    s.set('osUser', 'u');
    s.set('osPass', 'p');
    final m = s.toMap();
    expect(m.containsKey('osKey'), isFalse);
    expect(m.containsKey('osUser'), isFalse);
    expect(m.containsKey('osPass'), isFalse);
    expect(s.osKey, 'k');
  });
}
