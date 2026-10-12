import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/app_info.dart';
import 'package:streamboss/layouts/shell_nav.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/screens/moobee_screen.dart';
import 'package:streamboss/services/moobee.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

void main() {
  group('the address', () {
    test('empty means the project\'s own', () {
      expect(moobeeAddress('').toString(), kMoobeeUrl);
      expect(moobeeAddress('   ').toString(), kMoobeeUrl);
    });

    test('a bare name becomes https, a path is kept', () {
      expect(moobeeAddress('moobee.example.com').toString(),
          'https://moobee.example.com');
      expect(moobeeAddress('https://m.example.com/home').toString(),
          'https://m.example.com/home');
    });

    test('plain http only for this machine, nonsense is refused', () {
      expect(moobeeAddress('http://localhost:5173'), isNotNull);
      expect(moobeeAddress('http://127.0.0.1:8787'), isNotNull);
      expect(moobeeAddress('http://moobee.example.com'), isNull);
      expect(moobeeAddress('ftp://moobee.example.com'), isNull);
      expect(moobeeAddress('https://'), isNull);
    });
  });

  group('when the tab is shown', () {
    test(
        'on by default, off with the setting, never on a TV, never without an address',
        () {
      expect(moobeeTabVisible(enabled: true, isTv: false, address: ''), isTrue);
      expect(
          moobeeTabVisible(enabled: false, isTv: false, address: ''), isFalse);
      expect(moobeeTabVisible(enabled: true, isTv: true, address: ''), isFalse);
      expect(
          moobeeTabVisible(
              enabled: true, isTv: false, address: 'http://moobee.example.com'),
          isFalse);
    });

    test('a web view inside the app on Android, iOS and macOS only', () {
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS
      ]) {
        expect(moobeeInApp(web: false, platform: p), isTrue, reason: '$p');
      }
      for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
        expect(moobeeInApp(web: false, platform: p), isFalse, reason: '$p');
      }
      expect(moobeeInApp(web: true, platform: TargetPlatform.android), isFalse);
    });

    test('links to other sites leave the app, MooBee\'s own pages stay', () {
      final home = Uri.parse('https://moobee.example.com/');
      expect(
          moobeeOwnPage(home, Uri.parse('https://moobee.example.com/movie/1')),
          isTrue);
      expect(moobeeOwnPage(home, Uri.parse('about:blank')), isTrue);
      expect(
          moobeeOwnPage(home, Uri.parse('https://www.youtube.com/watch?v=x')),
          isFalse);
      expect(
          moobeeOwnPage(
              home, Uri.parse('https://moobee.example.com.evil.test/')),
          isFalse);
      expect(moobeeOwnPage(home, Uri.parse('https://example.com/')), isFalse);
    });
  });

  group('the menus', () {
    test(
        'the tab is the last before Settings in the More sheet, and absent when off',
        () {
      final on = phoneTabs(UiLayout.marquee, moobee: true);
      expect(on.more, containsAllInOrder([5, 8, 6]));
      expect(phoneTabs(UiLayout.marquee).more, isNot(contains(8)));
      expect(topTabs(UiLayout.marquee, moobee: true).last, 8);
      expect(topTabs(UiLayout.marquee), isNot(contains(8)));
      expect(topTabs(UiLayout.prime, moobee: true), contains(8));
    });

    test('the layouts with no menu stay as they were', () {
      for (final l in [
        UiLayout.playground,
        UiLayout.easy,
        UiLayout.hub,
        UiLayout.indexList
      ]) {
        final t = phoneTabs(l, moobee: true);
        expect(t.more, isEmpty, reason: '$l');
        expect(t.bar, isNot(contains(8)), reason: '$l');
      }
    });

    test('Anime off and MooBee on', () {
      final t = phoneTabs(UiLayout.marquee, anime: false, moobee: true);
      expect(t.more, [4, 5, 8, 6]);
    });

    test('it has a name and an icon', () {
      expect(kDests[8].label, 'MooBee');
    });
  });

  group('the setting', () {
    Future<(SettingsState, AppState)> make(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final st = SettingsState();
      await st.init();
      return (st, AppState()..bindSettings(st));
    }

    test('on, with the project\'s own address, until changed', () async {
      final (st, app) = await make({});
      expect(st.moobeeTab, isTrue);
      expect(st.moobeeUrl, '');
      expect(app.moobeeVisible, isTrue);
      st.set('moobeeTab', false);
      expect(app.moobeeVisible, isFalse);
    });

    test('hidden on a TV', () async {
      final (_, app) = await make({'tvMode': 'on'});
      expect(app.moobeeVisible, isFalse);
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester t,
        {String url = '', bool inApp = false}) async {
      SharedPreferences.setMockInitialValues({'moobeeUrl': url});
      final st = SettingsState();
      await st.init();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsState>.value(value: st),
          ChangeNotifierProvider<AppState>.value(
              value: AppState()..bindSettings(st)),
        ],
        child: MaterialApp(
            theme: Boss.theme(tv: false, layout: st.layout),
            home: Scaffold(body: MooBeeScreen(inApp: inApp))),
      ));
      await t.pump();
    }

    testWidgets(
        'where a page cannot sit in the app there is a button that opens the browser',
        (t) async {
      await pump(t);
      expect(find.text('MooBee'), findsOneWidget);
      expect(find.text('Open MooBee'), findsOneWidget);
    });

    testWidgets('a bad address says so instead of showing a blank page',
        (t) async {
      await pump(t, url: 'http://moobee.example.com');
      expect(find.text('MooBee has no address'), findsOneWidget);
      expect(find.text('Open MooBee'), findsNothing);
    });
  });
}
