import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  bool get ready => active != null && !loading && error == null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    sources = [
      for (final s in (p.getStringList('sources') ?? const []))
        Source.fromJson(jsonDecode(s) as Map<String, dynamic>),
    ];
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

  Future<void> addSource(Source s) async {
    sources = [...sources.where((e) => e.name != s.name), s];
    await _prefs?.setStringList(
        'sources', [for (final e in sources) jsonEncode(e.toJson())]);
    await activate(s);
  }

  Future<void> removeSource(Source s) async {
    sources = sources.where((e) => e.name != s.name).toList();
    await _prefs?.setStringList(
        'sources', [for (final e in sources) jsonEncode(e.toJson())]);
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
}
