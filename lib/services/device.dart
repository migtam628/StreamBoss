import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What kind of device we are on. Only Android can tell us it is a TV (Android TV, Google TV,
/// Fire TV); everything else reports false and relies on the manual "TV mode" setting.
class DeviceInfo {
  static const _channel = MethodChannel('com.streamboss/pip'); // shared with MainActivity (tool/patch_android.dart)

  /// True on Android TV / Google TV / Fire TV. Set once at startup by [init].
  static bool isTv = false;

  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } catch (_) {
      isTv = false;
    }
  }
}
