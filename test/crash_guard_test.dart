import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/screens/shell.dart';
import 'package:streamboss/services/crash_guard_io.dart';
import 'package:streamboss/services/crash_report.dart';
import 'package:streamboss/services/provider_url.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('crashguard'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('redactUrls', () {
    test('keeps only scheme and host, so Xtream logins in paths and queries never reach a log', () {
      expect(redactUrls('Opening http://host.test:8080/live/user/pass/123.ts now'), 'Opening http://host.test:8080/… now');
      expect(redactUrls('GET https://u:p@cdn.test/a?token=abc failed'), 'GET https://cdn.test/… failed');
      expect(redactUrls('no urls here'), 'no urls here');
      expect(redactUrls('rtsp://h.test/x and http://a.test/b'), 'rtsp://h.test/… and http://a.test/…');
    });
  });

  group('CrashReport', () {
    CrashReport r(List<String> steps) => CrashReport([for (final s in steps) '[12:00:00.000] $s'].join('\n'));

    test('knows the last step and whether it died during startup', () {
      expect(r(['step begin live host=x', 'step props', 'step open']).duringStartup, isTrue);
      expect(r(['step begin vod', 'step open', 'step opened']).duringStartup, isTrue);
      expect(r(['step begin vod', 'step open', 'step playing']).duringStartup, isFalse);
      expect(r(['step begin vod', 'step playing', 'step background']).duringStartup, isFalse);
      expect(r(['step begin vod', 'step playing', 'step closing']).lastStep, 'closing');
      expect(r(['step begin vod', 'log warn x: something', 'step open', 'log warn y: later']).lastStep, 'open');
    });

    test('tail returns only the last lines', () {
      final t = CrashReport(List.generate(50, (i) => 'line $i').join('\n')).tail(5);
      expect(t.split('\n'), ['line 45', 'line 46', 'line 47', 'line 48', 'line 49']);
    });
  });

  group('CrashGuard', () {
    test('a session that ends cleanly leaves nothing to report but keeps its log', () {
      CrashGuard.initIn(dir);
      CrashGuard.begin('live host=h.test decoder=auto');
      CrashGuard.mark('props');
      CrashGuard.log('warn ffmpeg: slow');
      CrashGuard.end();
      CrashGuard.initIn(dir);
      expect(CrashGuard.takeReport(), isNull);
      expect(CrashGuard.lastLog(), allOf(contains('step begin live host=h.test'), contains('warn ffmpeg: slow')));
    });

    test('a session that never ends is reported once, with how far it got', () {
      CrashGuard.initIn(dir);
      CrashGuard.begin('vod host=h.test decoder=auto');
      CrashGuard.mark('props');
      CrashGuard.mark('open');
      // ...the app dies here: no end()
      CrashGuard.initIn(dir);
      final r = CrashGuard.takeReport();
      expect(r, isNotNull);
      expect(r!.lastStep, 'open');
      expect(r.duringStartup, isTrue);
      expect(CrashGuard.takeReport(), isNull, reason: 'reported only once');
      CrashGuard.initIn(dir);
      expect(CrashGuard.takeReport(), isNull, reason: 'and not again on the launch after that');
    });

    test('each session starts a fresh log, and the log is size-capped', () {
      CrashGuard.initIn(dir);
      CrashGuard.begin('one');
      for (var i = 0; i < 3000; i++) {
        CrashGuard.log('warn x: ${'y' * 60}');
      }
      final size = File('${dir.path}/playback.session').lengthSync();
      expect(size, lessThan(60 * 1024));
      CrashGuard.mark('open'); // steps still get through once the log is full
      expect(File('${dir.path}/playback.session').readAsStringSync(), contains('step open'));
      CrashGuard.begin('two');
      expect(File('${dir.path}/playback.session').readAsStringSync(), contains('step begin two'));
      expect(File('${dir.path}/playback.session').readAsStringSync(), isNot(contains('one')));
    });

    test('without a usable directory it does nothing and never throws', () {
      CrashGuard.initIn(Directory('/proc/nope/not-writable'));
      CrashGuard.begin('x');
      CrashGuard.mark('y');
      CrashGuard.log('z');
      CrashGuard.end();
      expect(CrashGuard.takeReport(), isNull);
    });
  });

  group('startup notice in the app', () {
    Future<SettingsState> pumpShell(WidgetTester t, {required String decoder, required List<String> steps}) async {
      SharedPreferences.setMockInitialValues({'decoder': decoder});
      final st = SettingsState();
      await st.init();
      File('${dir.path}/playback.session')
          .writeAsStringSync([for (final s in steps) '[12:00:00.000] $s'].join('\n'));
      CrashGuard.initIn(dir);
      final app = AppState()..bindSettings(st);
      t.view.physicalSize = const Size(1280, 720);
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
      return st;
    }

    testWidgets('a startup crash turns on Safe playback and says so', (t) async {
      final st = await pumpShell(t, decoder: 'auto', steps: ['step begin live host=h.test', 'step open']);
      expect(find.text('Playback closed unexpectedly'), findsOneWidget);
      expect(find.textContaining('Safe playback is now on'), findsOneWidget);
      expect(st.decoder, 'software');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.text('Playback closed unexpectedly'), findsNothing);
    });

    testWidgets('a crash mid-playback only reports, and changes nothing', (t) async {
      final st = await pumpShell(t, decoder: 'auto', steps: ['step begin vod host=h.test', 'step open', 'step playing']);
      expect(find.text('Playback closed unexpectedly'), findsOneWidget);
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      expect(st.decoder, 'auto');
    });

    testWidgets('a startup crash that already used software decoding says so', (t) async {
      final st = await pumpShell(t, decoder: 'software', steps: ['step begin live host=h.test', 'step props']);
      expect(find.textContaining('even with software decoding'), findsOneWidget);
      expect(st.decoder, 'software');
    });

    testWidgets('no notice after a clean exit', (t) async {
      SharedPreferences.setMockInitialValues({});
      CrashGuard.initIn(dir);
      CrashGuard.begin('live host=h.test');
      CrashGuard.end();
      CrashGuard.initIn(dir);
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(theme: Boss.theme(), home: const Shell()),
      ));
      await t.pumpAndSettle();
      expect(find.text('Playback closed unexpectedly'), findsNothing);
    });
  });
}
