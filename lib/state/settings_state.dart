import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';
import '../layouts/ui_layout.dart';
import '../services/net_config.dart';
import '../services/shaders.dart';
import 'profiles_state.dart';

/// All user preferences. Every key has a typed default; [set] validates the type, persists,
/// applies side effects and notifies. Storage keys are stable (older versions' values keep working).
class SettingsState extends ChangeNotifier {
  SharedPreferences? _p;

  static const Map<String, Object> defaults = {
    // playback
    'decoder': 'auto', // auto | software (native only)
    'videoOutput': 'auto', // auto | surface | compat (Android only, see [surfaceOutput])
    'bufferSecs': 20, // low 5 / normal 20 / high 60 (native only)
    'speed': 1.0,
    'autoResume': true,
    'autoplayNext': true, // start the next episode when one ends
    'aspect': 'auto', // picture shape in the player: auto | 16:9 | 4:3 | fill | stretch
    'seekSecs': 10,
    'skipSecs': 90,
    'controlsHideSecs': 5, // 0 = never
    'audioLang': '', // mpv language list, '' = automatic
    'subLang': '',
    'subsOn': true,
    // subtitles
    'subSize': 36.0,
    'subColor': 0xFFFFFFFF,
    'subBg': true,
    'subBold': false,
    'subBottom': 48.0,
    // appearance
    'uiScale': 1.0,
    'posterSize': 1.0,
    'startTab': 0,
    'tvMode': 'auto', // auto | on | off
    'tvWidth': 1280, // TV mode lays the UI out on a canvas this many logical pixels wide
    'onboarded': false, // the first-run setup has been done or skipped (this device)
    'layout': 'marquee', // marquee | control | spotlight
    'screensaver': 'auto', // auto | off | 2 | 5 | 10 | 20 | 30 (minutes idle). Auto is 10 on a TV, off elsewhere
    'accentColor': 0, // 0 = the layout's own accent, else an ARGB color
    'background': 'layout', // layout | black | charcoal | midnight | forest | plum | paper
    'appIcon': 'crown', // crown | bold | signal | screen (this device)
    // library & guide
    'hideAdult': false,
    'sortAz': false,
    'mergeDuplicates': true, // show one entry for the same channel offered several times
    'hideDead': false, // hide live channels that failed a check
    'livePreview': true, // show a live picture in the Cable Box and Mosaic layouts
    'use24h': true,
    // network & metadata
    'userAgent': '',
    'tmdbKey': '',
    'osKey': '', // OpenSubtitles API key, username and password (subtitle search)
    'osUser': '',
    'osPass': '',
    'realPosters': true, // fill in missing posters from TMDB (needs the key)
  };

  /// Keys that must never leave the device (backups, diagnostics).
  static const secretKeys = {'tmdbKey', 'osKey', 'osUser', 'osPass'};

  /// Describes this device rather than the user's taste, so backups don't carry it over.
  static const deviceKeys = {'tvMode', 'tvWidth', 'layout', 'videoOutput', 'onboarded', 'appIcon'};

  /// Set at startup from [DeviceInfo]; tests set it directly.
  static bool detectedTv = false;

  final Map<String, Object> _v = {...defaults};

  // Shader library: pipeline order, enabled set, user-added shaders.
  List<ShaderDef> customShaders = [];
  List<String> shaderOrder = [];
  Set<String> shaderEnabled = {};

  /// The settings a profile can have of its own (see [Profile.ownSettings]): how it looks, what it reads
  /// and hears, and what it hides. Everything else is about the device and stays shared.
  static const profileKeys = {
    'layout', 'accentColor', 'background', 'uiScale', 'posterSize', 'startTab', 'audioLang', 'subLang', 'subsOn', 'subSize', 'subColor',
    'subBg', 'subBold', 'subBottom', 'hideAdult', 'sortAz', 'use24h', 'mergeDuplicates', 'livePreview',
  };

  // The values of the profile in use when it has its own settings; they win over the shared ones.
  Map<String, Object>? _o;
  String? _oId;

  T _g<T>(String k) => ((_o != null && _o!.containsKey(k)) ? _o![k] : _v[k]) as T;

  /// True while the profile in use has settings of its own.
  bool get hasProfileOverlay => _o != null;

  /// Follows the profile in use: one that has its own settings gets them, others get the shared ones.
  void bindProfiles(ProfilesState p) {
    _syncProfile(p, notify: false);
    p.addListener(() => _syncProfile(p));
  }

