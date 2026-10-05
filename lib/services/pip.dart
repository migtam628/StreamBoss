import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android picture-in-picture via a tiny native channel (see tool/patch_android.dart,
/// which installs the matching MainActivity). Everywhere else this is a no-op.
class Pip {
  static const _channel = MethodChannel('com.streamboss/pip');
  static final _changes = StreamController<bool>.broadcast();
  static bool _wired = false;

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Emits true when the app enters PiP and false when it leaves.
  static Stream<bool> get changes {
    if (_android && !_wired) {
      _wired = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') _changes.add(call.arguments == true);
      });
    }
    return _changes.stream;
  }

  static Future<bool> get available async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enter() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }
}
