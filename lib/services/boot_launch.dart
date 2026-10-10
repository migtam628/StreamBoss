import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// "Open when the device starts" (Settings > Startup). The switch itself is the `startOnBoot` setting,
/// which the boot receiver added by tool/patch_android.dart reads; this only deals with the permission
/// Android 10 and later want before a background receiver may open the app.
class BootLaunch {
  static const _channel = MethodChannel('com.streamboss/boot');

  /// Android (phones, Android TV, Fire TV) only.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the system will let the app open itself at start-up. True where no permission is needed.
  static Future<bool> allowed() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the system screen where "Display over other apps" is granted; false when the device has none
  /// (some Fire TV versions), in which case the app can only be opened by hand.
  static Future<bool> openPermissionSettings() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('openOverlaySettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
