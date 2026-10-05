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
  _patchMainActivity();
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

  // Picture-in-picture needs this flag on the activity.
  x = x.replaceFirst('<activity', '<activity\n            android:supportsPictureInPicture="true"');

  f.writeAsStringSync(x);
  stdout.writeln('Patched AndroidManifest.xml for TV.');
}

/// Replaces the generated MainActivity with one exposing picture-in-picture
/// over the `com.streamboss/pip` method channel (see lib/services/pip.dart).
void _patchMainActivity() {
  final root = Directory('android/app/src/main/kotlin');
  final files = root.existsSync()
      ? root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('MainActivity.kt')).toList()
      : <File>[];
  if (files.isEmpty) {
    stderr.writeln('MainActivity.kt not found; PiP will be unavailable.');
    return;
  }
  final f = files.first;
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(f.readAsStringSync())?[1];
  if (pkg == null) {
    stderr.writeln('Could not read package from MainActivity.kt.');
    return;
  }
  f.writeAsStringSync(_mainActivity(pkg));
}

String _mainActivity(String pkg) => '''
package $pkg

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.streamboss/pip")
        pipChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                )
                "enter" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational(16, 9))
                            .build()
                        result.success(enterPictureInPictureMode(params))
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("changed", isInPictureInPictureMode)
    }
}
''';
