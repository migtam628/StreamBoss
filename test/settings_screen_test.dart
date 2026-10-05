import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/app_info.dart';
import 'package:streamboss/screens/settings_screen.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

Future<SettingsState> pump(WidgetTester t, Size size) async {
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
      appName: 'StreamBoss', packageName: 'x', version: '1.2.3', buildNumber: '4', buildSignature: '');
  final st = SettingsState();
  await st.init();
  final app = AppState();
  app.bindSettings(st);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<SettingsState>.value(value: st),
    ],
    child: MaterialApp(theme: Boss.theme(), home: const Scaffold(body: SettingsScreen())),
  ));
  await t.pumpAndSettle();
  return st;
}

void main() {
  testWidgets('wide layout shows the sections and the selected page side by side', (t) async {
    await pump(t, const Size(1200, 900));
    expect(find.text('Source & library'), findsWidgets);
    expect(find.text('CURRENT SOURCE'), findsOneWidget);
    await t.tap(find.text('Library & guide'));
    await t.pumpAndSettle();
    expect(find.text('Hide adult categories'), findsOneWidget);
  });

  testWidgets('toggles write through to SettingsState', (t) async {
    final st = await pump(t, const Size(1200, 900));
    await t.tap(find.text('Library & guide'));
    await t.pumpAndSettle();
    expect(st.sortAz, false);
    await t.tap(find.text('Sort A–Z'));
    await t.pumpAndSettle();
    expect(st.sortAz, true);
  });

  testWidgets('narrow layout opens a section as its own page', (t) async {
    await pump(t, const Size(420, 900));
    expect(find.text('CURRENT SOURCE'), findsNothing);
    await t.tap(find.text('Appearance'));
    await t.pumpAndSettle();
    expect(find.text('LAYOUT'), findsOneWidget);
    expect(find.text('Marquee'), findsOneWidget);
  });

  testWidgets('about page shows the app version', (t) async {
    await pump(t, const Size(1200, 900));
    await t.tap(find.text('About'));
    await t.pumpAndSettle();
    expect(find.text('${appVersion('1.2.3')} (build 4)'), findsOneWidget);
  });

  testWidgets('reset all settings restores defaults after confirming', (t) async {
    final st = await pump(t, const Size(1200, 900));
    st.set('sortAz', true);
    await t.tap(find.text('Data & backup'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reset all settings'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reset'));
    await t.pumpAndSettle();
    expect(st.sortAz, false);
  });
}
