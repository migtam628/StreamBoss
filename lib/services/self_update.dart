import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'update_check.dart';

/// The platforms that can replace themselves from inside the app. Web and iOS/tvOS cannot: the page
/// is reloaded, or the store/TestFlight does it.
enum UpdateTarget { android, windows, linux, macos }

UpdateTarget? updateTarget() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => UpdateTarget.android,
    TargetPlatform.windows => UpdateTarget.windows,
    TargetPlatform.linux => UpdateTarget.linux,
    TargetPlatform.macOS => UpdateTarget.macos,
    _ => null,
  };
}

/// The release file to install on [t]. [abis] are the device's CPU types, best first (Android).
UpdateAsset? pickAsset(List<UpdateAsset> assets, UpdateTarget t, {List<String> abis = const []}) {
  bool ends(UpdateAsset a, String s) => a.name.toLowerCase().endsWith(s);
  switch (t) {
    case UpdateTarget.android:
      final apks = assets.where((a) => ends(a, '.apk')).toList();
      for (final abi in abis) {
        for (final a in apks) {
          if (ends(a, '-${abi.toLowerCase()}.apk')) return a;
        }
      }
      for (final a in apks) {
        if (a.name.toLowerCase().contains('universal')) return a;
      }
      return apks.length == 1 ? apks.first : null;
    case UpdateTarget.windows:
      return assets.where((a) => ends(a, '-windows-x64.zip')).firstOrNull;
    case UpdateTarget.linux:
      return assets.where((a) => ends(a, '-linux-x64.tar.gz')).firstOrNull;
    case UpdateTarget.macos:
      return assets.where((a) => ends(a, '-macos.zip')).firstOrNull;
  }
}

/// Lets a running download be stopped.
class UpdateCancel {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class UpdateCancelled implements Exception {
  @override
  String toString() => 'Cancelled';
}

/// Downloads [a] into [dir], reporting progress, and checks its size and SHA-256 when they are known.
/// Returns the finished file; a failed or cancelled download leaves nothing behind.
Future<File> downloadUpdate(
  UpdateAsset a, {
  required Directory dir,
  http.Client? client,
  void Function(int received, int total)? onProgress,
  UpdateCancel? cancel,
}) async {
  final c = client ?? http.Client();
  await dir.create(recursive: true);
  final out = File('${dir.path}/${a.name}');
  final part = File('${out.path}.part');
  if (await out.exists()) await out.delete();
  IOSink? sink;
  try {
    final res = await c.send(http.Request('GET', Uri.parse(a.url))..headers['Accept'] = 'application/octet-stream');
    if (res.statusCode != 200) throw Exception('The download failed (${res.statusCode}).');
    final total = res.contentLength ?? a.size;
    sink = part.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      if (cancel?.cancelled ?? false) throw UpdateCancelled();
      sink.add(chunk);
      got += chunk.length;
      onProgress?.call(got, total);
    }
    await sink.flush();
    await sink.close();
    sink = null;
    if (a.size > 0 && got != a.size) {
      throw Exception('The download was cut short ($got of ${a.size} bytes). Try again.');
    }
    if (a.sha256 != null) {
      final sum = (await sha256.bind(part.openRead()).first).toString();
      if (sum != a.sha256) throw Exception('The download did not match its checksum, so it was not installed.');
    }
    await part.rename(out.path);
    return out;
  } catch (_) {
    try {
      await sink?.close();
    } catch (_) {}
    if (await part.exists()) await part.delete();
    rethrow;
  } finally {
    if (client == null) c.close();
  }
}

