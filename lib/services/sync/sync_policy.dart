import 'dart:convert';
import '../../state/settings_state.dart';

/// How one synced preference is merged when two devices changed it.
enum SyncKind {
  /// One value: whoever changed it last wins (a setting, a PIN).
  scalar,

  /// A list of texts without meaning in its order (My List, watched, recent searches): both devices' additions
  /// are kept and a removal on one device is a removal on both.
  set,

  /// A JSON object kept in a string (resume positions, collections): changes to different entries both stay.
  map,

  /// A list of JSON objects with an identity (profiles, sources, reminders): same idea, by identity.
  byId,
}

/// Which preferences are synced between devices, and how. Everything not named here stays on the device:
/// where it last was, how the screen is sized, the decoder, caches, and every password.
class SyncPolicy {
  /// Settings that describe the device rather than the person, or that are passwords.
  static const deviceSettings = {
    ...SettingsState.deviceKeys,
    'decoder', 'fastStart', 'bufferSecs', 'startOnBoot', 'updating', 'lastTab',
    'lastLive', 'lastLiveOpen',
    'uiScale', 'posterSize', 'screensaver', 'watchNextRow',
    'osPass', // a password of another service: typed again on each device
  };

  static const _sets = {
    'favorites',
    'watched',
    'searches',
    'extraSources',
    'shaderEnabled'
  };
  static const _maps = {
    'positions',
    'durations',
    'deckSkips',
    'collections',
    'introSkips',
    'channelEdits',
    'profileSettings'
  };
  static const _scalars = {
    'shaderOrder',
    'shaderCustom',
    'active',
    'pinHash',
    'pinSalt'
  };

  /// The name a per-profile preference starts with (`favorites:p1abc` is `favorites` for profile p1abc).
  static String baseOf(String key) {
    final i = key.indexOf(':');
    return i < 0 ? key : key.substring(0, i);
  }

  /// How [key] is synced, or null when it stays on this device. Recents are left out on purpose: each entry
  /// carries a stream address, and for most providers that address holds the login.
  static SyncKind? kindOf(String key) {
    if (key.startsWith('sync')) return null;
    final base = baseOf(key);
    if (SettingsState.defaults.containsKey(key)) {
      return deviceSettings.contains(key) ? null : SyncKind.scalar;
    }
    if (key == 'sources' || key == 'profiles' || base == 'reminders') {
      return SyncKind.byId;
    }
    if (_sets.contains(base)) return SyncKind.set;
    if (_maps.contains(base)) return SyncKind.map;
    if (_scalars.contains(key)) return SyncKind.scalar;
    return null;
  }

  /// The identity of an element of a [SyncKind.byId] list.
  static String? idOf(String key, Map<String, dynamic> e) {
    if (key == 'profiles') return e['id'] as String?;
    if (key == 'sources') return e['name'] as String?;
    return '${e['channelKey']}|${e['startMs']}'; // a reminder
  }

  // --- What leaves the device ------------------------------------------------------------------------------

  static final _urlPassword =
      RegExp(r'((?:password|passwd|pass|pwd)=)[^&\s]*', caseSensitive: false);
  static final _userInfo = RegExp(r'^([a-z][a-z0-9+.-]*://[^/@:\s]*):[^/@\s]*@',
      caseSensitive: false);

  /// The address of a source without its password: a playlist link carries one in its query (`password=...`) or
  /// as `user:password@host`. A server address with neither is returned as it was.
  static String stripUrlPassword(String url) => url
      .replaceAllMapped(_urlPassword, (m) => m[1]!)
      .replaceFirstMapped(_userInfo, (m) => '${m[1]}@');

  /// Whether the address holds a password, or has had one taken out and needs it back.
  static bool urlHasPassword(String url) =>
      _urlPassword.hasMatch(url) || _userInfo.hasMatch(url);

  static final _blankPassword =
      RegExp(r'(?:password|passwd|pass|pwd)=(?:&|$)', caseSensitive: false);

  /// A playlist address whose password was taken out (`...&password=&...`) and not put back yet.
  static bool urlPasswordBlank(String url) =>
      _blankPassword.hasMatch(url) ||
      RegExp(r'^[a-z][a-z0-9+.-]*://[^/@:\s]*:?@', caseSensitive: false)
          .hasMatch(url);

  /// [url] with [password] put in where it was taken out.
  static String fillUrlPassword(String url, String password) {
    final enc = Uri.encodeQueryComponent(password);
    final filled = url.replaceFirstMapped(
        RegExp(r'((?:password|passwd|pass|pwd)=)(?=&|$)', caseSensitive: false),
        (m) => '${m[1]}$enc');
    if (filled != url) return filled;
    return url.replaceFirstMapped(
        RegExp(r'^([a-z][a-z0-9+.-]*://[^/@:\s]*):?@', caseSensitive: false),
        (m) => '${m[1]}:${Uri.encodeComponent(password)}@');
  }

  /// A saved source as it may leave the device: no password, in the keystore or in its address.
  static Map<String, dynamic> sanitizeSource(Map<String, dynamic> j) =>
      {...j, 'pass': '', 'url': stripUrlPassword((j['url'] as String?) ?? '')};

  /// [raw] (a preference as stored on this device) as it may be sent to the server.
  static Object? outgoing(String key, Object? raw) {
    if (key != 'sources' || raw is! List) return raw;
    return [
      for (final s in raw)
        jsonEncode(
            sanitizeSource(jsonDecode(s as String) as Map<String, dynamic>)),
    ];
  }

  /// What to store on this device for [merged] (the merge of sanitized values): a source this device already has
  /// keeps its own address and login when only the password was taken out.
  static Object? incoming(String key, Object? merged, Object? rawLocal) {
    if (key != 'sources' || merged is! List || rawLocal is! List) return merged;
    final mine = <String, String>{
      for (final s in rawLocal)
        (jsonDecode(s as String) as Map<String, dynamic>)['name'] as String: s,
    };
    return [
      for (final s in merged)
        () {
          final j = jsonDecode(s as String) as Map<String, dynamic>;
          final own = mine[j['name']];
          if (own != null &&
              jsonEncode(sanitizeSource(
                      jsonDecode(own) as Map<String, dynamic>)) ==
                  jsonEncode(j)) {
            return own;
          }
          return s;
        }(),
    ];
  }
}
