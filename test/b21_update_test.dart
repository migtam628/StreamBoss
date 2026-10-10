import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/services/self_update.dart';
import 'package:streamboss/services/update_check.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/widgets/update_dialog.dart';

UpdateAsset a(String n, {int size = 0, String? sum}) => UpdateAsset(n, 'https://x/$n', size, sum);

void main() {
  group('pickAsset', () {
    final all = [
      a('StreamBoss-0.3.0b21-android-arm64-v8a.apk'),
      a('StreamBoss-0.3.0b21-android-armeabi-v7a.apk'),
      a('StreamBoss-0.3.0b21-android-x86_64.apk'),
      a('StreamBoss-0.3.0b21-windows-x64.zip'),
      a('StreamBoss-0.3.0b21-linux-x64.tar.gz'),
      a('StreamBoss-0.3.0b21-macos.zip'),
      a('StreamBoss-0.3.0b21-web.zip'),
    ];
    test('Android takes the first CPU type the device lists', () {
      expect(pickAsset(all, UpdateTarget.android, abis: ['arm64-v8a', 'armeabi-v7a'])!.name, endsWith('arm64-v8a.apk'));
      expect(pickAsset(all, UpdateTarget.android, abis: ['armeabi-v7a'])!.name, endsWith('armeabi-v7a.apk'));
      expect(pickAsset(all, UpdateTarget.android, abis: ['x86_64'])!.name, endsWith('x86_64.apk'));
      expect(pickAsset(all, UpdateTarget.android, abis: ['mips']), isNull);
    });
    test('desktop picks its own archive', () {
      expect(pickAsset(all, UpdateTarget.windows)!.name, endsWith('windows-x64.zip'));
      expect(pickAsset(all, UpdateTarget.linux)!.name, endsWith('linux-x64.tar.gz'));
      expect(pickAsset(all, UpdateTarget.macos)!.name, endsWith('macos.zip'));
      expect(pickAsset(const [], UpdateTarget.windows), isNull);
    });
  });

  group('release parsing', () {
    test('notes and assets come through, with the checksum when GitHub gives one', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'tag_name': 'v0.3.0b21',
            'html_url': 'https://github.com/x/y/releases/tag/v0.3.0b21',
            'body': '- **New** thing',
            'assets': [
              {'name': 'f.apk', 'browser_download_url': 'https://x/f.apk', 'size': 10, 'digest': 'sha256:ABCDEF'},
              {'name': 'g.zip', 'browser_download_url': 'https://x/g.zip', 'size': 5},
              {'name': 'broken'},
            ],
          }),
          200));
      final u = await checkForUpdate('0.2.0', client: client);
      expect(u.newer, isTrue);
      expect(u.notes, '- **New** thing');
      expect(u.assets.length, 2);
      expect(u.assets.first.sha256, 'abcdef');
      expect(u.assets.last.sha256, isNull);
    });
  });

  group('downloadUpdate', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sbupd'));
    tearDown(() => dir.deleteSync(recursive: true));

    final bytes = utf8.encode('pretend this is an apk');
    final good = sha256.convert(bytes).toString();

    test('saves the file and reports progress', () async {
      final seen = <int>[];
      final f = await downloadUpdate(a('u.apk', size: bytes.length, sum: good),
          dir: dir,
          client: MockClient.streaming((r, _) async =>
              http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length)),
          onProgress: (g, t) => seen.add(g));
      expect(f.readAsBytesSync(), bytes);
      expect(seen.last, bytes.length);
      expect(File('${f.path}.part').existsSync(), isFalse);
    });

    test('a wrong checksum is refused and nothing is left behind', () async {
      await expectLater(
          downloadUpdate(a('u.apk', size: bytes.length, sum: 'deadbeef'),
              dir: dir,
              client: MockClient.streaming(
                  (r, _) async => http.StreamedResponse(Stream.value(bytes), 200, contentLength: bytes.length))),
          throwsA(predicate((e) => e.toString().contains('checksum'))));
      expect(dir.listSync(), isEmpty);
    });

    test('a short download is refused', () async {
      await expectLater(
          downloadUpdate(a('u.apk', size: 999),
              dir: dir,
              client: MockClient.streaming((r, _) async => http.StreamedResponse(Stream.value(bytes), 200))),
          throwsA(predicate((e) => e.toString().contains('cut short'))));
    });

    test('an error status is refused', () async {
      await expectLater(
          downloadUpdate(a('u.apk'),
              dir: dir, client: MockClient.streaming((r, _) async => http.StreamedResponse(const Stream.empty(), 404))),
          throwsA(predicate((e) => e.toString().contains('404'))));
    });

    test('cancelling stops it and cleans up', () async {
      final cancel = UpdateCancel();
      await expectLater(
          downloadUpdate(a('u.apk'),
              dir: dir,
              cancel: cancel,
              onProgress: (_, __) => cancel.cancel(),
              client: MockClient.streaming((r, _) async =>
                  http.StreamedResponse(Stream.fromIterable([bytes, bytes, bytes]), 200))),
          throwsA(isA<UpdateCancelled>()));
      expect(dir.listSync(), isEmpty);
    });
  });

  group('desktop scripts', () {
    test('Windows waits for the app, unpacks, copies and restarts', () {
      final s = windowsUpdateScript(pid: 42, zip: r"C:\Temp\it's.zip", dest: r'C:\Apps\StreamBoss', exe: r'C:\Apps\StreamBoss\streamboss.exe');
      expect(s, contains('Wait-Process -Id 42'));
      expect(s, contains("'C:\\Temp\\it''s.zip'"));
      expect(s, contains("Copy-Item"));
      expect(s, contains("Start-Process -FilePath 'C:\\Apps\\StreamBoss\\streamboss.exe'"));
    });
    test('Linux and macOS scripts quote paths', () {
      final l = linuxUpdateScript(pid: 7, archive: "/tmp/a b/it's.tar.gz", dest: '/opt/sb', exe: '/opt/sb/streamboss');
      expect(l, contains('kill -0 7'));
      expect(l, contains(r"'/tmp/a b/it'\''s.tar.gz'"));
      final m = macosUpdateScript(pid: 9, zip: '/tmp/x.zip', app: '/Applications/StreamBoss.app');
      expect(m, contains("ditto -x -k '/tmp/x.zip'"));
      expect(m, contains("open '/Applications/StreamBoss.app'"));
    });
  });

  group('macOS install location', () {
    bool all(String _) => true;
    bool none(String _) => false;
    test('a normal app is replaced where it is', () {
      expect(macosInstallTarget('/Applications/StreamBoss.app', home: '/Users/me', writable: all), '/Applications/StreamBoss.app');
    });
    test('an app run from a translocated copy goes in Applications', () {
      const t = '/private/var/folders/zv/fyfsl4g14tdf075qf9ffw0k40000gn/T/AppTranslocation/D159B133/d/StreamBoss.app';
      expect(macosInstallTarget(t, home: '/Users/me', writable: all), '/Applications/StreamBoss.app');
    });
    test('and in the home Applications folder when that is not writable', () {
      const t = '/private/var/folders/zv/x/T/AppTranslocation/D1/d/StreamBoss.app';
      expect(macosInstallTarget(t, home: '/Users/me', writable: none), '/Users/me/Applications/StreamBoss.app');
    });
    test('an app on a disk image is not changed in place', () {
      expect(macosInstallTarget('/Volumes/StreamBoss/StreamBoss.app', home: '/Users/me', writable: all), '/Applications/StreamBoss.app');
    });
    test('a read-only folder falls back too', () {
      expect(macosInstallTarget('/opt/StreamBoss.app', home: '/Users/me', writable: (d) => d != '/opt'), '/Applications/StreamBoss.app');
    });
    test('the script makes the folder first', () {
      final m = macosUpdateScript(pid: 9, zip: '/tmp/x.zip', app: '/Users/me/Applications/StreamBoss.app');
      expect(m, contains("mkdir -p '/Users/me/Applications'"));
    });
  });

  group('plainNotes', () {
    test('drops markdown marks and trims', () {
      expect(plainNotes('## 1\n- **Bold** and [a link](http://x) and `code`'), '1\n- Bold and a link and code');
      expect(plainNotes('x' * 2000, max: 10), '${'x' * 10}…');
    });
  });

  group('UpdateDialog', () {
    const info = UpdateInfo('0.3.0b21', 'https://x', true,
        notes: '- **Updates in the app**', assets: [UpdateAsset('StreamBoss-0.3.0b21-android-arm64-v8a.apk', 'https://x/a.apk', 3)]);

    Future<SettingsState> open(WidgetTester t,
        {Future<File> Function(UpdateAsset, void Function(int, int), UpdateCancel)? download,
        Future<void> Function(File, UpdateTarget)? install,
        UpdateTarget? target = UpdateTarget.android}) async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      await t.pumpWidget(ChangeNotifierProvider<SettingsState>.value(
        value: st,
        child: MaterialApp(
          home: Scaffold(
            body: UpdateDialog(
              update: info,
              current: '0.3.0b20',
              target: target,
              abis: const ['arm64-v8a'],
              download: download,
              install: install,
            ),
          ),
        ),
      ));
      return st;
    }

    testWidgets('shows the notes and a button; Update now downloads then installs', (t) async {
      final installed = <String>[];
      final st = await open(t, download: (asset, progress, cancel) async {
        progress(1, 3);
        return File('/tmp/${asset.name}');
      }, install: (f, target) async => installed.add('${f.path}|${target.name}'));
      expect(find.text('Version 0.3.0b21 is available'), findsOneWidget);
      expect(find.textContaining('Updates in the app'), findsOneWidget);
      expect(find.textContaining('without opening a browser'), findsOneWidget);
      await t.tap(find.text('Update now'));
      await t.pump();
      await t.pump();
      expect(installed, ['/tmp/StreamBoss-0.3.0b21-android-arm64-v8a.apk|android']);
      expect(st.updating, isTrue);
      expect(find.textContaining('Handing the update to Android'), findsOneWidget);
    });

    testWidgets('a failed download says why and offers Try again', (t) async {
      final st = await open(t,
          download: (a, p, c) async => throw Exception('The download failed (503).'), install: (f, t) async {});
      await t.tap(find.text('Update now'));
      await t.pump();
      await t.pump();
      expect(find.textContaining('503'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(st.updating, isFalse);
    });

    testWidgets('where an app cannot update itself it says so', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await open(t, target: null);
      debugDefaultTargetPlatformOverride = null;
      expect(find.textContaining('updated by whatever installed it'), findsOneWidget);
      expect(find.text('Update now'), findsNothing);
    });
  });
}
