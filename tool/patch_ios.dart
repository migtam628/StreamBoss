// Run after `flutter create . --platforms=ios`:  dart run tool/patch_ios.dart
// Casting (lib/services/cast_service.dart) looks for Chromecast devices with Bonjour. Since iOS 14 the
// app has to declare that and say why it uses the local network, or the search finds nothing.
import 'dart:io';

void main() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) {
    stderr
        .writeln('ios/Runner/Info.plist not found. Run flutter create first.');
    exit(1);
  }
  var x = f.readAsStringSync();
  if (x.contains('NSBonjourServices')) {
    stdout.writeln('Already patched.');
    return;
  }
  const add = '''
	<key>NSBonjourServices</key>
	<array>
		<string>_googlecast._tcp</string>
	</array>
	<key>NSLocalNetworkUsageDescription</key>
	<string>StreamBoss uses the local network to find TVs you can cast to.</string>
''';
  final i = x.lastIndexOf('</dict>');
  if (i < 0) {
    stderr.writeln('Unexpected format in ios/Runner/Info.plist');
    exit(1);
  }
  x = '${x.substring(0, i)}$add${x.substring(i)}';
  f.writeAsStringSync(x);
  stdout.writeln('Patched Info.plist for casting.');
}
