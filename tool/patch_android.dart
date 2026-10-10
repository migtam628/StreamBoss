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
  _copyResources();
  _patchSigning();
  _patchLibrarySdk();
  if (x.contains('LEANBACK_LAUNCHER')) {
    _patchIconAliases();
    _patchBoot();
    _patchUpdate();
    stdout.writeln('Already patched.');
    return;
  }

  const features = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
    <uses-feature android:name="android.software.leanback" android:required="false"/>
    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
''';
  x = x.replaceFirstMapped(RegExp(r'<manifest[^>]*>'), (m) => '${m[0]}\n$features');

  // Many IPTV servers are plain http.
  x = x.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"\n        android:banner="@drawable/banner"');
  x = x.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="StreamBoss"');

  // Add the TV launcher category next to the normal one.
  x = x.replaceFirstMapped(
    RegExp(r'<category android:name="android.intent.category.LAUNCHER"\s*/>'),
    (m) => '${m[0]}\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
  );

  // Picture-in-picture needs this flag on the activity.
  x = x.replaceFirst('<activity', '<activity\n            android:supportsPictureInPicture="true"');

  f.writeAsStringSync(x);
  _patchIconAliases();
  _patchBoot();
  _patchUpdate();
  stdout.writeln('Patched AndroidManifest.xml for TV.');
}

/// The launcher icons the app can switch between (Settings > Appearance > App icon). Each one is an
/// `activity-alias` of MainActivity with its own icon and TV banner; exactly one is enabled at a time and
/// the native channel in MainActivity flips them. Keep this list in step with lib/services/app_icon.dart
/// and design/make_icons.mjs.
const _iconNames = ['crown', 'bold', 'signal', 'screen'];

String _aliasClass(String n) => 'Icon${n[0].toUpperCase()}${n.substring(1)}';

void _patchIconAliases() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  var x = f.readAsStringSync();
  if (x.contains('.${_aliasClass(_iconNames.first)}"')) return;
  // The launcher entry moves from the activity itself to the aliases.
  x = x.replaceFirst(RegExp(r'<intent-filter>\s*<action android:name="android.intent.action.MAIN"\s*/>[\s\S]*?</intent-filter>'), '');
  final aliases = StringBuffer();
  for (final n in _iconNames) {
    aliases.writeln('''        <activity-alias
            android:name=".${_aliasClass(n)}"
            android:targetActivity=".MainActivity"
            android:enabled="${n == _iconNames.first}"
            android:exported="true"
            android:icon="@mipmap/ic_logo_$n"
            android:roundIcon="@mipmap/ic_logo_${n}_round"
            android:banner="@drawable/banner_$n"
            android:label="StreamBoss">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
            </intent-filter>
        </activity-alias>''');
  }
  x = x.replaceFirst('</application>', '$aliases    </application>');
  f.writeAsStringSync(x);
  stdout.writeln('Added the launcher icon aliases.');
}

/// Opening the app when the device starts (Settings > Startup): a receiver for BOOT_COMPLETED that
/// starts MainActivity when the app's own setting is on. Android 10 and later only let a background
/// receiver open an activity if the app may "Display over other apps", which the setting asks for.
void _patchBoot() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  var x = f.readAsStringSync();
  if (x.contains('.BootReceiver"') && x.contains('MY_PACKAGE_REPLACED')) return;
  x = x.replaceAll(RegExp(r'\s*<receiver\s+android:name="\.BootReceiver"[\s\S]*?</receiver>'), '');
  x = x.replaceAll(RegExp(r'\n    <uses-permission android:name="android.permission.(RECEIVE_BOOT_COMPLETED|SYSTEM_ALERT_WINDOW)"/>'), '');
  x = x.replaceFirstMapped(
      RegExp(r'<manifest[^>]*>'),
      (m) => '${m[0]}\n'
          '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
          '    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>');
  x = x.replaceFirst('</application>', '''        <receiver
            android:name=".BootReceiver"
            android:enabled="true"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
            </intent-filter>
        </receiver>
    </application>''');
  f.writeAsStringSync(x);
  final root = Directory('android/app/src/main/kotlin');
  final main = root.existsSync()
      ? root.listSync(recursive: true).whereType<File>().where((e) => e.path.endsWith('MainActivity.kt')).firstOrNull
      : null;
  final pkg = main == null ? null : RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(main.readAsStringSync())?[1];
  if (main == null || pkg == null) {
    stderr.writeln('MainActivity.kt not found; opening on start-up will be unavailable.');
    return;
  }
  File('${main.parent.path}/BootReceiver.kt').writeAsStringSync('''
