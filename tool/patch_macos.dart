// Run after `flutter create . --platforms=macos`:  dart run tool/patch_macos.dart
// The macOS app is sandboxed; without the network.client entitlement every outgoing
// connection (providers, playlists, streams, TMDB) fails with a DNS-style error.
import 'dart:io';

const _key = 'com.apple.security.network.client';

void main() {
  var patched = 0;
  for (final name in ['DebugProfile', 'Release']) {
    final f = File('macos/Runner/$name.entitlements');
    if (!f.existsSync()) {
      stderr.writeln('${f.path} not found. Run flutter create first.');
      exit(1);
    }
    final x = f.readAsStringSync();
    if (x.contains(_key)) continue;
    final i = x.lastIndexOf('</dict>');
    if (i < 0) {
      stderr.writeln('Unexpected format in ${f.path}');
      exit(1);
    }
    f.writeAsStringSync('${x.substring(0, i)}\t<key>$_key</key>\n\t<true/>\n${x.substring(i)}');
    patched++;
  }
  stdout.writeln(patched == 0 ? 'Already patched.' : 'Added $_key to $patched entitlements file(s).');
}
