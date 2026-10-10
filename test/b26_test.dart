import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/state/settings_state.dart';

void main() {
  test('Faster channel start is on by default and can be turned off', () async {
    SharedPreferences.setMockInitialValues({});
    final st = SettingsState();
    await st.init();
    expect(st.fastStart, isTrue);
    st.set('fastStart', false);
    expect(st.fastStart, isFalse);
    // and it is remembered
    final again = SettingsState();
    await again.init();
    expect(again.fastStart, isFalse);
  });
}