  void _syncProfile(ProfilesState p, {bool notify = true}) {
    final cur = p.current;
    if (!cur.ownSettings) {
      // Turning it off forgets the own settings; just moving to another profile keeps them.
      if (_oId == cur.id && _o != null) _p?.remove('profileSettings:$_oId');
      final had = _o != null;
      _o = null;
      _oId = null;
      if (had && notify) notifyListeners();
      return;
    }
    if (_o != null && _oId == cur.id) return;
    Map<String, Object>? loaded;
    try {
      final raw = _p?.getString('profileSettings:${cur.id}');
      if (raw != null) {
        loaded = {};
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          final c = profileKeys.contains(k) ? _coerce(k, v as Object) : null;
          if (c != null) loaded![k] = c;
        });
      }
    } catch (_) {
      loaded = null;
    }
    // First time: start from what is in use now, so turning it on changes nothing you can see.
    _o = loaded ?? {for (final k in profileKeys) k: _v[k]!};
    _oId = cur.id;
    if (loaded == null) _saveOverlay();
    if (notify) notifyListeners();
  }

  void _saveOverlay() {
    if (_o == null || _oId == null) return;
    _p?.setString('profileSettings:$_oId', jsonEncode(_o));
  }

  String get decoder => _g('decoder');
  int get bufferSecs => _g('bufferSecs');
  double get speed => _g('speed');
  bool get autoResume => _g('autoResume');
  bool get autoplayNext => _g('autoplayNext');
  String get appIcon => _g('appIcon');
  String get aspect => _g('aspect');
  int get seekSecs => _g('seekSecs');
  int get skipSecs => _g('skipSecs');
  int get controlsHideSecs => _g('controlsHideSecs');
  String get audioLang => _g('audioLang');
  String get subLang => _g('subLang');
  bool get subsOn => _g('subsOn');
  double get subSize => _g('subSize');
  int get subColor => _g('subColor');
  bool get subBackground => _g('subBg');
  bool get subBold => _g('subBold');
  double get subBottom => _g('subBottom');
  double get uiScale => _g('uiScale');
  double get posterSize => _g('posterSize');
  int get startTab => _g('startTab');
  String get tvMode => _g('tvMode');

  /// TV ("10-foot") mode: on when forced, or when auto and a TV was detected.
  bool get isTv => tvMode == 'on' || (tvMode == 'auto' && detectedTv);

  String get videoOutput => _g('videoOutput');

  /// Android only: hand video straight from the hardware decoder to the screen (libmpv's
  /// `mediacodec_embed`) instead of copying every frame through the GPU. Much lighter for movies
  /// on a Fire TV or Android TV box, but libmpv then can't draw embedded subtitles or shaders.
  /// Automatic means on for TVs. Software decoding always uses the GPU path.
  bool get surfaceOutput {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (decoder == 'software') return false;
    return videoOutput == 'surface' || (videoOutput == 'auto' && isTv);
  }

  /// Width in logical pixels of the canvas the TV layout is drawn on (see TvCanvas). A smaller
  /// number zooms in, a larger one zooms out.
  int get tvWidth => _g('tvWidth');

  bool get onboarded => _g('onboarded');

  UiLayout get layout => UiLayout.fromKey(_g<String>('layout'));

  /// The accent the viewer picked, or null to keep the layout's own.
  Color? get accent => _g<int>('accentColor') == 0 ? null : Color(_g<int>('accentColor'));
  String get background => _g('background');
  String get screensaver => _g('screensaver');

  /// Minutes without input before the screensaver starts; 0 = never.
  int get screensaverMinutes {
    final v = _g<String>('screensaver');
    if (v == 'auto') return isTv ? 10 : 0;
    return int.tryParse(v) ?? 0;
  }

  /// Text and poster scales as applied. TV mode no longer adds to them: the TV canvas sets the size.
  double get textScale => uiScale;
  double get posterScale => posterSize;
  bool get hideAdult => _g('hideAdult');
  bool get sortAz => _g('sortAz');
  bool get hideDead => _g('hideDead');
  bool get mergeDuplicates => _g('mergeDuplicates');
  bool get livePreview => _g('livePreview');
  bool get use24h => _g('use24h');
  String get userAgent => _g('userAgent');
  String get tmdbKey => _g('tmdbKey');
  String get osKey => _g('osKey');
  String get osUser => _g('osUser');
  String get osPass => _g('osPass');
  bool get realPosters => _g('realPosters');

  /// All shaders in pipeline order.
  List<ShaderDef> get shaders {
    final all = [...builtinShaders, ...customShaders];
    final byId = {for (final s in all) s.id: s};
    return [for (final id in reconcileOrder(shaderOrder, all)) byId[id]!];
  }

  /// Enabled shaders, in order, ready to hand to the player.
  List<ShaderDef> get activeShaders => [for (final s in shaders) if (shaderEnabled.contains(s.id)) s];

  Future<void> init() async {
    final p = _p = await SharedPreferences.getInstance();
    for (final e in defaults.entries) {
      final d = e.value;
      final stored = d is bool
          ? p.getBool(e.key)
          : d is int
              ? p.getInt(e.key)
              : d is double
                  ? p.getDouble(e.key)
                  : p.getString(e.key);
      if (stored != null) _v[e.key] = stored;
    }
    customShaders = [
      for (final j in (p.getStringList('shaderCustom') ?? const []))
        ShaderDef.fromJson(jsonDecode(j) as Map<String, dynamic>),
    ];
    shaderOrder = p.getStringList('shaderOrder') ?? [];
    shaderEnabled = (p.getStringList('shaderEnabled') ?? const []).toSet();
    NetConfig.userAgent = userAgent;
  }

  /// Coerces numbers to the key's type; returns null if [value] doesn't fit.
  static Object? _coerce(String key, Object value) {
    final d = defaults[key];
    if (d == null) return null;
    if (d is double && value is num) return value.toDouble();
    if (d is int && value is num) return value.round();
    if (d is bool && value is bool) return value;
    if (d is String && value is String) return value;
    return null;
  }

  void _persist(String key, Object value) {
    final p = _p;
    if (p == null) return;
    if (value is bool) {
      p.setBool(key, value);
    } else if (value is int) {
      p.setInt(key, value);
    } else if (value is double) {
      p.setDouble(key, value);
    } else if (value is String) {
      p.setString(key, value);
    }
  }

  void set(String key, Object value, {bool notify = true}) {
    final v = _coerce(key, value);
    if (v == null) throw ArgumentError('Bad setting $key=$value');
    if (_o != null && profileKeys.contains(key)) {
      _o![key] = v;
      _saveOverlay();
    } else {
      _v[key] = v;
      _persist(key, v);
    }
    if (key == 'userAgent') NetConfig.userAgent = v as String;
    if (notify) notifyListeners();
  }

  bool isDefault(String key) => _g<Object>(key) == defaults[key];

  /// Restores every preference (and the shader toggles) to its default. Sources,
  /// My List and resume positions are not touched.
  void resetAll() {
    for (final k in defaults.keys) {
      _p?.remove(k);
    }
    if (_o != null) {
      _o = {for (final k in profileKeys) k: defaults[k]!};
      _saveOverlay();
    }
    _v
      ..clear()
      ..addAll(defaults);
    NetConfig.userAgent = '';
    shaderEnabled = {};
    shaderOrder = [];
    _p?.remove('shaderEnabled');
    _p?.remove('shaderOrder');
    notifyListeners();
  }

  void setShaders({List<String>? order, Set<String>? enabled, List<ShaderDef>? custom}) {
    shaderOrder = order ?? shaderOrder;
    shaderEnabled = enabled ?? shaderEnabled;
    customShaders = custom ?? customShaders;
    final p = _p;
    if (p != null) {
      p.setStringList('shaderOrder', shaderOrder);
      p.setStringList('shaderEnabled', shaderEnabled.toList());
      p.setStringList('shaderCustom', [for (final c in customShaders) jsonEncode(c.toJson())]);
    }
    notifyListeners();
  }

  /// Settings as JSON-able data for backups and diagnostics. Secrets (API keys) are left out
  /// unless [includeSecrets] is set.
  Map<String, dynamic> toMap({bool includeSecrets = false}) => {
        for (final e in _v.entries)
          if (includeSecrets || !secretKeys.contains(e.key)) e.key: e.value,
        'shaderOrder': shaderOrder,
        'shaderEnabled': shaderEnabled.toList(),
        'shaderCustom': [for (final c in customShaders) c.toJson()],
      };

  /// Applies known keys with matching types; unknown or mistyped entries are ignored, so
  /// backups from other versions restore what they can.
  void applyMap(Map<String, dynamic> m) {
    for (final e in m.entries) {
      final v = e.value;
      if (v == null || secretKeys.contains(e.key) || deviceKeys.contains(e.key)) continue;
      final c = _coerce(e.key, v as Object);
      if (c != null) set(e.key, c, notify: false);
    }
    notifyListeners();
  }

  void applyShaderMap(Map<String, dynamic> m) => setShaders(
        order: [for (final x in (m['shaderOrder'] as List? ?? const [])) '$x'],
        enabled: {for (final x in (m['shaderEnabled'] as List? ?? const [])) '$x'},
        custom: [
          for (final j in (m['shaderCustom'] as List? ?? const []))
            ShaderDef.fromJson(j as Map<String, dynamic>),
        ],
      );
}