package $pkg

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Opens the app after the device starts, when Settings > Startup > "Open when the device starts" is on.
/// Flutter keeps its preferences in this file, with a "flutter." prefix on every key.
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action ?: return
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (a == Intent.ACTION_MY_PACKAGE_REPLACED) {
            // The app just updated itself from Settings > About: open the new version again.
            if (!prefs.getBoolean("flutter.updating", false)) return
            prefs.edit().putBoolean("flutter.updating", false).apply()
        } else {
            if (a != Intent.ACTION_BOOT_COMPLETED && !a.endsWith("QUICKBOOT_POWERON")) return
            if (!prefs.getBoolean("flutter.startOnBoot", false)) return
        }
        try {
            context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
        }
    }
}
'''.trimLeft());
  stdout.writeln('Added the start-on-boot receiver.');
}

/// Updating from inside the app (Settings > About > Check for updates): the permission to install
/// packages, which Android also asks the person to allow once for this app.
void _patchUpdate() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  var x = f.readAsStringSync();
  if (x.contains('REQUEST_INSTALL_PACKAGES')) return;
  x = x.replaceFirstMapped(
      RegExp(r'<manifest[^>]*>'),
      (m) => '${m[0]}\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>');
  f.writeAsStringSync(x);
  stdout.writeln('Added the install-packages permission.');
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

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pipChannel: MethodChannel? = null
    private var updateChannel: MethodChannel? = null
    private val installAction = "$pkg.INSTALL_STATUS"

    // The system installer reports back here: it asks for the person's go-ahead, then succeeds or fails.
    private val installReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION")
                    val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                    if (confirm != null) {
                        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(confirm)
                    }
                    updateChannel?.invokeMethod("status", mapOf("code" to "waiting"))
                }
                PackageInstaller.STATUS_SUCCESS -> updateChannel?.invokeMethod("status", mapOf("code" to "success"))
                else -> updateChannel?.invokeMethod(
                    "status",
                    mapOf("code" to "failed", "message" to (intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "The install failed."))
                )
            }
        }
    }

    private fun installApk(path: String) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        val session = installer.openSession(id)
        try {
            java.io.FileInputStream(java.io.File(path)).use { input ->
                session.openWrite("streamboss", 0, -1).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(this, id, Intent(installAction).setPackage(packageName), flags)
            session.commit(pending.intentSender)
        } finally {
            session.close()
        }
    }

    // The launcher icons (activity-aliases in the manifest, see tool/patch_android.dart).
    private val iconNames = listOf("crown", "bold", "signal", "screen")

    private fun iconComponent(name: String) =
        ComponentName(this, "$pkg.Icon" + name.replaceFirstChar { it.uppercase() })

    private fun currentIcon(): String {
        for (n in iconNames) {
            if (packageManager.getComponentEnabledSetting(iconComponent(n)) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return n
        }
        return iconNames.first() // never switched: the manifest enables the first one
    }

    private fun setIcon(name: String) {
        // Enable the new one before disabling the others so there is always a launcher entry.
        packageManager.setComponentEnabledSetting(iconComponent(name), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        for (n in iconNames) {
            if (n != name) {
                packageManager.setComponentEnabledSetting(iconComponent(n), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.streamboss/app_icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "current" -> result.success(currentIcon())
                "set" -> {
                    val name = call.arguments as? String
                    if (name != null && iconNames.contains(name)) {
                        setIcon(name)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        val update = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.streamboss/update")
        updateChannel = update
        val filter = IntentFilter(installAction)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(installReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(installReceiver, filter)
        update.setMethodCallHandler { call, result ->
            when (call.method) {
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "canInstall" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                )
                "openInstallSettings" -> {
                    try {
                        startActivity(
                            Intent(
                                android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                android.net.Uri.parse("package:" + packageName)
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "install" -> {
                    try {
                        installApk(call.arguments as String)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install", e.message ?: "The install failed.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.streamboss/boot").setMethodCallHandler { call, result ->
            when (call.method) {
                // Android 10+ only lets the boot receiver open the app when it may draw over other apps.
                "canDrawOverlays" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || android.provider.Settings.canDrawOverlays(this)
                )
                "openOverlaySettings" -> {
                    try {
                        startActivity(
                            android.content.Intent(
                                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                android.net.Uri.parse("package:" + packageName)
                            ).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.streamboss/pip")
        pipChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                )
                "isTv" -> {
                    val ui = getSystemService(android.content.Context.UI_MODE_SERVICE) as android.app.UiModeManager
                    result.success(
                        ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                            packageManager.hasSystemFeature("amazon.hardware.fire_tv")
                    )
                }
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

    override fun onDestroy() {
        try {
            unregisterReceiver(installReceiver)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("changed", isInPictureInPictureMode)
    }
}
''';

