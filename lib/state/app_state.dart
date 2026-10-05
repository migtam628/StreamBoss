import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media.dart';
import '../services/demo_catalog.dart';
import '../services/m3u_parser.dart';
import '../services/xtream_client.dart';
import 'package:http/http.dart' as http;

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
  final _secure = const FlutterSecureStorage();
  final Map<String, int> positions = {}; // media key -> ms

  bool get ready => active != null && !loading && error == null;

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
    final pos = p.getString('positions');
    if (pos != null) {
      positions.addAll((jsonDecode(pos) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)));
    }
    favorites.addAll(p.getStringList('favorites') ?? const []);
    recents.addAll([
      for (final s in (p.getStringList('recents') ?? const []))
        MediaItem.fromJson(jsonDecode(s) as Map<String, dynamic>),
    ]);
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
          final res = await http.get(Uri.parse(s.url)).timeout(const Duration(seconds: 60));
          if (res.statusCode != 200) throw Exception('Playlist returned ${res.statusCode}');
          catalog = parseM3u(utf8.decode(res.bodyBytes, allowMalformed: true));
          _xtream = null;
        case SourceType.xtream:
          final c = XtreamClient(s.url, s.username, s.password);
          await c.authenticate();
          catalog = await c.loadCatalog();
          _xtream = c;
      }
      await _prefs?.setString('active', s.name);
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
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

  Future<List<Episode>> episodes(MediaItem series) async =>
      _xtream?.episodes(series.id) ?? [];

  bool isFavorite(MediaItem i) => favorites.contains(i.key);

  void toggleFavorite(MediaItem i) {
    if (!favorites.remove(i.key)) favorites.add(i.key);
    _prefs?.setStringList('favorites', favorites.toList());
    notifyListeners();
  }

  List<MediaItem> get favoriteItems =>
      catalog.all.where((i) => favorites.contains(i.key)).toList();

  void markWatched(MediaItem i) {
    recents.removeWhere((e) => e.key == i.key);
    recents.insert(0, i);
    if (recents.length > 20) recents.removeLast();
    _prefs?.setStringList(
        'recents', [for (final e in recents) jsonEncode(e.toJson())]);
    notifyListeners();
  }

  // --- Resume positions -------------------------------------------------

  Duration? resumeFor(MediaItem i) {
    final ms = positions[i.key];
    return ms == null ? null : Duration(milliseconds: ms);
  }

  void savePosition(MediaItem i, Duration pos, Duration total) {
    if (i.kind == MediaKind.live || total.inSeconds < 60) return;
    // Treat the last 3% as finished.
    if (pos.inMilliseconds > total.inMilliseconds * 0.97) {
      positions.remove(i.key);
    } else if (pos.inSeconds > 10) {
      positions[i.key] = pos.inMilliseconds;
    }
    _prefs?.setString('positions', jsonEncode(positions));
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
    _prefs?.setStringList('favorites', favorites.toList());
    _prefs?.setString('positions', jsonEncode(positions));
    _prefs?.setStringList('recents', [for (final e in recents) jsonEncode(e.toJson())]);
    _saveSources();
    notifyListeners();
  }
}
