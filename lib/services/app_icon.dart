import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The icons the app can wear (Settings > Appearance > App icon). The art is drawn in
/// design/make_icons.mjs; the same names are used by tool/patch_android.dart (the launcher aliases) and
/// the previews in assets/app_icons.
enum AppIcon {
  crown('Crown', 'A crown with a play button cut out of it.'),
  bold('Bold B', 'A heavy B with a play button in its bowl.'),
  signal('Signal', 'A play button sending out waves.'),
  screen('Screen', 'A TV with a play button.');

  final String label, blurb;
  const AppIcon(this.label, this.blurb);

  String get asset => 'assets/app_icons/$name.png';

  static AppIcon fromKey(String? key) => AppIcon.values.firstWhere((e) => e.name == key, orElse: () => AppIcon.crown);
}

/// Changes the icon of the installed app.
///  * Android and Android TV: switches the launcher entry (the manifest has one alias per icon). The
///    launcher may take a few seconds to show it, and some hide the app for a moment.
///  * macOS: sets the Dock icon. macOS forgets it when the app quits, so [restore] sets it again at start.
///  * Elsewhere the icon is fixed at install time and [supported] is false.
class AppIconService {
  static const _channel = MethodChannel('com.streamboss/app_icon');

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _mac => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get supported => _android || _mac;

  /// What the system says is active, or null when it cannot tell (macOS) or on error.
  static Future<AppIcon?> current() async {
    if (!_android) return null;
    try {
      final v = await _channel.invokeMethod<String>('current');
      return v == null ? null : AppIcon.fromKey(v);
    } catch (_) {
      return null;
    }
  }

  /// True when the system accepted the change.
  static Future<bool> set(AppIcon icon) async {
    try {
      if (_android) return await _channel.invokeMethod<bool>('set', icon.name) ?? false;
      if (_mac) {
        final data = await rootBundle.load(icon.asset);
        return await _channel.invokeMethod<bool>('setDockIcon', data.buffer.asUint8List()) ?? false;
      }
    } catch (_) {}
    return false;
  }

  /// Puts the chosen icon back where the system does not keep it (macOS).
  static Future<void> restore(AppIcon icon) async {
    if (_mac) await set(icon);
  }
}
