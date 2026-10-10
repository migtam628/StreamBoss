import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/main.dart' show needsOnboarding;
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/onboarding_screen.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

Future<SettingsState> settings([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final st = SettingsState();
  await st.init();
  return st;
}

Future<void> pumpWizard(WidgetTester t, SettingsState st, VoidCallback onDone,
    {bool rerun = false}) async {
  t.view.physicalSize = const Size(900, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<SettingsState>.value(
    value: st,
    child: Consumer<SettingsState>(
      builder: (_, s, __) => MaterialApp(
        theme: Boss.theme(layout: s.layout),
        home: OnboardingScreen(onDone: onDone, rerun: rerun),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('when the wizard shows', () {
    test('only on a device that has not onboarded and has no provider',
        () async {
      final st = await settings();
      final app = AppState()..bindSettings(st);
      expect(needsOnboarding(st, app), true);
      st.set('onboarded', true);
      expect(needsOnboarding(st, app), false);
    });

    test('never for someone who already has a provider', () async {
      final st = await settings();
      final app = AppState()..bindSettings(st);
      app.sources = [
        const Source(name: 'Mine', type: SourceType.m3u, url: 'http://x/list.m3u')
      ];
      expect(needsOnboarding(st, app), false);
    });

    test('is remembered per device, not restored from a backup', () async {
      final st = await settings();
      expect(SettingsState.deviceKeys, contains('onboarded'));
      st.applyMap({'onboarded': true});
      expect(st.onboarded, false);
    });
  });

  testWidgets(
      'walks the five steps, applying choices as they are made, and finishes',
      (t) async {
    final st = await settings();
    var done = 0;
    await pumpWizard(t, st, () => done++);

    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();

    expect(find.text('Your screen'), findsOneWidget);
    await t.tap(find.text('TV'));
    await t.pumpAndSettle();
    expect(st.tvMode, 'on');
    expect(find.text('HOW MUCH FITS ON THE TV'), findsOneWidget);
    await t.tap(find.text('Large'));
    await t.pumpAndSettle();
    expect(st.uiScale, 1.15);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();

    expect(find.text('Pick a look'), findsOneWidget);
    await t.ensureVisible(find.text('Wall'));
    await t.tap(find.text('Wall'));
    await t.pumpAndSettle();
    expect(st.layout, UiLayout.wall);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();

    expect(find.text('Playback'), findsOneWidget);
    await t.tap(find.text('Spanish'));
    await t.pumpAndSettle();
    expect(st.audioLang, 'es,spa');
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(st.subsOn, false);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();

    expect(find.text('Connect your provider'), findsOneWidget);
    expect(done, 0);
    await t.tap(find.text('Connect my provider'));
    await t.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('Back goes to the previous step', (t) async {
    final st = await settings();
    await pumpWizard(t, st, () {});
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('Your screen'), findsOneWidget);
    await t.tap(find.text('Back'));
    await t.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('Skip setup finishes straight away', (t) async {
    final st = await settings();
    var done = 0;
    await pumpWizard(t, st, () => done++);
    await t.tap(find.text('Skip setup'));
    await t.pumpAndSettle();
    expect(done, 1);
  });

  testWidgets('opened again from Settings it ends with Done, not Connect',
      (t) async {
    final st = await settings();
    await pumpWizard(t, st, () {}, rerun: true);
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
    }
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Connect my provider'), findsNothing);
  });
}
