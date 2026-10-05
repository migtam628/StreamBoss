import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/home_screen.dart';
import 'package:streamboss/screens/shell.dart';
import 'package:streamboss/widgets/media_tile.dart';
import 'package:streamboss/services/device.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/focus_card.dart';
import 'package:streamboss/widgets/tv.dart';

Future<SettingsState> settings([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final st = SettingsState();
  await st.init();
  return st;
}

void main() {
  tearDown(() => SettingsState.detectedTv = false);

  group('TV mode setting', () {
    test('auto follows detection; on and off override it', () async {
      final st = await settings();
      expect(st.isTv, false);
      SettingsState.detectedTv = true;
      expect(st.isTv, true);
      st.set('tvMode', 'off');
      expect(st.isTv, false);
      SettingsState.detectedTv = false;
      st.set('tvMode', 'on');
      expect(st.isTv, true);
    });

    test('TV mode no longer scales text or posters: the TV canvas sets the size', () async {
      final st = await settings();
      st.set('uiScale', 1.15);
      st.set('posterSize', 1.25);
      st.set('tvMode', 'on');
      expect(st.textScale, 1.15);
      expect(st.posterScale, 1.25);
      expect(st.tvWidth, 1280);
    });

    test('is reported in diagnostics but not restored from a backup', () async {
      final st = await settings();
      expect(st.toMap()['tvMode'], 'auto');
      st.applyMap({'tvMode': 'on', 'sortAz': true});
      expect(st.tvMode, 'auto');
      expect(st.sortAz, true);
    });
  });

  group('DeviceInfo', () {
    const channel = MethodChannel('com.streamboss/pip');
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      DeviceInfo.isTv = false;
    });

    test('asks Android whether it is a TV', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async => c.method == 'isTv' ? true : null);
      await DeviceInfo.init();
      expect(DeviceInfo.isTv, true);
    });

    test('falls back to not-a-TV when the channel fails, and never asks other platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async => throw PlatformException(code: 'x'));
      await DeviceInfo.init();
      expect(DeviceInfo.isTv, false);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var asked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async => asked = true);
      await DeviceInfo.init();
      expect(asked, false);
      expect(DeviceInfo.isTv, false);
    });
  });

  testWidgets('FocusCard draws the bold TV ring only in TV mode', (t) async {
    double ringWidth() {
      final box = t.widget<AnimatedContainer>(find.descendant(of: find.byType(FocusCard), matching: find.byType(AnimatedContainer)).first);
      return ((box.decoration as BoxDecoration).border as Border).top.width;
    }

    for (final tv in [false, true]) {
      await t.pumpWidget(MaterialApp(
        home: TvScope(
          tv: tv,
          child: Scaffold(body: Center(child: SizedBox(width: 100, height: 150, child: FocusCard(autofocus: true, onTap: () {}, child: const SizedBox())))),
        ),
      ));
      await t.pumpAndSettle();
      expect(ringWidth(), tv ? 4 : 3);
    }
  });

  testWidgets('on TV, Back from another tab returns to Home before leaving the app', (t) async {
    final st = await settings({'startTab': 3});
    final app = AppState()..bindSettings(st);
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<SettingsState>.value(value: st),
      ],
      child: MaterialApp(theme: Boss.theme(tv: true), home: const TvScope(tv: true, child: Shell())),
    ));
    await t.pumpAndSettle();
    int selected() => t.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex!;
    expect(selected(), 3);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(selected(), 0);
  });

  testWidgets('off TV, the tab bar layout is used on a narrow screen and Back does not switch tabs', (t) async {
    final st = await settings({'startTab': 3});
    final app = AppState()..bindSettings(st);
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<SettingsState>.value(value: st),
      ],
      child: MaterialApp(theme: Boss.theme(), home: const Shell()),
    ));
    await t.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 3);
  });

  testWidgets('D-pad: focus starts on Play, then moves down into the shelf and across it', (t) async {
    final st = await settings({'tvMode': 'on'});
    final app = AppState()..bindSettings(st);
    app.catalog = const Catalog(
      live: [
        MediaItem(id: '1', name: 'News One', kind: MediaKind.live, streamUrl: 'http://x/1'),
        MediaItem(id: '2', name: 'News Two', kind: MediaKind.live, streamUrl: 'http://x/2'),
      ],
      movies: [MediaItem(id: '3', name: 'Movie One', kind: MediaKind.movie, streamUrl: 'http://x/3')],
    );
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<SettingsState>.value(value: st),
      ],
      child: MaterialApp(theme: Boss.theme(tv: true), home: const TvScope(tv: true, child: Scaffold(body: HomeScreen()))),
    ));
    await t.pumpAndSettle();

    BuildContext focused() => FocusManager.instance.primaryFocus!.context!;
    String? tile() => focused().findAncestorWidgetOfExactType<MediaTile>()?.item.name;

    expect(focused().findAncestorWidgetOfExactType<FilledButton>(), isNotNull, reason: 'Play is focused at start');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(tile(), 'News One');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(tile(), 'News Two');

    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(focused().findAncestorWidgetOfExactType<FilledButton>(), isNotNull, reason: 'Up returns to Play');
  });
}
