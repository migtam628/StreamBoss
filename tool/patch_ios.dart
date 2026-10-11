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
  _patchNotifications();
  _patchVoice(f);
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

/// Programme reminders arrive as local notifications; iOS needs the app to be the notification centre's
/// delegate for them to show while the app is open and to report a tap. Best effort: the generated
/// AppDelegate differs between Flutter versions, so this only adds the line where it knows the place.
void _patchNotifications() {
  final d = File('ios/Runner/AppDelegate.swift');
  if (!d.existsSync()) return;
  var x = d.readAsStringSync();
  if (x.contains('UNUserNotificationCenter')) return;
  const line = '    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate\n';
  final anchor = RegExp(r'(didFinishLaunchingWithOptions[^\n]*\{\n)');
  if (!anchor.hasMatch(x)) {
    stderr.writeln('ios/Runner/AppDelegate.swift has an unexpected layout; add the notification delegate line by hand '
        '(see flutter_local_notifications, "iOS setup").');
    return;
  }
  x = x.replaceFirstMapped(anchor, (m) => '${m[1]}$line');
  d.writeAsStringSync(x);
  stdout.writeln('Patched AppDelegate.swift for reminder notifications.');
}

/// Voice search: iOS asks the person for the microphone and for speech recognition, and shows these texts.
void _patchVoice(File plist) {
  var x = plist.readAsStringSync();
  if (x.contains('NSSpeechRecognitionUsageDescription')) return;
  const add = '''
	<key>NSMicrophoneUsageDescription</key>
	<string>StreamBoss uses the microphone for voice search.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>StreamBoss uses speech recognition to search by voice.</string>
''';
  final i = x.lastIndexOf('</dict>');
  if (i < 0) return;
  plist.writeAsStringSync('${x.substring(0, i)}$add${x.substring(i)}');
  stdout.writeln('Added the voice search texts to Info.plist.');
}
