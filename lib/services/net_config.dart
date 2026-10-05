import 'package:flutter/foundation.dart' show kIsWeb;

/// Process-wide network options that every HTTP call (and the player) reads.
class NetConfig {
  /// Empty = the platform default. Some IPTV panels only answer familiar player User-Agents.
  static String userAgent = '';

  /// Browsers refuse to let pages set User-Agent, so it is skipped on web.
  static Map<String, String> get headers =>
      (kIsWeb || userAgent.isEmpty) ? const {} : {'User-Agent': userAgent};

  static const presets = <String, String>{
    'VLC': 'VLC/3.0.20 LibVLC/3.0.20',
    'Chrome': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  };
}
