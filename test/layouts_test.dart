import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/shell_nav.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/settings/settings_pages.dart';
import 'package:streamboss/screens/shell.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/tv.dart';

const _catalog = Catalog(
  liveCategories: [Category('l1', 'Sports'), Category('l2', 'News')],
  movieCategories: [Category('m1', 'Action'), Category('m2', 'Drama')],
  live: [
    MediaItem(
        id: '1',
        name: 'Arena Sports 1',
        kind: MediaKind.live,
        streamUrl: 'http://x/1',
        categoryId: 'l1'),
    MediaItem(
        id: '2',
        name: 'Metro News 24',
        kind: MediaKind.live,
        streamUrl: 'http://x/2',
        categoryId: 'l2'),
  ],
  movies: [
    MediaItem(
        id: '3',
        name: 'Salt Road',
        kind: MediaKind.movie,
        streamUrl: 'http://x/3',
        categoryId: 'm1',
        plot: 'A courier crosses a frozen salt flat.'),
    MediaItem(
        id: '4',
        name: 'Northbound',
        kind: MediaKind.movie,
        streamUrl: 'http://x/4',
        categoryId: 'm2',
        plot: 'A long drive north.'),
  ],
);

Future<(SettingsState, AppState)> setup(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final st = SettingsState();
  await st.init();
  final app = AppState()..bindSettings(st);
  app.catalog = _catalog;
  return (st, app);
}

