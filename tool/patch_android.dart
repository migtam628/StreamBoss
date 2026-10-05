// Run after `flutter create .`:  dart run tool/patch_android.dart
// Makes the generated Android project work on Android TV, Google TV and Fire TV.
import 'dart:io';

void main() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stderr.writeln('android/app/src/main/AndroidManifest.xml not found. Run flutter create first.');
    exit(1);
  }
  var x = f.readAsStringSync();
  if (x.contains('LEANBACK_LAUNCHER')) {
    stdout.writeln('Already patched.');
    return;
  }

  const features = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-feature android:name="android.software.leanback" android:required="false"/>
    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
''';
  x = x.replaceFirstMapped(RegExp(r'<manifest[^>]*>'), (m) => '${m[0]}\n$features');

  // Many IPTV servers are plain http.
  x = x.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"\n        android:banner="@mipmap/ic_launcher"');

  // Add the TV launcher category next to the normal one.
  x = x.replaceFirstMapped(
    RegExp(r'<category android:name="android.intent.category.LAUNCHER"\s*/>'),
    (m) => '${m[0]}\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
  );

  f.writeAsStringSync(x);
  stdout.writeln('Patched AndroidManifest.xml for TV.');
}
