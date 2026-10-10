import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media.dart';
import '../services/combine_sources.dart';
import '../services/demo_catalog.dart';
import '../services/library_view.dart';
import '../services/m3u_parser.dart';
import '../services/recommend.dart';
import '../services/search.dart';
import '../services/skip_memory.dart';
import '../services/stream_check.dart';
import '../services/net_config.dart';
import '../services/provider_url.dart';
import '../services/anime.dart';
import '../services/catalog_cache.dart';
import '../services/perf_log.dart';
import '../services/languages.dart';
import '../services/channel_edits.dart';
import '../services/channel_filter.dart';
import '../services/vod_filter.dart';
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

  /// My list, in the order the viewer keeps it (newest last until moved).
  final Set<String> favorites = {};
  final List<MediaItem> recents = [];

  XtreamClient? _xtream;
  // macOS: the data-protection keychain needs signing entitlements an unsigned build lacks,
  // so use the regular keychain there.
  final _secure = const FlutterSecureStorage(mOptions: MacOsOptions(useDataProtectionKeyChain: false));
  final Map<String, int> positions = {}; // media key -> ms
  final Map<String, int> durations = {}; // media key -> ms, noted when a title is played
  final Set<String> watched = {}; // media keys finished or marked watched

  bool get ready => active != null && !loading && error == null;

  // --- View of the library (hide-adult / sort options) ---------------------------------

  SettingsState? _settings;
  ProfilesState? _profiles;
  bool _lastAdult = false, _lastSort = false, _lastHideDead = false, _lastMerge = true;
  Catalog? _viewSrc;
  bool _viewAdult = false, _viewSort = false, _viewHideDead = false, _viewKids = false, _viewMerge = false;
  final Map<String, List<MediaItem>> _alternates = {};
  int _viewVer = -1, _ver = 0;
  Catalog _view = const Catalog();

  /// Connects user preferences; only the ones that change what is listed rebuild the UI.
  void bindSettings(SettingsState s) {
    _settings = s;
    _lastAdult = s.hideAdult;
    _lastSort = s.sortAz;
    _lastHideDead = s.hideDead;
    _lastMerge = s.mergeDuplicates;
    s.addListener(() {
      if (s.hideAdult != _lastAdult ||
          s.sortAz != _lastSort ||
          s.hideDead != _lastHideDead ||
          s.mergeDuplicates != _lastMerge) {
        _lastAdult = s.hideAdult;
        _lastSort = s.sortAz;
        _lastHideDead = s.hideDead;
        _lastMerge = s.mergeDuplicates;
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
    for (final base in const ['favorites', 'positions', 'recents', 'searches', 'collections', 'profileSettings', 'deckSkips', 'channelEdits', 'introSkips', 'watched', 'durations']) {
      await _prefs?.remove('$base:$id');
    }
  }

  void _loadPersonal() {
    final p = _prefs;
    favorites.clear();
    recents.clear();
    positions.clear();
    durations.clear();
    watched.clear();
    recentSearches.clear();
    collections.clear();
    deckSkips.clear();
    channelEdits.clear();
    introSkips.clear();
    _animeSrc = null;
    if (p == null) return;
    try {
      final raw = p.getString(_k('channelEdits'));
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        (m['edits'] as Map? ?? const {}).forEach((k, v) => channelEdits.edits['$k'] = ChannelEdit.fromJson(v as Map<String, dynamic>));
        channelEdits.pins.addAll([for (final e in (m['pins'] as List? ?? const [])) '$e']);
      }
    } catch (_) {}
    try {
      final raw = p.getString(_k('introSkips'));
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) => introSkips[k] = IntroWindow.fromJson(v as Map<String, dynamic>));
      }
    } catch (_) {}
    try {
      final raw = p.getString(_k('deckSkips'));
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) => deckSkips[k] = v as int);
      }
    } catch (_) {}
    try {
      final raw = p.getString(_k('collections'));
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) => collections[k] = [for (final e in (v as List)) '$e']);
      }
    } catch (_) {}
    recentSearches.addAll(p.getStringList(_k('searches')) ?? const []);
    final pos = p.getString(_k('positions'));
    if (pos != null) {
      positions.addAll((jsonDecode(pos) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)));
    }
    try {
      final d = p.getString(_k('durations'));
      if (d != null) durations.addAll((jsonDecode(d) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)));
    } catch (_) {}
    watched.addAll(p.getStringList(_k('watched')) ?? const []);
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
    final merge = _settings?.mergeDuplicates ?? false;
    if (!identical(_viewSrc, catalog) ||
        adult != _viewAdult ||
        sort != _viewSort ||
        hideDead != _viewHideDead ||
        kids != _viewKids ||
        merge != _viewMerge ||
        _ver != _viewVer) {
      _alternates.clear();
      _view = buildView(catalog,
          hideAdult: adult,
          sortAz: sort,
          hideKeys: hideDead ? deadKeys : const {},
          kidsOnly: kids,
          mergeDuplicates: merge,
          deadKeys: deadKeys,
          channelEdits: channelEdits,
          alternatesOut: _alternates);
      _viewMerge = merge;
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

  /// Loads what is saved on this device. With [waitForLibrary] false (the app's start-up) it does not
  /// wait for the library at all: the app comes up with `loading` on, a saved copy of the library
  /// replaces that as soon as it is read (and is refreshed behind it), and with no saved copy the
  /// library loads from the provider while the connect screen shows its progress.
  Future<void> init({bool waitForLibrary = true}) async {
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
    extraSources.addAll(p.getStringList('extraSources') ?? const []);
    final last = p.getString('active');
    if (last != null) {
      final match = sources.where((s) => s.name == last);
      final src = match.isNotEmpty ? match.first : (last == Source.demo.name ? Source.demo : null);
      if (src != null) {
        if (waitForLibrary) {
          await activate(src);
        } else {
          // The app comes up at once; the library arrives behind it (from the saved copy when there is
          // one, else from the provider).
          active = src;
          loading = true;
          unawaited(() async {
            if (!await activateFromSaved(src)) await activate(src);
          }());
        }
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
    if (extraSources.remove(s.name)) await _prefs?.setStringList('extraSources', extraSources.toList());
    await _writeSecret(s.name, null);
    await _saveSources();
    if (active?.name == s.name) {
      active = null;
      catalog = const Catalog();
      await _prefs?.remove('active');
    }
    notifyListeners();
  }

  /// One source's library, how it was got, and the Xtream client when it has one.
  /// [savedAt] is set when the library is a saved copy rather than what the provider just sent.

  /// The Xtream login a source stands for: its own, or the one inside a provider's get.php link.
  ProviderLogin? _xtreamLogin(Source s) {
    if (s.type == SourceType.xtream) return ProviderLogin(s.url, s.username, s.password);
    if (s.type == SourceType.m3u && !s.url.contains('\n') && Uri.tryParse(s.url)?.path.endsWith('get.php') == true) {
      return parseProviderLink(s.url);
    }
    return null;
  }

  /// A source's saved library, ready to use, or null when there is none. Reading and parsing happen off
  /// the UI thread.
  Future<({Catalog catalog, XtreamClient? client, DateTime? savedAt})?> _fromCache(Source s) async {
    if (s.type == SourceType.demo) return (catalog: demoCatalog(), client: null, savedAt: null);
    final saved = await PerfLog.time('read saved library', () => CatalogCache.load(s));
    if (saved == null) return null;
    final total = saved.blobs.fold<int>(0, (a, b) => a + b.length);
    try {
      if (saved.kind == 'x') {
        final login = _xtreamLogin(s);
        if (login == null || saved.blobs.length != 6) return null;
        final cat = await parseAway('parse saved library', total,
            xtreamParseJob(_trimBase(login.server), login.username, login.password, saved.blobs));
        return (catalog: cat, client: XtreamClient(login.server, login.username, login.password), savedAt: saved.savedAt);
      }
      if (saved.kind == 'm' && saved.blobs.length == 1) {
        final cat = await parseAway('parse saved library', total, m3uParseJob(saved.blobs.first));
        return (catalog: cat, client: null, savedAt: saved.savedAt);
      }
    } catch (_) {}
    return null;
  }

  static String _trimBase(String server) => server.trim().replaceAll(RegExp(r'/+$'), '');

  /// Loads one source on its own: its library, and the Xtream client when it has one.
  Future<({Catalog catalog, XtreamClient? client, DateTime? savedAt})> _load(Source s) async {
    switch (s.type) {
      case SourceType.demo:
        return (catalog: demoCatalog(), client: null, savedAt: null);
      case SourceType.m3u:
        // Several playlist addresses, one per line, load and merge into one library.
        final urls = s.url.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (urls.length > 1) return (catalog: await loadMergedPlaylists(urls), client: null, savedAt: null);
        // A provider's get.php?username=..&password=.. link is the Xtream panel in disguise.
        // Its API gives proper movies, series, posters and guide data, so prefer it and
        // fall back to the plain playlist when the panel doesn't answer.
        final login = _xtreamLogin(s);
        if (login != null) {
          try {
            return await _loadXtream(s, XtreamClient(login.server, login.username, login.password));
          } catch (_) {}
        }
        final res = await PerfLog.time('fetch library', () => appHttp.get(Uri.parse(s.url), headers: NetConfig.headers).timeout(const Duration(seconds: 60)));
        if (res.statusCode != 200) throw Exception('Playlist returned ${res.statusCode}');
        final bytes = res.bodyBytes;
        unawaited(CatalogCache.save(s, 'm', [bytes]));
        final cat = await parseAway('parse library', bytes.length, m3uParseJob(bytes));
        return (catalog: cat, client: null, savedAt: null);
      case SourceType.xtream:
        return _loadXtream(s, XtreamClient(s.url, s.username, s.password));
    }
  }

  Future<({Catalog catalog, XtreamClient? client, DateTime? savedAt})> _loadXtream(Source s, XtreamClient c) async {
    await PerfLog.time('sign in', c.authenticate);
    final raw = await PerfLog.time('fetch library', c.fetchRaw);
    unawaited(CatalogCache.save(s, 'x', raw));
    final total = raw.fold<int>(0, (a, b) => a + b.length);
    PerfLog.fact('library download', '${(total / 1048576).toStringAsFixed(1)} MB');
    final cat = await parseAway('parse library', total, xtreamParseJob(c.base, c.user, c.pass, raw));
    return (catalog: cat, client: c, savedAt: null);
  }

  /// True while a saved library is on screen and the provider's current one is being fetched.
  bool refreshing = false;

  /// When the library on screen was saved, if it is a saved copy; null when it came from the provider.
  DateTime? libraryFrom;

  /// Why the last quiet refresh failed (the saved library stays on screen).
  String? refreshError;

  /// Makes [s] the library from what is saved on this device, if anything is. Returns false (and changes
  /// nothing) when no saved copy exists, so the caller can fetch it from the provider instead.
  Future<bool> activateFromSaved(Source s) async {
    final main = await _fromCache(s);
    if (main == null) return false;
    final extras = <(String, Catalog)>[];
    final clients = <String, XtreamClient>{};
    for (final src in sources) {
      if (src.name == s.name || !extraSources.contains(src.name)) continue;
      final r = await _fromCache(src); // an extra with no saved copy joins after the refresh
      if (r == null) continue;
      extras.add((src.name, r.catalog));
      if (r.client != null) clients[src.name] = r.client!;
    }
    active = s;
    _xtream = main.client;
    _clients
      ..clear()
      ..addAll(clients);
    _extraGuides.clear();
    extraErrors.clear();
    catalog = combineSources(main.catalog, extras);
    _guideLoaded = false;
    guide = XmltvData.empty;
    error = null;
    loading = false;
    refreshing = true;
    libraryFrom = main.savedAt;
    PerfLog.fact('library shown from', 'saved copy (${main.savedAt == null ? 'demo' : '${DateTime.now().difference(main.savedAt!).inMinutes} min old'})');
    PerfLog.mark('library on screen');
    notifyListeners();
    unawaited(_refresh(s));
    return true;
  }

  /// Fetches the provider's current library behind a saved copy that is already showing.
  Future<void> _refresh(Source s) async {
    refreshError = null;
    try {
      await activate(s, quiet: true);
    } catch (_) {}
  }

  Future<void> activate(Source s, {bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      refreshing = false;
      libraryFrom = null;
    }
    error = null;
    active = s;
    notifyListeners();
    try {
      final main = await _load(s);
      if (quiet && active?.name != s.name) return; // another source was picked meanwhile
      _xtream = main.client;
      _clients.clear();
      _extraGuides.clear();
      extraErrors.clear();
      // The other sources that are switched on join the library; one that fails is skipped and reported.
      final extras = <(String, Catalog)>[];
      final want = [for (final src in sources) if (src.name != s.name && extraSources.contains(src.name)) src];
      final loaded = await Future.wait(want.map((src) async {
        try {
          return (src, await _load(src), null as Object?);
        } catch (e) {
          return (src, null, e as Object?);
        }
      }));
      for (final (src, r, err) in loaded) {
        if (r == null) {
          extraErrors[src.name] = friendlyError(err!);
          continue;
        }
        extras.add((src.name, r.catalog));
        if (r.client != null) _clients[src.name] = r.client!;
        final g = r.client?.xmltvUri ?? (r.catalog.epgUrl == null ? null : Uri.tryParse(r.catalog.epgUrl!));
        if (g != null) _extraGuides.add(g);
      }
      catalog = combineSources(main.catalog, extras);
      _guideLoaded = false;
      guide = XmltvData.empty;
      libraryFrom = null;
      await _prefs?.setString('active', s.name);
      PerfLog.fact('library from', 'provider');
      PerfLog.mark(quiet ? 'library refreshed' : 'library on screen');
    } catch (e) {
      if (quiet) {
        // The saved copy stays; just say the refresh did not work.
        refreshError = friendlyError(e);
      } else {
        error = friendlyError(e);
        catalog = const Catalog();
      }
    }
    loading = false;
    refreshing = false;
    notifyListeners();
  }

  // --- More than one source at once ----------------------------------------------------------

  /// Names of the saved sources, besides the main one, that are part of the library too.
  final Set<String> extraSources = {};

  /// Why a source that is switched on could not be loaded (by source name).
  final Map<String, String> extraErrors = {};

  final Map<String, XtreamClient> _clients = {};
  final List<Uri> _extraGuides = [];

  /// How many sources the library is made of now (the main one and the loaded extras).
  int get sourceCount => active == null ? 0 : 1 + extraSources.where((n) => sources.any((s) => s.name == n) && n != active!.name).length;

  Future<void> setExtraSource(String name, bool on) async {
    if (on ? !extraSources.add(name) : !extraSources.remove(name)) return;
    await _prefs?.setStringList('extraSources', extraSources.toList());
    final a = active;
    if (a != null) {
      await activate(a);
    } else {
      notifyListeners();
    }
  }

  /// The Xtream client that serves [i]: the main source's, or the one of the source it came from.
  XtreamClient? _clientOf(MediaItem i) => i.src == null ? _xtream : _clients[i.src];

  void signOut() {
    active = null;
    error = null;
    catalog = const Catalog();
    _prefs?.remove('active');
    notifyListeners();
  }

  /// Provider-side details for the movie / series page (null without an Xtream source).
  Future<TmdbInfo?> providerInfo(MediaItem i) async {
    final c = _clientOf(i);
    if (c == null || i.kind == MediaKind.live || i.id.startsWith('ep')) return null;
    try {
      return i.kind == MediaKind.series ? await c.seriesInfo(i.id) : await c.vodInfo(i.id);
    } catch (_) {
      return null;
    }
  }

  Future<List<Episode>> episodes(MediaItem series) async => _clientOf(series)?.episodes(series.id) ?? [];

  /// Other copies of a merged channel, best first (empty for anything else).
  List<MediaItem> alternatesFor(MediaItem i) {
    shown; // makes sure the merge is current
    return _alternates[i.key] ?? const [];
  }

  /// The library item with [key], when it is in the library on screen.
  MediaItem? itemByKey(String key) => _byKey(key);

  bool isFavorite(MediaItem i) =>
      favorites.contains(i.key) || (i.kind == MediaKind.live && alternatesFor(i).any((a) => favorites.contains(a.key)));

  void toggleFavorite(MediaItem i) {
    if (!favorites.remove(i.key)) favorites.add(i.key);
    _prefs?.setStringList(_k('favorites'), favorites.toList());
    notifyListeners();
  }

  /// My list in the viewer's order. Items that are not in the library on screen are left out.
  List<MediaItem> get favoriteItems => [
        for (final k in favorites)
          if (_byKey(k) case final it?) it,
      ];

  /// Moves [key] within My list: to the top, or [by] places earlier (negative) or later (positive).
  void moveFavorite(String key, {bool toTop = false, int by = 0}) {
    final l = _moved(favorites.toList(), key, toTop: toTop, by: by, visible: {for (final i in favoriteItems) i.key});
    if (l == null) return;
    favorites
      ..clear()
      ..addAll(l);
    _prefs?.setStringList(_k('favorites'), l);
    notifyListeners();
  }

  /// Moves [key] within the collection [name], the same way.
  void moveInCollection(String name, String key, {bool toTop = false, int by = 0}) {
    final l = collections[name];
    if (l == null) return;
    final m = _moved(l, key, toTop: toTop, by: by, visible: {for (final i in collectionItems(name)) i.key});
    if (m == null) return;
    collections[name] = m;
    _saveCollections();
  }

  /// [list] with [key] moved, or null when it is not there or would not move. Moving by some places counts
  /// only the keys in [visible] (when given), so a title never seems to stand still because it traded
  /// places with something that is not in the library on screen.
  List<String>? _moved(List<String> list, String key, {required bool toTop, required int by, Set<String>? visible}) {
    final at = list.indexOf(key);
    if (at < 0) return null;
    var to = at;
    if (toTop) {
      to = 0;
    } else if (by != 0) {
      final dir = by.sign;
      var steps = by.abs();
      while (steps > 0) {
        var n = to + dir;
        while (n >= 0 && n < list.length && visible != null && !visible.contains(list[n])) {
          n += dir;
        }
        if (n < 0 || n >= list.length) break;
        to = n;
        steps--;
      }
    }
    if (to == at) return null;
    return [...list]
      ..removeAt(at)
      ..insert(to, key);
  }

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
      if (watched.add(i.key)) _prefs?.setStringList(_k('watched'), watched.toList());
    } else if (pos.inSeconds > 10) {
      positions[i.key] = pos.inMilliseconds;
    }
    if (durations[i.key] != total.inMilliseconds) {
      durations.remove(i.key);
      durations[i.key] = total.inMilliseconds;
      while (durations.length > 3000) {
        durations.remove(durations.keys.first);
      }
      _prefs?.setString(_k('durations'), jsonEncode(durations));
    }
    _prefs?.setString(_k('positions'), jsonEncode(positions));
    // Deferred: this runs from State.dispose(), where notifying synchronously would
    // mark widgets dirty while the tree is locked.
    if (notify) Future.microtask(notifyListeners);
  }

  // --- Watched and progress ---------------------------------------------------

  bool isWatched(MediaItem i) => watched.contains(i.key);

  /// How far through [i] you are, 0 to 1; null when it has not been started (or its length is unknown).
  double? progressOf(MediaItem i) {
    final p = positions[i.key], d = durations[i.key];
    if (p == null || d == null || d <= 0) return null;
    return (p / d).clamp(0.0, 1.0);
  }

  /// Marks titles watched (clearing where you were in them) or not watched.
  void setWatched(Iterable<MediaItem> items, bool on) {
    for (final i in items) {
      if (on) {
        watched.add(i.key);
        positions.remove(i.key);
      } else {
        watched.remove(i.key);
      }
    }
    _prefs?.setStringList(_k('watched'), watched.toList());
    _prefs?.setString(_k('positions'), jsonEncode(positions));
    notifyListeners();
  }

  // --- EPG --------------------------------------------------------------

  Future<List<EpgEntry>> epg(MediaItem live) async =>
      _clientOf(live) == null ? const [] : _clientOf(live)!.shortEpg(live.id);

  // --- Backup / restore ---------------------------------------------------

  /// Sources (without passwords), favorites, resume positions, recents.
  Map<String, dynamic> exportData() => {
        'sources': [for (final e in sources) e.toJson()..['pass'] = ''],
        'favorites': favorites.toList(),
        'positions': positions,
        'watched': watched.toList(),
        'recents': [for (final r in recents) r.toJson()],
        'collections': collections,
        'channelEdits': {
          'edits': {for (final e in channelEdits.edits.entries) e.key: e.value.toJson()},
          'pins': channelEdits.pins,
        },
      };

  void importData(Map<String, dynamic> m) {
    for (final j in (m['sources'] as List? ?? const [])) {
      final src = Source.fromJson(j as Map<String, dynamic>);
      if (!sources.any((e) => e.name == src.name)) sources.add(src);
    }
    favorites.addAll([for (final f in (m['favorites'] as List? ?? const [])) '$f']);
    positions.addAll((m['positions'] as Map? ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt())));
    watched.addAll([for (final w in (m['watched'] as List? ?? const [])) '$w']);
    _prefs?.setStringList(_k('watched'), watched.toList());
    final have = recents.map((e) => e.key).toSet();
    for (final j in (m['recents'] as List? ?? const [])) {
      final it = MediaItem.fromJson(j as Map<String, dynamic>);
      if (have.add(it.key)) recents.add(it);
    }
    (m['collections'] as Map? ?? const {}).forEach((k, v) {
      final l = collections.putIfAbsent('$k', () => []);
      for (final e in (v as List)) {
        if (!l.contains('$e')) l.add('$e');
      }
    });
    try {
      final ce = m['channelEdits'] as Map?;
      if (ce != null) {
        (ce['edits'] as Map? ?? const {}).forEach((k, v) => channelEdits.edits.putIfAbsent('$k', () => ChannelEdit.fromJson(Map<String, dynamic>.from(v as Map))));
        for (final e in (ce['pins'] as List? ?? const [])) {
          if (!channelEdits.pins.contains('$e')) channelEdits.pins.add('$e');
        }
        _prefs?.setString(_k('channelEdits'), jsonEncode({
          'edits': {for (final e in channelEdits.edits.entries) e.key: e.value.toJson()},
          'pins': channelEdits.pins,
        }));
        _ver++;
      }
    } catch (_) {}
    _prefs?.setString(_k('collections'), jsonEncode(collections));
    _prefs?.setStringList(_k('favorites'), favorites.toList());
    _prefs?.setString(_k('positions'), jsonEncode(positions));
    _prefs?.setStringList(_k('recents'), [for (final e in recents) jsonEncode(e.toJson())]);
    _saveSources();
    notifyListeners();
  }

  // --- Posters from TMDB --------------------------------------------------------------------

  Map<String, String>? _posterCache; // item key -> poster address, '' = TMDB has none
  final Map<String, Future<String?>> _posterFutures = {};
  int _posterBusy = 0;
  final List<void Function()> _posterWaiting = [];
  http.Client? _tmdbClient; // tests

  @visibleForTesting
  void useTmdbClientForTest(http.Client c) => _tmdbClient = c;

  /// Missing posters can be filled in: there is a TMDB key and the setting is on.
  bool get canResolvePosters => (_settings?.tmdbKey.isNotEmpty ?? false) && (_settings?.realPosters ?? true);

  Map<String, String> get _posters {
    if (_posterCache != null) return _posterCache!;
    final out = <String, String>{};
    try {
      final raw = _prefs?.getString('posterCache');
      if (raw != null) (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) => out[k] = '$v');
    } catch (_) {}
    return _posterCache = out;
  }

  /// The poster of [i]: its own, else one from TMDB (asked for politely, three at a time, and remembered).
  Future<String?> posterFor(MediaItem i) {
    final own = i.poster;
    if (own != null && own.isNotEmpty) return Future.value(own);
    if (!canResolvePosters || i.kind == MediaKind.live) return Future.value(null);
    final cached = _posters[i.key];
    if (cached != null) return Future.value(cached.isEmpty ? null : cached);
    return _posterFutures.putIfAbsent(i.key, () => _askTmdb(i));
  }

  Future<String?> _askTmdb(MediaItem i) async {
    while (_posterBusy >= 3) {
      final turn = Completer<void>();
      _posterWaiting.add(turn.complete);
      await turn.future;
    }
    _posterBusy++;
    try {
      final url = await TmdbService(_settings!.tmdbKey, client: _tmdbClient).posterFor(i);
      if (url == null) return null;
      final c = _posters;
      c[i.key] = url;
      if (c.length > 4000) c.remove(c.keys.first);
      _prefs?.setString('posterCache', jsonEncode(c));
      return url.isEmpty ? null : url;
    } finally {
      _posterBusy--;
      if (_posterWaiting.isNotEmpty) _posterWaiting.removeAt(0)();
    }
  }

  // --- Deck ---------------------------------------------------------------------------------

  /// Titles the viewer said "not tonight" to in the Deck layout, with when (milliseconds). Kept per profile.
  final Map<String, int> deckSkips = {};

  /// How long a skipped title stays out of the deck.
  static const deckSkipFor = Duration(days: 30);

  void skipForDeck(MediaItem i) {
    deckSkips[i.key] = DateTime.now().millisecondsSinceEpoch;
    _prefs?.setString(_k('deckSkips'), jsonEncode(deckSkips));
    notifyListeners();
  }

  void clearDeckSkips() {
    deckSkips.clear();
    _prefs?.remove(_k('deckSkips'));
    notifyListeners();
  }

  /// Keys of titles skipped within the last [deckSkipFor].
  Set<String> get deckSkippedKeys {
    final cut = DateTime.now().subtract(deckSkipFor).millisecondsSinceEpoch;
    return {for (final e in deckSkips.entries) if (e.value >= cut) e.key};
  }

  // --- Channel filter -----------------------------------------------------------------------

  /// The filter on the live lists, shared by Live and the Guide so it carries from one to the other.
  ChannelFilter channelFilter = ChannelFilter.none;

  void setChannelFilter(ChannelFilter f) {
    if (f == channelFilter) return;
    channelFilter = f;
    notifyListeners();
  }

  /// The category name of a live channel ("" when it has none).
  String liveCategoryName(MediaItem ch) => _liveCatNames(shown)[ch.categoryId] ?? '';

  Map<String, String>? _catNames;
  Catalog? _catNamesFor;
  Map<String, String> _liveCatNames(Catalog c) {
    if (_catNames == null || !identical(_catNamesFor, c)) {
      _catNames = {for (final x in c.liveCategories) x.id: x.name};
      _catNamesFor = c;
    }
    return _catNames!;
  }

  /// [channels] narrowed by the shared filter.
  List<MediaItem> filterChannels(List<MediaItem> channels) => applyChannelFilter(
        channels,
        channelFilter,
        categoryName: liveCategoryName,
        isFavorite: isFavorite,
        hasGuide: (c) => programmesFor(c).isNotEmpty,
      );

  // --- Movie, series and anime filters ------------------------------------------------------

  /// One filter per list: 'movie', 'series' or 'anime' (and 'anime-live' for anime channels).
  final Map<String, VodFilter> vodFilters = {};

  VodFilter vodFilter(String list) => vodFilters[list] ?? VodFilter.none;

  void setVodFilter(String list, VodFilter f) {
    if (f == vodFilter(list)) return;
    if (f == VodFilter.none) {
      vodFilters.remove(list);
    } else {
      vodFilters[list] = f;
    }
    notifyListeners();
  }

  Map<String, String>? _vodCatNames;
  Catalog? _vodCatNamesFor;

  /// The category name of a movie or series ("" when it has none). Movies and series number their
  /// categories separately, so the same id can be two different categories.
  String vodCategoryName(MediaItem i) {
    final c = shown;
    if (_vodCatNames == null || !identical(_vodCatNamesFor, c)) {
      _vodCatNames = {
        for (final x in c.movieCategories) 'movie:${x.id}': x.name,
        for (final x in c.seriesCategories) 'series:${x.id}': x.name,
      };
      _vodCatNamesFor = c;
    }
    return _vodCatNames!['${i.kind == MediaKind.series ? 'series' : 'movie'}:${i.categoryId}'] ?? '';
  }

  final Map<String, List<(Language, int)>> _langMemo = {};
  Catalog? _langMemoFor;

  /// The languages in a list ('live', 'movie', 'series', 'anime'), most titles first, worked out once
  /// per library.
  List<(Language, int)> languagesFor(String list) {
    final c = shown;
    if (!identical(_langMemoFor, c)) {
      _langMemo.clear();
      _langMemoFor = c;
    }
    return _langMemo[list] ??= switch (list) {
      'live' => languagesIn(c.live, liveCategoryName),
      'series' => languagesIn(c.series, vodCategoryName),
      'anime' => languagesIn(
          [for (final k in MediaKind.values) ...animeFor(k).items], vodCategoryName),
      _ => languagesIn(c.movies, vodCategoryName),
    };
  }

  /// Whether this title was opened lately or has a resume position.
  bool isStarted(MediaItem i) =>
      positions.containsKey(i.key) || recents.any((e) => e.key == i.key);

  final Map<String, (List<MediaItem>, VodFilter, List<MediaItem>)> _vodMemo = {};

  /// [items] narrowed by the filter of [list]. The answer is kept while the same list and filter are
  /// asked about again (every rebuild of a screen does), except when it depends on favorites or history.
  List<MediaItem> filterVod(String list, List<MediaItem> items) {
    final f = vodFilter(list);
    if (!f.active) return items;
    final volatile = f.favoritesOnly || f.unwatchedOnly;
    final hit = _vodMemo[list];
    if (!volatile && hit != null && identical(hit.$1, items) && hit.$2 == f) return hit.$3;
    final out = applyVodFilter(items, f,
        categoryName: vodCategoryName, isFavorite: isFavorite, started: isStarted);
    if (!volatile) _vodMemo[list] = (items, f, out);
    return out;
  }

  // --- Anime ----------------------------------------------------------------------------------

  Catalog? _animeSrc;
  Map<MediaKind, AnimeFound>? _anime;

  /// The anime in the library on screen, found once per library.
  AnimeFound animeFor(MediaKind k) {
    final c = shown;
    if (_anime == null || !identical(_animeSrc, c)) {
      _anime = {for (final kind in MediaKind.values) kind: animeOf(c, kind)};
      _animeSrc = c;
    }
    return _anime![k]!;
  }

  int get animeCount => MediaKind.values.fold<int>(0, (a, k) => a + animeFor(k).items.length);

  /// Whether the Anime page is in the menus: always, never, or (Auto) when the library has some.
  bool get animeVisible => switch (_settings?.animePage ?? 'auto') {
        'on' => true,
        'off' => false,
        _ => animeCount > 0,
      };

  // --- Edited channels ------------------------------------------------------------------------

  /// The viewer's renames, hidden channels and pinned channels, kept per profile.
  final ChannelEdits channelEdits = ChannelEdits();

  void _saveChannelEdits() {
    _prefs?.setString(_k('channelEdits'), jsonEncode({
      'edits': {for (final e in channelEdits.edits.entries) e.key: e.value.toJson()},
      'pins': channelEdits.pins,
    }));
    _ver++;
    notifyListeners();
  }

  ChannelEdit _editOf(MediaItem ch) => channelEdits.edits[ch.key] ?? ChannelEdit(original: ch.name);

  void _putEdit(MediaItem ch, ChannelEdit e) {
    if (e.isEmpty) {
      channelEdits.edits.remove(ch.key);
    } else {
      channelEdits.edits[ch.key] = e;
    }
  }

  /// Gives [ch] a name of its own. A blank name, or the original one, takes the rename away.
  void renameChannel(MediaItem ch, String? name) {
    final cur = _editOf(ch);
    final n = name?.trim();
    _putEdit(ch, cur.copyWith(name: (n == null || n.isEmpty || n == cur.original) ? null : n));
    _saveChannelEdits();
  }

  /// Takes [ch] out of every list. The Edited channels screen brings it back.
  void hideChannel(MediaItem ch) {
    _putEdit(ch, _editOf(ch).copyWith(hidden: true));
    channelEdits.pins.remove(ch.key);
    _saveChannelEdits();
  }

  void unhideChannel(String key) {
    final e = channelEdits.edits[key];
    if (e == null) return;
    if (e.copyWith(hidden: false).isEmpty) {
      channelEdits.edits.remove(key);
    } else {
      channelEdits.edits[key] = e.copyWith(hidden: false);
    }
    _saveChannelEdits();
  }

  bool isPinned(String key) => channelEdits.pins.contains(key);

  /// Puts [ch] at the top of the channel lists (after the ones pinned before it).
  void pinChannel(MediaItem ch) {
    if (isPinned(ch.key)) return;
    channelEdits.pins.add(ch.key);
    _saveChannelEdits();
  }

  void unpinChannel(String key) {
    if (channelEdits.pins.remove(key)) _saveChannelEdits();
  }

  /// Moves a pinned channel among the pinned ones, [by] places (negative is earlier).
  void movePinned(String key, int by) {
    final l = _moved(channelEdits.pins, key, toTop: false, by: by);
    if (l == null) return;
    channelEdits.pins
      ..clear()
      ..addAll(l);
    _saveChannelEdits();
  }

  /// Undoes every rename, hide and pin of one channel.
  void resetChannel(String key) {
    final had = channelEdits.edits.remove(key) != null;
    final pinned = channelEdits.pins.remove(key);
    if (had || pinned) _saveChannelEdits();
  }

  void resetAllChannelEdits() {
    if (channelEdits.isEmpty) return;
    channelEdits.clear();
    _saveChannelEdits();
  }

  // --- Skips the viewer made ------------------------------------------------------------------

  /// Where the viewer skipped the opening of a series, so the next episodes can offer the same skip.
  /// Keyed by the first episode's key; kept per profile.
  final Map<String, IntroWindow> introSkips = {};

  void rememberIntro(String seriesKey, IntroWindow w) {
    introSkips[seriesKey] = w;
    _prefs?.setString(_k('introSkips'), jsonEncode({for (final e in introSkips.entries) e.key: e.value.toJson()}));
  }

  // --- Recommendations ----------------------------------------------------------------------

  Recommendation? _rec;
  String? _recKey;

  /// A shelf of unseen movies and series that fit what was watched and saved (null without any history).
  Recommendation? get recommendation {
    final c = shown;
    final key = '${identityHashCode(c)}|${recents.map((e) => e.key).join(',')}|${favorites.length}|${positions.length}';
    if (key != _recKey) {
      _recKey = key;
      _rec = recommend(catalog: c, recents: recents, favorites: favorites, positions: positions);
    }
    return _rec;
  }

  // --- Collections --------------------------------------------------------------------------

  /// Named lists the viewer makes (beyond My List): name to the keys of the items in it, in the order added.
  /// Kept per profile. An item that is not in the library on screen is simply not shown.
  final Map<String, List<String>> collections = {};

  Map<String, MediaItem>? _keyIndex;
  Catalog? _keyIndexSrc;

  MediaItem? _byKey(String key) {
    final c = shown;
    if (_keyIndex == null || !identical(_keyIndexSrc, c)) {
      _keyIndex = {for (final i in c.all) i.key: i};
      _keyIndexSrc = c;
    }
    return _keyIndex![key];
  }

  void _saveCollections() {
    _prefs?.setString(_k('collections'), jsonEncode(collections));
    notifyListeners();
  }

  /// Makes a collection. False when the name is blank or taken.
  bool createCollection(String name) {
    final n = name.trim();
    if (n.isEmpty || collections.keys.any((k) => k.toLowerCase() == n.toLowerCase())) return false;
    collections[n] = [];
    _saveCollections();
    return true;
  }

  bool renameCollection(String from, String to) {
    final n = to.trim();
    if (!collections.containsKey(from) || n.isEmpty) return false;
    if (n.toLowerCase() != from.toLowerCase() && collections.keys.any((k) => k.toLowerCase() == n.toLowerCase())) return false;
    final items = collections.remove(from)!;
    collections[n] = items;
    _saveCollections();
    return true;
  }

  void deleteCollection(String name) {
    if (collections.remove(name) != null) _saveCollections();
  }

  bool inCollection(String name, MediaItem i) => collections[name]?.contains(i.key) ?? false;

  /// Adds [i] to [name], or takes it out if it is there.
  void toggleInCollection(String name, MediaItem i) {
    final l = collections[name];
    if (l == null) return;
    if (!l.remove(i.key)) l.add(i.key);
    _saveCollections();
  }

  /// The items of [name] that are in the library now, in the order they were added.
  List<MediaItem> collectionItems(String name) => [
        for (final k in collections[name] ?? const <String>[])
          if (_byKey(k) case final it?) it,
      ];

  // --- Catch-up (provider archive) ----------------------------------------------------------

  @visibleForTesting
  void useXtreamForTest(XtreamClient c) => _xtream = c;

  /// True when [ch] keeps an archive and this source can play it.
  bool canCatchUp(MediaItem ch) => ch.kind == MediaKind.live && ch.archiveDays > 0 && _clientOf(ch) != null;

  /// Whether [p] on [ch] can be watched from the archive: it has started and is within the days kept.
  bool catchUpFor(MediaItem ch, Programme p, {DateTime? now}) {
    if (!canCatchUp(ch)) return false;
    final n = now ?? DateTime.now();
    return !p.start.isAfter(n) && p.start.isAfter(n.subtract(Duration(days: ch.archiveDays)));
  }

  /// The archive stream of [p] on [ch] (the whole programme, from its start), or null.
  String? catchUpUrl(MediaItem ch, Programme p) {
    if (!canCatchUp(ch)) return null;
    return _clientOf(ch)!.timeshiftUrl(ch.id, p.start, p.end.difference(p.start));
  }

  // --- Search -------------------------------------------------------------------------------

  SearchIndex? _searchIdx;
  Catalog? _searchSrc;

  /// The searchable form of what is on screen (built once per library and filter change).
  SearchIndex get searchIndex {
    final c = shown;
    if (_searchIdx == null || !identical(_searchSrc, c)) {
      _searchIdx = SearchIndex.of(c);
      _searchSrc = c;
    }
    return _searchIdx!;
  }

  /// What was searched for lately, newest first. Kept per profile.
  final List<String> recentSearches = [];

  void rememberSearch(String q) {
    final t = q.trim();
    if (t.length < 2) return;
    recentSearches.removeWhere((e) => e.toLowerCase() == t.toLowerCase());
    recentSearches.insert(0, t);
    if (recentSearches.length > 8) recentSearches.removeLast();
    _prefs?.setStringList(_k('searches'), recentSearches);
    notifyListeners();
  }

  void clearSearches() {
    recentSearches.clear();
    _prefs?.remove(_k('searches'));
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
    final parallel = _xtream != null || _clients.isNotEmpty || src.type == SourceType.xtream ? 2 : 10;
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

  @visibleForTesting
  Future<void> setDeadForTest(Set<String> keys) async {
    _dead[active!.name] = keys;
    _ver++;
    notifyListeners();
  }

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

  List<Uri> get _guideUris => [
        if (_xtream?.xmltvUri ?? (catalog.epgUrl == null ? null : Uri.tryParse(catalog.epgUrl!)) case final u?) u,
        ..._extraGuides,
      ];

  bool get hasGuideSource => _guideUris.isNotEmpty;

  /// Loads and parses the XMLTV guide(s) once per library load: the last day (for catch-up) and the next 8 hours.
  Future<void> loadGuide({bool force = false}) async {
    final uris = _guideUris;
    if (uris.isEmpty || guideLoading || (_guideLoaded && !force)) return;
    guideLoading = true;
    guideError = null;
    notifyListeners();
    final now = DateTime.now();
    final parts = <XmltvData>[];
    Object? firstError;
    for (final uri in uris) {
      try {
        final res = await appHttp.get(uri, headers: NetConfig.headers).timeout(const Duration(seconds: 90));
        if (res.statusCode != 200) throw Exception('Guide returned ${res.statusCode}');
        parts.add(await compute(parseXmltvBytesJob, <Object>[
          res.bodyBytes,
          now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch,
          now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
        ]));
      } catch (e) {
        firstError ??= e;
      }
    }
    if (parts.isEmpty) {
      guideError = firstError.toString().replaceFirst('Exception: ', '');
    } else {
      guide = mergeXmltv(parts);
      _guideLoaded = true;
    }
    guideLoading = false;
    notifyListeners();
  }

  /// Programmes for a channel, matched by tvg-id, then by channel name.
  List<Programme> programmesFor(MediaItem ch) {
    final byId = ch.epgId == null ? null : guide.programmes[ch.epgId!.toLowerCase()];
    if (byId != null) return byId;
    final id = guide.nameToId[(channelEdits.edits[ch.key]?.original ?? ch.name).trim().toLowerCase()];
    return id == null ? const [] : (guide.programmes[id] ?? const []);
  }
}
