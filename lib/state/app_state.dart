import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media.dart';
import '../services/demo_catalog.dart';
import '../services/library_view.dart';
import '../services/m3u_parser.dart';
import '../services/stream_check.dart';
import '../services/net_config.dart';
import '../services/provider_url.dart';
import '../services/tmdb.dart';
import '../services/xmltv.dart';
import '../services/free_playlists.dart';
import '../services/http_client.dart';
import '../services/xtream_client.dart';
import 'profiles_state.dart';
import 'settings_state.dart';

class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;

  List<Source> sources = [];
  Source? active;
  Catalog catalog = const Catalog();
  bool loading = false;
  String? error;

  final Set<String> favorites = {};
  final List<MediaItem> recents = [];

  XtreamClient? _xtream;
  // macOS: the data-protection keychain needs signing entitlements an unsigned build lacks,
  // so use the regular keychain there.
  final _secure = const FlutterSecureStorage(mOptions: MacOsOptions(useDataProtectionKeyChain: false));
  final Map<String, int> positions = {}; // media key -> ms

  bool get ready => active != null && !loading && error == null;

  // --- View of the library (hide-adult / sort options) ---------------------------------

  SettingsState? _settings;
  ProfilesState? _profiles;
  bool _lastAdult = false, _lastSort = false, _lastHideDead = false;
  Catalog? _viewSrc;
  bool _viewAdult = false, _viewSort = false, _viewHideDead = false, _viewKids = false;
  int _viewVer = -1, _ver = 0;
  Catalog _view = const Catalog();

  /// Connects user preferences; only the ones that change what is listed rebuild the UI.
  void bindSettings(SettingsState s) {
    _settings = s;
    _lastAdult = s.hideAdult;
    _lastSort = s.sortAz;
    _lastHideDead = s.hideDead;
    s.addListener(() {
      if (s.hideAdult != _lastAdult || s.sortAz != _lastSort || s.hideDead != _lastHideDead) {
        _lastAdult = s.hideAdult;
        _lastSort = s.sortAz;
        _lastHideDead = s.hideDead;
        notifyListeners();
      }
    });
  }

  // --- Profiles ---------------------------------------------------------------------------

  String _pid = 'main';

  /// Storage key for personal data: the Main profile keeps the original keys, so nothing
  /// saved before profiles existed moves.
  String _k(String base) => _pid == 'main' ? base : '$base:$_pid';

  /// Connects the profiles; switching profile swaps favorites, history and resume positions.
  void bindProfiles(ProfilesState p) {
    _profiles = p;
    _pid = p.current.id;
    var kids = p.current.kids;
    p.addListener(() {
      final changed = p.current.id != _pid;
      if (changed) {
        _pid = p.current.id;
        _loadPersonal();
      }
      if (changed || p.current.kids != kids) {
        kids = p.current.kids;
        _ver++;
        notifyListeners();
      }
    });
  }

  /// Removes everything a deleted profile saved.
  Future<void> forgetProfile(String id) async {
    for (final base in const ['favorites', 'positions', 'recents']) {
      await _prefs?.remove('$base:$id');
    }
  }

  void _loadPersonal() {
    final p = _prefs;
    favorites.clear();
    recents.clear();
    positions.clear();
    if (p == null) return;
    final pos = p.getString(_k('positions'));
    if (pos != null) {
      positions.addAll((jsonDecode(pos) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)));
    }
    favorites.addAll(p.getStringList(_k('favorites')) ?? const []);
    recents.addAll([
      for (final s in (p.getStringList(_k('recents')) ?? const []))
        MediaItem.fromJson(jsonDecode(s) as Map<String, dynamic>),
    ]);
  }

  /// The catalog as it should be displayed: [catalog] with the user's filters applied.
  Catalog get shown {
    final adult = _settings?.hideAdult ?? false;
    final sort = _settings?.sortAz ?? false;
    final hideDead = (_settings?.hideDead ?? false) && deadKeys.isNotEmpty;
    final kids = _profiles?.current.kids ?? false;
    if (!identical(_viewSrc, catalog) ||
        adult != _viewAdult ||
        sort != _viewSort ||
        hideDead != _viewHideDead ||
        kids != _viewKids ||
        _ver != _viewVer) {
      _view = buildView(catalog,
          hideAdult: adult, sortAz: sort, hideKeys: hideDead ? deadKeys : const {}, kidsOnly: kids);
      _viewSrc = catalog;
      _viewAdult = adult;
      _viewSort = sort;
      _viewHideDead = hideDead;
      _viewKids = kids;
      _viewVer = _ver;
    }
    return _view;
  }

  /// True when an M3U-style link was upgraded to the provider's Xtream API.
  bool get usingXtreamApi => _xtream != null;

  /// The provider's account details (expiry, connections) when an Xtream login is in use.
  AccountInfo? get account => _xtream?.account;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    sources = [];
    for (final raw in (p.getStringList('sources') ?? const [])) {
      final src = Source.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      sources.add(Source(
        name: src.name,
        type: src.type,
        url: src.url,
        username: src.username,
        password: await _readSecret(src.name) ?? '',
      ));
    }
    _loadPersonal();
    _loadDead();
    final last = p.getString('active');
    if (last != null) {
      final match = sources.where((s) => s.name == last);
      if (match.isNotEmpty) {
        await activate(match.first);
      } else if (last == Source.demo.name) {
        await activate(Source.demo);
      }
    }
    notifyListeners();
  }

  // Passwords live in the platform keystore, never in shared_preferences.
  Future<String?> _readSecret(String name) async {
    try {
      return await _secure.read(key: 'pass:$name');
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSecret(String name, String? value) async {
    try {
      value == null || value.isEmpty
          ? await _secure.delete(key: 'pass:$name')
          : await _secure.write(key: 'pass:$name', value: value);
    } catch (_) {}
  }

  Future<void> _saveSources() async => _prefs?.setStringList('sources', [
        for (final e in sources) jsonEncode((e.toJson()..['pass'] = '')),
      ]);

  Future<void> addSource(Source s) async {
    sources = [...sources.where((e) => e.name != s.name), s];
    await _writeSecret(s.name, s.password);
    await _saveSources();
    await activate(s);
  }

  Future<void> removeSource(Source s) async {
    sources = sources.where((e) => e.name != s.name).toList();
    await _writeSecret(s.name, null);
    await _saveSources();
    if (active?.name == s.name) {
      active = null;
      catalog = const Catalog();
      await _prefs?.remove('active');
    }
    notifyListeners();
  }

  Future<void> activate(Source s) async {
    loading = true;
    error = null;
    active = s;
    notifyListeners();
    try {
      switch (s.type) {
        case SourceType.demo:
          catalog = demoCatalog();
          _xtream = null;
        case SourceType.m3u:
          {
            _xtream = null;
            // Several playlist addresses, one per line, load and merge into one library.
            final urls = s.url.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            if (urls.length > 1) {
              catalog = await loadMergedPlaylists(urls);
              break;
            }
            // A provider's get.php?username=..&password=.. link is the Xtream panel in disguise.
            // Its API gives proper movies, series, posters and guide data, so prefer it and
            // fall back to the plain playlist when the panel doesn't answer.
            final login = parseProviderLink(s.url);
            if (login != null && Uri.tryParse(s.url)?.path.endsWith('get.php') == true) {
              try {
                final api = XtreamClient(login.server, login.username, login.password);
                await api.authenticate();
                catalog = await api.loadCatalog();
                _xtream = api;
              } catch (_) {
                _xtream = null;
              }
            }
            if (_xtream == null) {
              final res = await appHttp.get(Uri.parse(s.url), headers: NetConfig.headers).timeout(const Duration(seconds: 60));
              if (res.statusCode != 200) throw Exception('Playlist returned ${res.statusCode}');
              catalog = parseM3u(utf8.decode(res.bodyBytes, allowMalformed: true));
            }
          }
        case SourceType.xtream:
          final c = XtreamClient(s.url, s.username, s.password);
          await c.authenticate();
          catalog = await c.loadCatalog();
          _xtream = c;
      }
      _guideLoaded = false;
      guide = XmltvData.empty;
      await _prefs?.setString('active', s.name);
    } catch (e) {
      error = friendlyError(e);
      catalog = const Catalog();
    }
    loading = false;
    notifyListeners();
  }

  void signOut() {
    active = null;
    error = null;
    catalog = const Catalog();
    _prefs?.remove('active');
    notifyListeners();
  }

  /// Provider-side details for the movie / series page (null without an Xtream source).
  Future<TmdbInfo?> providerInfo(MediaItem i) async {
    final c = _xtream;
    if (c == null || i.kind == MediaKind.live || i.id.startsWith('ep')) return null;
    try {
      return i.kind == MediaKind.series ? await c.seriesInfo(i.id) : await c.vodInfo(i.id);
    } catch (_) {
      return null;
    }
  }

  Future<List<Episode>> episodes(MediaItem series) async =>
      _xtream?.episodes(series.id) ?? [];

  bool isFavorite(MediaItem i) => favorites.contains(i.key);

  void toggleFavorite(MediaItem i) {
    if (!favorites.remove(i.key)) favorites.add(i.key);
    _prefs?.setStringList(_k('favorites'), favorites.toList());
    notifyListeners();
  }

  List<MediaItem> get favoriteItems =>
      shown.all.where((i) => favorites.contains(i.key)).toList();

  void markWatched(MediaItem i) {
    recents.removeWhere((e) => e.key == i.key);
    recents.insert(0, i);
    if (recents.length > 20) recents.removeLast();
    _prefs?.setStringList(
        _k('recents'), [for (final e in recents) jsonEncode(e.toJson())]);
    notifyListeners();
  }

  // --- Clearing personal data ---------------------------------------------------------

  void clearRecents() {
    recents.clear();
    _prefs?.remove(_k('recents'));
    notifyListeners();
  }

  void clearPositions() {
    positions.clear();
    _prefs?.remove(_k('positions'));
    notifyListeners();
  }

  void clearFavorites() {
    favorites.clear();
    _prefs?.remove(_k('favorites'));
    notifyListeners();
  }

  // --- Resume positions -------------------------------------------------

  Duration? resumeFor(MediaItem i) {
    final ms = positions[i.key];
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// Persists the resume position. Pass [notify] on the final save so screens
  /// underneath the player (e.g. the detail screen's "Resume from") refresh;
  /// periodic saves stay silent to avoid rebuilding the app every few seconds.
  void savePosition(MediaItem i, Duration pos, Duration total, {bool notify = false}) {
    if (i.kind == MediaKind.live || total.inSeconds < 60) return;
    // Treat the last 3% as finished.
    if (pos.inMilliseconds > total.inMilliseconds * 0.97) {
      positions.remove(i.key);
    } else if (pos.inSeconds > 10) {
      positions[i.key] = pos.inMilliseconds;
    }
    _prefs?.setString(_k('positions'), jsonEncode(positions));
    // Deferred: this runs from State.dispose(), where notifying synchronously would
    // mark widgets dirty while the tree is locked.
    if (notify) Future.microtask(notifyListeners);
  }

  // --- EPG --------------------------------------------------------------

  Future<List<EpgEntry>> epg(MediaItem live) async =>
      _xtream == null ? const [] : _xtream!.shortEpg(live.id);

  // --- Backup / restore ---------------------------------------------------

  /// Sources (without passwords), favorites, resume positions, recents.
  Map<String, dynamic> exportData() => {
        'sources': [for (final e in sources) e.toJson()..['pass'] = ''],
        'favorites': favorites.toList(),
        'positions': positions,
        'recents': [for (final r in recents) r.toJson()],
      };

  void importData(Map<String, dynamic> m) {
    for (final j in (m['sources'] as List? ?? const [])) {
      final src = Source.fromJson(j as Map<String, dynamic>);
      if (!sources.any((e) => e.name == src.name)) sources.add(src);
    }
    favorites.addAll([for (final f in (m['favorites'] as List? ?? const [])) '$f']);
    positions.addAll((m['positions'] as Map? ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt())));
    final have = recents.map((e) => e.key).toSet();
    for (final j in (m['recents'] as List? ?? const [])) {
      final it = MediaItem.fromJson(j as Map<String, dynamic>);
      if (have.add(it.key)) recents.add(it);
    }
    _prefs?.setStringList(_k('favorites'), favorites.toList());
    _prefs?.setString(_k('positions'), jsonEncode(positions));
    _prefs?.setStringList(_k('recents'), [for (final e in recents) jsonEncode(e.toJson())]);
    _saveSources();
    notifyListeners();
  }

  // --- Dead-stream check -------------------------------------------------------------------

  /// Per source: keys of live channels that failed a check, and how many channels were checked.
  final Map<String, Set<String>> _dead = {};
  final Map<String, int> _checked = {};
  bool checking = false;
  int checkDone = 0, checkTotal = 0, checkDeadSoFar = 0;
  bool _cancelCheck = false;

  Set<String> get deadKeys => _dead[active?.name] ?? const {};
  int get checkedCount => _checked[active?.name] ?? 0;
  bool isDead(MediaItem i) => deadKeys.contains(i.key);

  /// Browsers cannot read another site's streams, so the check is for the apps only.
  bool get canCheck => !kIsWeb && catalog.live.isNotEmpty;

  void _loadDead() {
    final raw = _prefs?.getString('deadStreams');
    if (raw == null) return;
    try {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
        final o = v as Map<String, dynamic>;
        _dead[k] = {for (final e in (o['dead'] as List)) '$e'};
        _checked[k] = (o['n'] as num).toInt();
      });
    } catch (_) {}
  }

  void _saveDead() => _prefs?.setString('deadStreams', jsonEncode({
        for (final e in _dead.entries) e.key: {'dead': e.value.toList(), 'n': _checked[e.key] ?? 0},
      }));

  /// Tests every live channel of the current source and remembers the ones that do not answer.
  Future<void> checkLive() async {
    final src = active;
    if (src == null || checking || !canCheck) return;
    final items = [...catalog.live];
    checking = true;
    _cancelCheck = false;
    checkDone = 0;
    checkDeadSoFar = 0;
    checkTotal = items.length;
    notifyListeners();
    final dead = <String>{};
    var lastNotify = DateTime.now();
    // A login usually allows only a couple of streams at once, so go slowly there. A public list
    // has no such limit.
    final parallel = _xtream != null || src.type == SourceType.xtream ? 2 : 10;
    await checkStreams(items, parallel: parallel, cancelled: () => _cancelCheck,
        onResult: (item, problem, done) {
      if (problem != null) dead.add(item.key);
      checkDone = done;
      checkDeadSoFar = dead.length;
      final now = DateTime.now();
      if (now.difference(lastNotify).inMilliseconds > 400) {
        lastNotify = now;
        notifyListeners();
      }
    });
    // A stopped check keeps what it found; the next one starts over.
    _dead[src.name] = _cancelCheck ? {...deadKeys, ...dead} : dead;
    _checked[src.name] = _cancelCheck ? checkDone : items.length;
    _saveDead();
    checking = false;
    _ver++;
    notifyListeners();
  }

  void cancelCheck() => _cancelCheck = true;

  void forgetCheck() {
    final n = active?.name;
    if (n == null) return;
    _dead.remove(n);
    _checked.remove(n);
    _saveDead();
    _ver++;
    notifyListeners();
  }

  // --- XMLTV guide --------------------------------------------------------

  XmltvData guide = XmltvData.empty;
  bool guideLoading = false;
  String? guideError;
  bool _guideLoaded = false;

  Uri? get _guideUri =>
      _xtream?.xmltvUri ?? (catalog.epgUrl == null ? null : Uri.tryParse(catalog.epgUrl!));

  bool get hasGuideSource => _guideUri != null;

  /// Loads and parses the XMLTV guide once per library load (8h window).
  Future<void> loadGuide({bool force = false}) async {
    final uri = _guideUri;
    if (uri == null || guideLoading || (_guideLoaded && !force)) return;
    guideLoading = true;
    guideError = null;
    notifyListeners();
    try {
      final res = await appHttp.get(uri, headers: NetConfig.headers).timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) throw Exception('Guide returned ${res.statusCode}');
      final now = DateTime.now();
      guide = await compute(parseXmltvBytesJob, <Object>[
        res.bodyBytes,
        now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
      ]);
      _guideLoaded = true;
    } catch (e) {
      guideError = e.toString().replaceFirst('Exception: ', '');
    }
    guideLoading = false;
    notifyListeners();
  }

  /// Programmes for a channel, matched by tvg-id, then by channel name.
  List<Programme> programmesFor(MediaItem ch) {
    final byId = ch.epgId == null ? null : guide.programmes[ch.epgId!.toLowerCase()];
    if (byId != null) return byId;
    final id = guide.nameToId[ch.name.trim().toLowerCase()];
    return id == null ? const [] : (guide.programmes[id] ?? const []);
  }
}
