import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/theme_picker.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/state/profiles_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

void main() {
  group('LayoutPalette.customized', () {
    test('changes only the accent when asked for only that', () {
      final p =
          LayoutPalette.marquee.customized(accent: const Color(0xFF2FBF8F));
      expect(p.accent, const Color(0xFF2FBF8F));
      expect(p.bg, LayoutPalette.marquee.bg);
      expect(
          p.onAccent,
          LayoutPalette.marquee
              .copyWith(accent: const Color(0xFF2FBF8F))
              .onAccent);
    });

    test('puts a background look over the layout\'s own colors', () {
      final p = LayoutPalette.marquee.customized(background: 'black');
      expect(p.bg, const Color(0xFF000000));
      expect(p.light, isFalse);
      expect(p.accent, LayoutPalette.marquee.accent);
    });

    test('Paper makes any layout light, with ink text', () {
      final p = LayoutPalette.control.customized(background: 'paper');
      expect(p.light, isTrue);
      expect(p.text, const Color(0xFF1B1B1F));
      expect(p.ring, p.text);
    });

    test('an unknown look, or keepBackground, leaves the layout alone', () {
      expect(LayoutPalette.hub.customized(background: 'nonsense').bg,
          LayoutPalette.hub.bg);
      expect(
          LayoutPalette.glass
              .customized(background: 'paper', keepBackground: true)
              .bg,
          LayoutPalette.glass.bg);
      expect(
          LayoutPalette.glass
              .customized(background: 'paper', keepBackground: true)
              .frosted,
          isTrue);
    });

    test('every look has a distinct, readable text on its background', () {
      for (final e in LayoutPalette.backgrounds.entries) {
        final bg = e.value.$2, text = e.value.$5;
        expect((bg.computeLuminance() - text.computeLuminance()).abs(),
            greaterThan(0.6),
            reason: e.key);
      }
    });
  });

  group('Boss.theme', () {
    LayoutPalette palette(ThemeData t) => t.extension<LayoutPalette>()!;

    test('carries the accent and background into the Material theme', () {
      final t = Boss.theme(
          layout: UiLayout.marquee,
          accent: const Color(0xFF4C8DFF),
          background: 'midnight');
      expect(palette(t).accent, const Color(0xFF4C8DFF));
      expect(t.colorScheme.primary, const Color(0xFF4C8DFF));
      expect(t.scaffoldBackgroundColor, const Color(0xFF0A0F1F));
    });

    test('Paper switches the Material theme to light', () {
      final t = Boss.theme(layout: UiLayout.marquee, background: 'paper');
      expect(t.brightness, Brightness.light);
      expect(t.scaffoldBackgroundColor, const Color(0xFFF7F5F0));
    });

    test('layouts that paint their own backdrop keep it, and take the accent',
        () {
      for (final l in [UiLayout.glass, UiLayout.mood, UiLayout.mosaic]) {
        final t = Boss.theme(
            layout: l, accent: const Color(0xFFD946EF), background: 'paper');
        expect(palette(t).bg, LayoutPalette.forLayout(l).bg, reason: l.name);
        expect(palette(t).accent, const Color(0xFFD946EF), reason: l.name);
      }
    });

    test('the defaults are the layout\'s own colors', () {
      for (final l in UiLayout.values) {
        expect(palette(Boss.theme(layout: l)).accent,
            LayoutPalette.forLayout(l).accent,
            reason: l.name);
      }
    });
  });

  group('settings', () {
    test(
        'default to the layout\'s colors, validate, persist and are per-profile keys',
        () async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      expect(st.accent, isNull);
      expect(st.background, 'layout');
      st.set('accentColor', 0xFF2FBF8F);
      st.set('background', 'plum');
      expect(st.accent, const Color(0xFF2FBF8F));
      final again = SettingsState();
      await again.init();
      expect(again.accent, const Color(0xFF2FBF8F));
      expect(again.background, 'plum');
      expect(SettingsState.profileKeys,
          containsAll(['accentColor', 'background']));
      expect(SettingsState.deviceKeys, isNot(contains('accentColor')));
    });

    test('a profile with its own settings can have its own colors', () async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final ps = ProfilesState();
      await ps.init();
      st.bindProfiles(ps);
      final kid = ps.add('Sam');
      ps.select(kid.id);
      ps.update(kid.copyWith(ownSettings: true));
      st.set('accentColor', 0xFFFF6A3D);
      st.set('background', 'forest');
      ps.select('main');
      expect(st.accent, isNull);
      expect(st.background, 'layout');
      ps.select(kid.id);
      expect(st.accent, const Color(0xFFFF6A3D));
      expect(st.background, 'forest');
    });
  });

  group('the picker', () {
    Future<SettingsState> pump(WidgetTester t,
        {String layout = 'marquee'}) async {
      SharedPreferences.setMockInitialValues({'layout': layout});
      final st = SettingsState();
      await st.init();
      t.view.physicalSize = const Size(900, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider.value(
        value: st,
        child: Consumer<SettingsState>(
          builder: (_, s, __) => MaterialApp(
            theme: Boss.theme(
                layout: s.layout, accent: s.accent, background: s.background),
            home: const Scaffold(
                body: SingleChildScrollView(child: ThemePicker())),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return st;
    }

    testWidgets('a swatch sets the accent, the first one clears it', (t) async {
      final st = await pump(t);
      await t.tap(find.bySemanticsLabel('Accent color ff2fbf8f'));
      await t.pumpAndSettle();
      expect(st.accent, const Color(0xFF2FBF8F));
      await t.tap(find.bySemanticsLabel("The layout's own accent"));
      await t.pumpAndSettle();
      expect(st.accent, isNull);
    });

    testWidgets('the hue slider makes a custom accent', (t) async {
      final st = await pump(t);
      await t.drag(find.byType(Slider), const Offset(120, 0));
      await t.pumpAndSettle();
      expect(st.accent, isNotNull);
    });

    testWidgets('a background chip sets the look and the app takes it',
        (t) async {
      final st = await pump(t);
      await t.tap(find.text('Paper'));
      await t.pumpAndSettle();
      expect(st.background, 'paper');
      expect(Theme.of(t.element(find.byType(ThemePicker))).brightness,
          Brightness.light);
      await t.tap(find.text('Layout'));
      await t.pumpAndSettle();
      expect(st.background, 'layout');
    });

    testWidgets('says so when the layout paints its own backdrop', (t) async {
      await pump(t, layout: 'glass');
      expect(find.textContaining('paints its own backdrop'), findsOneWidget);
    });
  });
}