String _psq(String s) => "'${s.replaceAll("'", "''")}'";
String _shq(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// The PowerShell script that swaps the files of a running Windows install once it has exited.
String windowsUpdateScript({required int pid, required String zip, required String dest, required String exe}) => '''
\$ErrorActionPreference = 'Stop'
try { Wait-Process -Id $pid -Timeout 60 } catch {}
\$tmp = Join-Path \$env:TEMP 'streamboss-update'
if (Test-Path \$tmp) { Remove-Item -Recurse -Force \$tmp }
Expand-Archive -LiteralPath ${_psq(zip)} -DestinationPath \$tmp -Force
Copy-Item -Path (Join-Path \$tmp '*') -Destination ${_psq(dest)} -Recurse -Force
Remove-Item -Recurse -Force \$tmp
Start-Process -FilePath ${_psq(exe)}
''';

/// The shell script that does the same on Linux (a tar.gz unpacked over the install folder).
String linuxUpdateScript({required int pid, required String archive, required String dest, required String exe}) => '''
#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
tar -xzf ${_shq(archive)} -C ${_shq(dest)} && (nohup ${_shq(exe)} >/dev/null 2>&1 &)
''';

/// Where the new macOS app goes. Normally over the one that is running. But an app opened straight from
/// Downloads or a disk image is run by macOS from a random read-only copy ("App Translocation", under
/// /private/var/folders) or from /Volumes, which cannot be changed: then it is put in Applications, or in
/// the person's own Applications folder when that is not writable. [writable] says whether a folder can
/// be changed.
String macosInstallTarget(String runningApp, {required String home, required bool Function(String dir) writable}) {
  final name = runningApp.split('/').where((e) => e.isNotEmpty).lastOrNull ?? 'StreamBoss.app';
  final stuck = runningApp.contains('/AppTranslocation/') || runningApp.startsWith('/Volumes/');
  final parent = runningApp.substring(0, runningApp.lastIndexOf('/'));
  if (!stuck && writable(parent)) return runningApp;
  if (writable('/Applications')) return '/Applications/$name';
  return '$home/Applications/$name';
}

/// And on macOS (a zip holding the .app, which replaces the one that is running).
String macosUpdateScript({required int pid, required String zip, required String app}) => '''
#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
mkdir -p ${_shq(app.substring(0, app.lastIndexOf('/')))}
tmp="\$(mktemp -d)"
ditto -x -k ${_shq(zip)} "\$tmp" && rm -rf ${_shq(app)} && mv "\$tmp"/*.app ${_shq(app)} && xattr -cr ${_shq(app)}
open ${_shq(app)}
''';

/// The result of the system installer on Android.
enum InstallStatus { waiting, success, failed }

class InstallEvent {
  final InstallStatus status;
  final String? message;
  const InstallEvent(this.status, [this.message]);
}

/// Everything platform specific about installing an update from inside the app.
class SelfUpdate {
  static const _channel = MethodChannel('com.streamboss/update');
  static final _events = StreamController<InstallEvent>.broadcast();
  static bool _wired = false;

  /// What Android's installer says while a downloaded APK is being installed.
  static Stream<InstallEvent> get events {
    if (!_wired) {
      _wired = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'status') return;
        final m = Map<String, dynamic>.from(call.arguments as Map);
        _events.add(InstallEvent(
          switch (m['code']) {
            'success' => InstallStatus.success,
            'failed' => InstallStatus.failed,
            _ => InstallStatus.waiting,
          },
          m['message'] as String?,
        ));
      });
    }
    return _events.stream;
  }

  static Future<List<String>> abis() async {
    try {
      return (await _channel.invokeMethod<List<dynamic>>('abis') ?? const []).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// Whether Android lets this app install packages. False until the person allows "Install unknown apps".
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openInstallSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Where downloads go: the app's own cache, which nothing else can read.
  static Future<Directory> downloadDir() async => Directory('${(await getTemporaryDirectory()).path}/update');

  /// Installs [file]. On Android the system installer takes over (watch [events]); on desktop the app
  /// quits, a small script swaps the files and starts the new version.
  static Future<void> install(File file, UpdateTarget t) async {
    switch (t) {
      case UpdateTarget.android:
        await _channel.invokeMethod<bool>('install', file.path);
      case UpdateTarget.windows:
        final exe = Platform.resolvedExecutable;
        final dest = File(exe).parent.path;
        await _checkWritable(dest);
        final script = File('${file.parent.path}/apply-update.ps1');
        await script.writeAsString(windowsUpdateScript(pid: pid, zip: file.path, dest: dest, exe: exe));
        await Process.start(
            'powershell', ['-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', script.path],
            mode: ProcessStartMode.detached);
        _quitSoon();
      case UpdateTarget.linux:
        final exe = Platform.resolvedExecutable;
        final dest = File(exe).parent.path;
        await _checkWritable(dest);
        final script = File('${file.parent.path}/apply-update.sh');
        await script.writeAsString(linuxUpdateScript(pid: pid, archive: file.path, dest: dest, exe: exe));
        await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
        _quitSoon();
      case UpdateTarget.macos:
        // .../StreamBoss.app/Contents/MacOS/streamboss
        final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
        if (!app.endsWith('.app')) throw Exception('Could not find the app to replace. Install the new version by hand.');
        final target = macosInstallTarget(app,
            home: Platform.environment['HOME'] ?? '', writable: _writable);
        final dir = target.substring(0, target.lastIndexOf('/'));
        await Directory(dir).create(recursive: true);
        await _checkWritable(dir);
        final script = File('${file.parent.path}/apply-update.sh');
        await script.writeAsString(macosUpdateScript(pid: pid, zip: file.path, app: target));
        await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
        _quitSoon();
    }
  }

  static bool _writable(String dir) {
    try {
      final f = File('$dir/.streamboss-write-test');
      f.writeAsStringSync('x');
      f.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _checkWritable(String dir) async {
    try {
      final f = File('$dir/.streamboss-write-test');
      await f.writeAsString('x');
      await f.delete();
    } catch (_) {
      throw Exception('StreamBoss cannot change the files in $dir. Move it to a folder you own, or run it as an administrator.');
    }
  }

  static void _quitSoon() => Future.delayed(const Duration(milliseconds: 400), () => exit(0));
}
