// Run after `flutter create . --platforms=macos`:  dart run tool/patch_macos.dart
// The macOS app is sandboxed. Without network.client every outgoing connection (providers,
// playlists, streams, TMDB) fails with a DNS-style error; without network.server the
// phone-setup page (lib/services/pairing_io.dart) can't accept connections.
import 'dart:io';

const _keys = ['com.apple.security.network.client', 'com.apple.security.network.server'];

void main() {
  var patched = 0;
  for (final name in ['DebugProfile', 'Release']) {
    final f = File('macos/Runner/$name.entitlements');
    if (!f.existsSync()) {
      stderr.writeln('${f.path} not found. Run flutter create first.');
      exit(1);
    }
    var x = f.readAsStringSync();
    var changed = false;
    for (final key in _keys) {
      if (x.contains(key)) continue;
      final i = x.lastIndexOf('</dict>');
      if (i < 0) {
        stderr.writeln('Unexpected format in ${f.path}');
        exit(1);
      }
      x = '${x.substring(0, i)}\t<key>$key</key>\n\t<true/>\n${x.substring(i)}';
      changed = true;
    }
    if (changed) {
      f.writeAsStringSync(x);
      patched++;
    }
  }
  stdout.writeln(patched == 0 ? 'Already patched.' : 'Added network entitlements to $patched file(s).');
  _patchDockIcon();
}

/// Lets the app change its Dock icon (Settings > Appearance > App icon, lib/services/app_icon.dart):
/// a `com.streamboss/app_icon` channel whose `setDockIcon` call receives PNG bytes. macOS keeps the
/// icon only while the app runs, so the app sets it again at every start.
void _patchDockIcon() {
  final f = File('macos/Runner/MainFlutterWindow.swift');
  if (!f.existsSync()) {
    stderr.writeln('${f.path} not found; the Dock icon cannot be changed.');
    return;
  }
  var x = f.readAsStringSync();
  if (x.contains('com.streamboss/app_icon')) return;
  const anchor = 'RegisterGeneratedPlugins(registry: flutterViewController)';
  if (!x.contains(anchor)) {
    stderr.writeln('Unexpected ${f.path}; the Dock icon cannot be changed.');
    return;
  }
  const channel = '''

    let iconChannel = FlutterMethodChannel(name: "com.streamboss/app_icon", binaryMessenger: flutterViewController.engine.binaryMessenger)
    iconChannel.setMethodCallHandler { call, result in
      if call.method == "setDockIcon",
         let data = (call.arguments as? FlutterStandardTypedData)?.data,
         let image = NSImage(data: data) {
        NSApplication.shared.applicationIconImage = image
        result(true)
      } else {
        result(false)
      }
    }''';
  x = x.replaceFirst(anchor, '$anchor$channel');
  f.writeAsStringSync(x);
  stdout.writeln('Added the Dock icon channel.');
}
