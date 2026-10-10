import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/screens/settings/settings_pages.dart';
import 'package:streamboss/services/app_icon.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

const _channel = MethodChannel('com.streamboss/app_icon');

Future<SettingsState> pump(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  final st = SettingsState();
  await st.init();
  final app = AppState()..bindSettings(st);
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<SettingsState>.value(value: st),
    ],
    child: MaterialApp(theme: Boss.theme(), home: const Scaffold(body: AppearancePage())),
  ));
  await t.pumpAndSettle();
  return st;
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('the icon list stays in step everywhere', () {
    final names = AppIcon.values.map((e) => e.name).toList();

    test('every icon has its previews and Android resources', () {
      for (final n in names) {
        for (final f in [
          'assets/app_icons/$n.png',
          'tool/android_res/mipmap-anydpi-v26/ic_logo_$n.xml',
          'tool/android_res/mipmap-anydpi-v26/ic_logo_${n}_round.xml',
          'tool/android_res/mipmap-xxxhdpi/ic_logo_$n.png',
          'tool/android_res/mipmap-xxxhdpi/ic_logo_${n}_round.png',
          'tool/android_res/drawable-xxxhdpi/ic_logo_${n}_fg.png',
          'tool/android_res/drawable-nodpi/ic_logo_${n}_bg.png',
          'tool/android_res/drawable-nodpi/ic_logo_${n}_mono.png',
          'tool/android_res/drawable-xhdpi/banner_$n.png',
        ]) {
          expect(File(f).existsSync(), isTrue, reason: f);
        }
      }
    });

    test('the Android patch script lists the same icons', () {
      final src = File('tool/patch_android.dart').readAsStringSync();
      final dart = RegExp(r"const _iconNames = \[([^\]]*)\]").firstMatch(src)![1]!;
      final kotlin = RegExp(r'private val iconNames = listOf\(([^)]*)\)').firstMatch(src)![1]!;
      List<String> parse(String s) => RegExp("[a-z]+").allMatches(s).map((m) => m[0]!).toList();
      expect(parse(dart), names);
      expect(parse(kotlin), names);
    });

    test('an unknown key falls back to the first icon', () {
      expect(AppIcon.fromKey('nonsense'), AppIcon.crown);
      expect(AppIcon.fromKey(null), AppIcon.crown);
      expect(AppIcon.fromKey('screen'), AppIcon.screen);
    });
  });

  group('the picker', () {
    testWidgets('on Android it shows the four icons, follows the system and changes the icon', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (c) async {
        calls.add(c);
        return c.method == 'current' ? 'bold' : true;
      });
      final st = await pump(t);
      await t.scrollUntilVisible(find.text('APP ICON'), 400, scrollable: find.byType(Scrollable).first);
      expect(find.text('APP ICON'), findsOneWidget);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -250));
      await t.pumpAndSettle();
      for (final i in AppIcon.values) {
        expect(find.text(i.label), findsOneWidget, reason: i.label);
      }
      // The launcher said Bold B is active, so the setting follows it.
      expect(st.appIcon, 'bold');

      await t.drag(find.byType(Scrollable).first, const Offset(0, -150)); // clear the bottom edge
      await t.pumpAndSettle();
      await t.tap(find.text('Signal'));
      await t.pumpAndSettle();
      expect(calls.last.method, 'set');
      expect(calls.last.arguments, 'signal');
      expect(st.appIcon, 'signal');
      expect(find.textContaining('Signal icon set'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null; // before the framework checks its invariants
    });

    testWidgets('a refused change keeps the old icon and says so', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (c) async => c.method == 'current' ? 'crown' : false);
      final st = await pump(t);
      await t.scrollUntilVisible(find.text('Screen'), 400, scrollable: find.byType(Scrollable).first);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -150));
      await t.pumpAndSettle();
      await t.tap(find.text('Screen'));
      await t.pumpAndSettle();
      expect(st.appIcon, 'crown');
      expect(find.textContaining('could not be changed'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('where the icon is fixed at install, there is no picker', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await pump(t);
      await t.scrollUntilVisible(find.text('SIZE'), 400, scrollable: find.byType(Scrollable).first); // the section after where the picker would be
      expect(find.text('APP ICON'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