/// Branded launcher icons and the 320x180 Android TV / Fire TV banner
/// (tool/android_res mirrors android/app/src/main/res).
void _copyResources() {
  final src = Directory('tool/android_res');
  final dst = Directory('android/app/src/main/res');
  if (!src.existsSync() || !dst.existsSync()) return;
  for (final f in src.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(src.path.length + 1);
    final out = File('${dst.path}/$rel')..parent.createSync(recursive: true);
    f.copySync(out.path);
  }
}

/// Signs release builds with a permanent key when one is provided through the environment
/// (STREAMBOSS_KEYSTORE = path to a .jks/.p12, STREAMBOSS_KEYSTORE_PASSWORD, STREAMBOSS_KEY_ALIAS,
/// optional STREAMBOSS_KEY_PASSWORD). Without it the build falls back to the machine's debug key,
/// which is regenerated on every fresh CI runner: each release then has a different signature and
/// Android refuses to install one over another. See README "Android signing".
void _patchSigning() {
  final f = File('android/app/build.gradle.kts');
  if (!f.existsSync()) {
    stderr.writeln('android/app/build.gradle.kts not found; releases will use the debug key.');
    return;
  }
  var x = f.readAsStringSync();
  if (x.contains('STREAMBOSS_KEYSTORE')) return;

  const vals = '''
// Permanent release key from the environment (see tool/patch_android.dart); debug key otherwise.
val sbKeystore: String? = System.getenv("STREAMBOSS_KEYSTORE")?.takeIf { it.isNotBlank() && file(it).exists() }
val sbStorePassword: String? = System.getenv("STREAMBOSS_KEYSTORE_PASSWORD")

''';
  const signing = '''    signingConfigs {
        if (sbKeystore != null) {
            create("streamboss") {
                storeFile = file(sbKeystore)
                storePassword = sbStorePassword
                keyAlias = System.getenv("STREAMBOSS_KEY_ALIAS") ?: "streamboss"
                keyPassword = System.getenv("STREAMBOSS_KEY_PASSWORD") ?: sbStorePassword
            }
        }
    }

''';
  final release = RegExp(r'signingConfig = signingConfigs\.getByName\("debug"\)');
  if (!x.contains('android {') || !x.contains('buildTypes {') || !release.hasMatch(x)) {
    stderr.writeln('Unexpected build.gradle.kts layout; releases will use the debug key.');
    return;
  }
  x = x.replaceFirst('android {', '${vals}android {');
  x = x.replaceFirst('    buildTypes {', '$signing    buildTypes {');
  x = x.replaceFirst(
    release,
    'signingConfig = if (sbKeystore != null) signingConfigs.getByName("streamboss") else signingConfigs.getByName("debug")',
  );
  f.writeAsStringSync(x);
  stdout.writeln('Patched build.gradle.kts for optional permanent release signing.');
}

/// Some plugins (bonsoir_android, used for casting) compile against an old Android SDK while their own
/// AndroidX dependencies need a newer one, which fails the release build. Compile every library
/// subproject against the same SDK as the app. Must come before `evaluationDependsOn(":app")` in the
/// root build file, because afterEvaluate cannot be added to a project that is already evaluated.
void _patchLibrarySdk() {
  final f = File('android/build.gradle.kts');
  if (!f.existsSync()) {
    return;
  }
  var x = f.readAsStringSync();
  if (x.contains('STREAMBOSS_LIBSDK')) {
    return;
  }
  const block = '''// STREAMBOSS_LIBSDK: see tool/patch_android.dart
subprojects {
    afterEvaluate {
        val ext = extensions.findByName("android")
        if (ext is com.android.build.gradle.LibraryExtension) {
            ext.compileSdk = 36
        }
    }
}
''';
  const anchor = 'subprojects {\n    project.evaluationDependsOn(":app")';
  if (!x.contains(anchor)) {
    stderr.writeln('android/build.gradle.kts has an unexpected layout; plugin SDKs left alone.');
    return;
  }
  x = x.replaceFirst(anchor, '$block$anchor');
  f.writeAsStringSync(x);
  stdout.writeln('Patched android/build.gradle.kts so plugins compile against SDK 36.');
}
