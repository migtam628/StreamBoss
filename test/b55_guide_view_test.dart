import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/services/guide_view.dart';
import 'package:streamboss/state/settings_state.dart';

void main() {
  test('the saved name gives the view, and anything unknown is compact', () {
    expect(parseGuideView('theater'), GuideView.theater);
    expect(parseGuideView('off'), GuideView.off);
    expect(parseGuideView('nope'), GuideView.compact);
    expect(parseGuideView(null), GuideView.compact);
  });

  test('compact keeps the size the Guide always had', () {
    expect(guideVideoSize(GuideView.compact, maxWidth: 1000, screenHeight: 800).width, 220);
    expect(guideVideoSize(GuideView.compact, maxWidth: 300, screenHeight: 800).width, 128);
  });

  test('large and theater stay under their share of the screen height', () {
    for (final h in [360.0, 600.0, 900.0, 1400.0]) {
      final l = guideVideoSize(GuideView.large, maxWidth: 1200, screenHeight: h);
      expect(l.height, lessThanOrEqualTo(h * 0.38 + 0.001));
      expect((l.width / l.height - 16 / 9).abs(), lessThan(0.001));
      final t = guideVideoSize(GuideView.theater, maxWidth: 1200, screenHeight: h);
      expect(t.height, lessThanOrEqualTo(h * 0.42 + 0.001));
      expect(t.width, 1200);
    }
    expect(guideVideoSize(GuideView.large, maxWidth: 1200, screenHeight: 2000).width, 560);
    expect(guideVideoSize(GuideView.large, maxWidth: 1200, screenHeight: 800).width,
        greaterThan(guideVideoSize(GuideView.compact, maxWidth: 1200, screenHeight: 800).width));
  });

  test('hidden takes no room', () {
    final z = guideVideoSize(GuideView.off, maxWidth: 1000, screenHeight: 800);
    expect((z.width, z.height), (0, 0));
  });

  test('the view is saved with the settings', () async {
    SharedPreferences.setMockInitialValues({});
    final st = SettingsState();
    expect(st.guideView, 'compact');
    st.set('guideView', GuideView.theater.name);
    expect(parseGuideView(st.guideView), GuideView.theater);
  });
}
