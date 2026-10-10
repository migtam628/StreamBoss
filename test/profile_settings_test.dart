import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/profiles_state.dart';
import 'package:streamboss/state/settings_state.dart';

Future<(SettingsState, ProfilesState)> setup(
    [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({...prefs});
  final st = SettingsState();
  await st.init();
  final ps = ProfilesState();
  await ps.init();
  st.bindProfiles(ps);
  return (st, ps);
}

void main() {
  group('a profile with its own settings', () {
    test('starts from what is in use, so turning it on changes nothing',
        () async {
      final (st, ps) = await setup({'layout': 'glass', 'uiScale': 1.15});
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      expect(st.hasProfileOverlay, isTrue);
      expect(st.layout, UiLayout.glass);
      expect(st.uiScale, 1.15);
    });

    test('changes stay with that profile and the others keep theirs', () async {
      final (st, ps) = await setup({'layout': 'glass'});
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      st.set('layout', 'mosaic');
      st.set('uiScale', 1.3);
      expect(st.layout, UiLayout.mosaic);
      ps.select('main');
      expect(st.hasProfileOverlay, isFalse);
      expect(st.layout, UiLayout.glass);
      expect(st.uiScale, 1.0);
      ps.select(kid.id);
      expect(st.layout, UiLayout.mosaic);
      expect(st.uiScale, 1.3);
    });

    test('device settings stay shared even inside such a profile', () async {
      final (st, ps) = await setup();
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      st.set('tvMode', 'on');
      st.set('decoder', 'software');
      ps.select('main');
      expect(st.tvMode, 'on');
      expect(st.decoder, 'software');
    });

    test('are kept across a restart', () async {
      final (st, ps) = await setup();
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      st.set('subLang', 'es,spa');
      st.set('hideAdult', true);

      final st2 = SettingsState();
      await st2.init();
      final ps2 = ProfilesState();
      await ps2.init();
      st2.bindProfiles(ps2);
      expect(ps2.current.name, 'Sam');
      expect(st2.subLang, 'es,spa');
      expect(st2.hideAdult, isTrue);
      ps2.select('main');
      expect(st2.subLang, '');
      expect(st2.hideAdult, isFalse);
    });

    test(
        'turning it off goes back to the shared settings and forgets the own ones',
        () async {
      final (st, ps) = await setup();
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      st.set('posterSize', 1.25);
      ps.update(ps.current.copyWith(ownSettings: false));
      expect(st.hasProfileOverlay, isFalse);
      expect(st.posterSize, 1.0);
      expect(
          (await SharedPreferences.getInstance())
              .getString('profileSettings:${kid.id}'),
          isNull);
      // Switching it on again starts fresh from the shared settings.
      ps.update(ps.current.copyWith(ownSettings: true));
      expect(st.posterSize, 1.0);
    });

    test('moving between two profiles with their own settings swaps them',
        () async {
      final (st, ps) = await setup();
      final a = ps.add('A');
      final b = ps.add('B');
      ps.select(a.id);
      ps.update(a.copyWith(ownSettings: true));
      st.set('layout', 'bento');
      ps.select(b.id);
      ps.update(b.copyWith(ownSettings: true));
      st.set('layout', 'wall');
      ps.select(a.id);
      expect(st.layout, UiLayout.bento);
      ps.select(b.id);
      expect(st.layout, UiLayout.wall);
    });

    test('a backup carries the shared settings, not a profile\'s own',
        () async {
      final (st, ps) = await setup();
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      st.set('uiScale', 1.3);
      expect(st.toMap()['uiScale'], 1.0);
    });

    test('Reset to defaults clears the own settings of the profile in use too',
        () async {
      final (st, ps) = await setup();
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      st.set('uiScale', 1.3);
      expect(st.isDefault('uiScale'), isFalse);
      st.resetAll();
      expect(st.uiScale, 1.0);
      expect(st.isDefault('uiScale'), isTrue);
    });

    test('a deleted profile takes its settings with it', () async {
      final (st, ps) = await setup();
      final app = AppState();
      await app.init();
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      st.set('uiScale', 1.3);
      ps.select('main');
      ps.remove(kid.id);
      await app.forgetProfile(kid.id);
      expect(
          (await SharedPreferences.getInstance())
              .getString('profileSettings:${kid.id}'),
          isNull);
    });
  });
}