Future<void> pumpApp(WidgetTester t, SettingsState st, AppState app, Size size,
    {Widget? home}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final tv = st.isTv;
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<SettingsState>.value(value: st),
    ],
    child: MaterialApp(
      theme: Boss.theme(tv: tv, layout: st.layout),
      builder: (context, child) => TvCanvas(
          enabled: tv,
          width: st.tvWidth,
          child: TvScope(tv: tv, child: child!)),
      home: home ?? const Shell(),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  tearDown(() {
    SettingsState.detectedTv = false;
    debugDefaultTargetPlatformOverride = null;
  });

  group('layout setting', () {
    test('defaults to Marquee, persists, and is a device setting', () async {
      var (st, _) = await setup({});
      expect(st.layout, UiLayout.marquee);
      st.set('layout', 'control');
      expect(st.layout, UiLayout.control);
      (st, _) = await setup({'layout': 'spotlight'});
      expect(st.layout, UiLayout.spotlight);
      expect(SettingsState.deviceKeys, containsAll(['layout', 'tvWidth']));
      st.applyMap({'layout': 'control'});
      expect(st.layout, UiLayout.spotlight,
          reason: 'a backup from another device must not change the layout');
    });

    test('an unknown stored value falls back to Marquee', () async {
      final (st, _) = await setup({'layout': 'nonsense'});
      expect(st.layout, UiLayout.marquee);
    });

    test('every layout has its own palette installed by the theme', () {
      for (final l in UiLayout.values) {
        final t = Boss.theme(layout: l);
        expect(t.extension<LayoutPalette>(), LayoutPalette.forLayout(l));
        expect(t.scaffoldBackgroundColor, LayoutPalette.forLayout(l).bg);
      }
    });

    test(
        'phone bars never repeat a screen, and every layout can reach Settings and Search',
        () {
      for (final l in UiLayout.values) {
        final t = phoneTabs(l);
        final all = [...t.bar, ...t.more];
        expect(all.toSet().length, all.length, reason: l.label);
        expect(all, containsAll([5, 6]), reason: l.label);
        expect(t.bar.length, lessThanOrEqualTo(4));
      }
    });

    test('Prime Time calls Home the Guide and Hub calls it the Hub', () {
      expect(destLabel(UiLayout.prime, 0), 'Guide');
      expect(destLabel(UiLayout.hub, 0), 'Hub');
      expect(destLabel(UiLayout.marquee, 0), 'Home');
    });
  });

  group('TvCanvas', () {
    testWidgets(
        'lays the app out on the chosen width whatever the screen reports',
        (t) async {
      t.view.physicalSize = const Size(960, 540);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      Size? seen;
      await t.pumpWidget(MaterialApp(
        home: TvCanvas(
            enabled: true,
            width: 1280,
            child: Builder(builder: (c) {
              seen = MediaQuery.sizeOf(c);
              return const SizedBox.expand();
            })),
      ));
      expect(seen!.width, 1280);
      expect(seen!.height, closeTo(720, 0.01));
    });

    testWidgets('does nothing when TV mode is off', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      Size? seen;
      await t.pumpWidget(MaterialApp(
        home: TvCanvas(
            enabled: false,
            width: 1280,
            child: Builder(builder: (c) {
              seen = MediaQuery.sizeOf(c);
              return const SizedBox.expand();
            })),
      ));
      expect(seen, const Size(420, 900));
    });
  });

  for (final layout in UiLayout.values) {
    group(layout.label, () {
      testWidgets(
          'phone: Home and every browse tab render, bottom bar with More',
          (t) async {
        final (st, app) = await setup({'layout': layout.name});
        await pumpApp(t, st, app, const Size(420, 900));
        if (layout == UiLayout.indexList) {
          // The list is the menu: no bottom bar on Home, a slim back bar inside a section.
          expect(find.byType(NavigationBar), findsNothing);
          expect(find.text('MOVIES'), findsOneWidget);
          await t.tap(find.text('MOVIES'));
          await t.pumpAndSettle();
          expect(tester(t), isNull);
          expect(find.byType(IndexBackBar), findsOneWidget);
          await t.tap(find.text('Index'));
          await t.pumpAndSettle();
          expect(find.text('MOVIES'), findsOneWidget);
          return;
        }
        expect(find.byType(NavigationBar), findsOneWidget);
        final tabs = phoneTabs(layout);
        expect(find.text('More'),
            tabs.more.isEmpty ? findsNothing : findsOneWidget);
        for (final k in tabs.bar) {
          await t.tap(find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(destLabel(layout, k))));
          await t.pumpAndSettle();
          expect(tester(t), isNull, reason: 'no exceptions on that tab');
        }
        if (tabs.more.isNotEmpty) {
          await t.tap(find.text('More'));
          await t.pumpAndSettle();
          expect(find.text(destLabel(layout, tabs.more.first)), findsWidgets);
        }
      });

      testWidgets(
          'TV: 1280 canvas renders Home and each browse tab without overflow',
          (t) async {
        final (st, app) = await setup({'layout': layout.name, 'tvMode': 'on'});
        await pumpApp(t, st, app, const Size(1920, 1080));
        for (final k in [1, 3]) {
          if (layout == UiLayout.marquee) {
            final rail = t.widget<NavigationRail>(find.byType(NavigationRail));
            expect(rail.destinations.length, 7);
            (rail.onDestinationSelected!)(k);
          } else if (layout == UiLayout.hub) {
            await t.tap(find.text(k == 1 ? 'Live TV' : 'Movies').first);
            await t.pumpAndSettle();
            expect(tester(t), isNull);
            await t.tap(find.text('Hub').first);
          } else if (layout == UiLayout.cable) {
            await t.tap(find.text(k == 1 ? 'CHANNELS' : 'MOVIES').first);
            await t.pumpAndSettle();
            expect(tester(t), isNull);
            await t.tap(find.text('Live').first);
          } else if (layout == UiLayout.indexList) {
            await t.tap(find.text(k == 1 ? 'LIVE NOW' : 'MOVIES').first);
            await t.pumpAndSettle();
            expect(tester(t), isNull);
            await t.tap(find.text('Index').first);
          } else {
            await t.tap(find.text(kDests[k].label).first);
          }
          await t.pumpAndSettle();
          expect(tester(t), isNull);
        }
      });
    });
  }

  testWidgets('Spotlight on TV: the details panel follows the focused poster',
      (t) async {
    final (st, app) =
        await setup({'layout': 'spotlight', 'tvMode': 'on', 'startTab': 3});
    await pumpApp(t, st, app, const Size(1280, 720));
    expect(find.text('Salt Road'), findsWidgets);
    expect(find.text('A courier crosses a frozen salt flat.'), findsOneWidget);
    // Move focus onto the second poster.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
  });

  testWidgets('Control Room on TV lists channels numbered, with a details pane',
      (t) async {
    final (st, app) =
        await setup({'layout': 'control', 'tvMode': 'on', 'startTab': 1});
    await pumpApp(t, st, app, const Size(1280, 720));
    expect(find.text('Arena Sports 1'), findsWidgets);
    expect(find.text('Metro News 24'), findsWidgets);
    expect(find.text('1'), findsWidgets);
    expect(find.text('Sports'), findsOneWidget);
    expect(find.text('News'), findsWidgets);
    expect(find.text('Watch'), findsOneWidget);
  });

  testWidgets('Control Room category pane filters the channel list', (t) async {
    final (st, app) =
        await setup({'layout': 'control', 'tvMode': 'on', 'startTab': 1});
    await pumpApp(t, st, app, const Size(1280, 720));
    await t.tap(find.text('News').first);
    await t.pumpAndSettle();
    expect(find.text('Arena Sports 1'), findsNothing);
    expect(find.text('Metro News 24'), findsWidgets);
  });

  testWidgets('Hub: the tiles open Live, Movies and the other places',
      (t) async {
    final (st, app) = await setup({'layout': 'hub', 'tvMode': 'on'});
    await pumpApp(t, st, app, const Size(1280, 720));
    expect(find.text('Live TV'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('2 channels'), findsOneWidget);
    await t.tap(find.text('Movies'));
    await t.pumpAndSettle();
    expect(find.text('Salt Road'), findsWidgets);
    expect(find.text('Hub'), findsOneWidget,
        reason: 'the bar to get back to the hub');
  });

  testWidgets('Hub: Back from a section returns to the hub', (t) async {
    final (st, app) = await setup({'layout': 'hub', 'tvMode': 'on'});
    await pumpApp(t, st, app, const Size(1280, 720));
    await t.tap(find.text('Movies'));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Live TV'), findsOneWidget);
  });

  testWidgets('Coverflow: Right flips to the next title and the details follow',
      (t) async {
    final (st, app) =
        await setup({'layout': 'coverflow', 'tvMode': 'on', 'startTab': 3});
    await pumpApp(t, st, app, const Size(1280, 720));
    expect(find.text('1 of 2', findRichText: true), findsNothing);
    expect(find.textContaining('1 of 2'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(find.textContaining('2 of 2'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(find.textContaining('1 of 2'), findsOneWidget);
  });

  testWidgets(
      'Prime Time: Home is the guide, with a channel list when there is no guide source',
      (t) async {
    final (st, app) = await setup({'layout': 'prime', 'tvMode': 'on'});
    await pumpApp(t, st, app, const Size(1280, 720));
    expect(find.text('Arena Sports 1'), findsWidgets);
    expect(find.text('Move over the grid to see what is on.'), findsOneWidget);
  });

  testWidgets('Appearance page: choosing a layout card changes the setting',
      (t) async {
    final (st, app) = await setup({});
    await pumpApp(t, st, app, const Size(900, 1400),
        home: const Scaffold(body: AppearancePage()));
    expect(st.layout, UiLayout.marquee);
    await t.tap(find.text('Spotlight'));
    await t.pumpAndSettle();
    expect(st.layout, UiLayout.spotlight);
    await t.tap(find.text('Control Room'));
    await t.pumpAndSettle();
    expect(st.layout, UiLayout.control);
  });

  group('Daylight', () {
    test('is the light layout: light Material theme and an ink focus ring', () {
      const p = LayoutPalette.daylight;
      expect(p.light, isTrue);
      expect(p.ring, p.text);
      expect(Boss.theme(layout: UiLayout.daylight).brightness, Brightness.light);
      expect(Boss.theme(layout: UiLayout.marquee).brightness, Brightness.dark);
      expect(LayoutPalette.marquee.ring, Colors.white);
    });

    testWidgets('Home shows a feature card with Play and the live channels',
        (t) async {
      final (st, app) = await setup({'layout': 'daylight'});
      await pumpApp(t, st, app, const Size(420, 900));
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Live now'), findsOneWidget);
      expect(find.text('Arena Sports 1'), findsWidgets);
    });
  });

  group('Cable Box', () {
    testWidgets('Down and Up change channel and the banner follows',
        (t) async {
      final (st, app) = await setup({'layout': 'cable', 'tvMode': 'on'});
      await pumpApp(t, st, app, const Size(1280, 720));
      expect(find.text('ARENA SPORTS 1'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(find.text('METRO NEWS 24'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(find.text('ARENA SPORTS 1'), findsOneWidget);
    });

    testWidgets('a category narrows the channels', (t) async {
      final (st, app) = await setup({'layout': 'cable', 'tvMode': 'on'});
      await pumpApp(t, st, app, const Size(1280, 720));
      await t.tap(find.text('NEWS').first);
      await t.pumpAndSettle();
      expect(find.text('METRO NEWS 24'), findsOneWidget);
      expect(find.text('ARENA SPORTS 1'), findsNothing);
    });

    testWidgets('the soft keys open the other screens', (t) async {
      final (st, app) = await setup({'layout': 'cable', 'tvMode': 'on'});
      await pumpApp(t, st, app, const Size(1280, 720));
      for (final k in ['GUIDE', 'CHANNELS', 'MOVIES', 'SERIES', 'SEARCH', 'SETTINGS']) {
        expect(find.text(k), findsOneWidget, reason: k);
      }
    });
  });

  group('Index', () {
    testWidgets('the words show counts and the panel follows the highlight',
        (t) async {
      final (st, app) = await setup({'layout': 'indexList', 'tvMode': 'on'});
      await pumpApp(t, st, app, const Size(1280, 720));
      for (final w in ['LIVE NOW', 'CONTINUE', 'MOVIES', 'SERIES', 'GUIDE', 'SETTINGS']) {
        expect(find.text(w), findsOneWidget, reason: w);
      }
      // Nothing watched yet: the first word is highlighted and lists what is live.
      expect(find.text('ON NOW'), findsOneWidget);
      expect(find.text('Arena Sports 1'), findsOneWidget);
      await t.tap(find.text('MOVIES'));
      await t.pumpAndSettle();
      // Tapping a word opens that screen.
      expect(find.text('Index'), findsWidgets);
    });
  });
}

/// The exception, if any, the framework caught during the last frame.
Object? tester(WidgetTester t) => t.takeException();
