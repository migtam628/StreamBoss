import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media.dart';
import 'http_client.dart';
import 'net_config.dart';
import 'tmdb.dart';

/// What the provider says about the account: how long it lasts and how many screens it allows.
class AccountInfo {
  final String status; // Active, Expired, Disabled ...
  final DateTime? expires;
  final int? maxConnections, activeConnections;
  final bool trial;
  const AccountInfo({required this.status, this.expires, this.maxConnections, this.activeConnections, this.trial = false});

  static AccountInfo fromUserInfo(Map info) {
    int? i(dynamic v) => int.tryParse('$v');
    final exp = i(info['exp_date']);
    return AccountInfo(
      status: '${info['status'] ?? 'Active'}',
      // Providers send unix seconds; 0 or missing means no expiry.
      expires: exp == null || exp <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      maxConnections: i(info['max_connections']),
      activeConnections: i(info['active_cons']),
      trial: '${info['is_trial']}' == '1',
    );
  }

  int? daysLeft([DateTime? now]) => expires?.difference(now ?? DateTime.now()).inDays;

  /// Short lines for the Source settings page.
  List<String> describe([DateTime? now]) {
    final d = daysLeft(now);
    final e = expires;
    String date(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return [
      '$status${trial ? ' (trial)' : ''}',
      if (e == null)
        'No expiry date'
      else if (d != null && d < 0)
        'Expired on ${date(e)}'
      else
        'Expires ${date(e)}${d == null ? '' : ' (${d == 0 ? 'today' : d == 1 ? 'in 1 day' : 'in $d days'})'}',
      if (maxConnections != null)
        '${activeConnections ?? 0} of $maxConnections ${maxConnections == 1 ? 'connection' : 'connections'} in use',
    ];
  }
}

class XtreamClient {
  final String base;
  final String user;
  final String pass;
  final http.Client _http;

  /// Filled in by [authenticate].
  AccountInfo? account;

  XtreamClient(String server, this.user, this.pass, {http.Client? client})
      : base = server.trim().replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? appHttp;

  Uri _api(String action, [Map<String, String> extra = const {}]) =>
      Uri.parse('$base/player_api.php').replace(queryParameters: {
        'username': user,
        'password': pass,
        if (action.isNotEmpty) 'action': action,
        ...extra,
      });

  Uri get xmltvUri => Uri.parse('$base/xmltv.php')
      .replace(queryParameters: {'username': user, 'password': pass});

  Future<dynamic> _get(String action, [Map<String, String> extra = const {}]) async {
    final res = await _http.get(_api(action, extra), headers: NetConfig.headers).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Server returned ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<void> authenticate() async {
    final j = await _get('');
    final auth = (j is Map ? j['user_info'] : null);
    if (auth is! Map || '${auth['auth']}' != '1') {
      throw Exception('Invalid credentials');
    }
    account = AccountInfo.fromUserInfo(auth);
  }

  List<Category> _cats(dynamic j) => [
        for (final c in (j as List? ?? const []))
          Category('${c['category_id']}', '${c['category_name']}'),
      ];

  Future<Catalog> loadCatalog() async {
    final r = await Future.wait([
      _get('get_live_categories'),
      _get('get_live_streams'),
      _get('get_vod_categories'),
      _get('get_vod_streams'),
      _get('get_series_categories'),
      _get('get_series'),
    ]);

    String? s(dynamic v) {
      final t = v?.toString();
      return (t == null || t.isEmpty) ? null : t;
    }

    final live = [
      for (final c in (r[1] as List? ?? const []))
        MediaItem(
          id: '${c['stream_id']}',
          name: '${c['name']}',
          kind: MediaKind.live,
          streamUrl: '$base/live/$user/$pass/${c['stream_id']}.m3u8',
          poster: s(c['stream_icon']),
          categoryId: '${c['category_id']}',
          epgId: s(c['epg_channel_id']),
        ),
    ];
    final movies = [
      for (final c in (r[3] as List? ?? const []))
        MediaItem(
          id: '${c['stream_id']}',
          name: '${c['name']}',
          kind: MediaKind.movie,
          streamUrl:
              '$base/movie/$user/$pass/${c['stream_id']}.${s(c['container_extension']) ?? 'mp4'}',
          poster: s(c['stream_icon']),
          categoryId: '${c['category_id']}',
          rating: s(c['rating']),
        ),
    ];
    final series = [
      for (final c in (r[5] as List? ?? const []))
        MediaItem(
          id: '${c['series_id']}',
          name: '${c['name']}',
          kind: MediaKind.series,
          poster: s(c['cover']),
          categoryId: '${c['category_id']}',
          rating: s(c['rating']),
          plot: s(c['plot']),
        ),
    ];
    return Catalog(
      liveCategories: _cats(r[0]),
      movieCategories: _cats(r[2]),
      seriesCategories: _cats(r[4]),
      live: live,
      movies: movies,
      series: series,
    );
  }

  /// Plot, cast, backdrop etc. straight from the provider (no TMDB key needed).
  Future<TmdbInfo?> vodInfo(String vodId) async =>
      parseInfo(await _get('get_vod_info', {'vod_id': vodId}));

  Future<TmdbInfo?> seriesInfo(String seriesId) async =>
      parseInfo(await _get('get_series_info', {'series_id': seriesId}));

  static String? _str(dynamic v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty || t == 'null') ? null : t;
  }

  /// Panels disagree on shapes (strings vs numbers, lists vs strings, ids vs URLs),
  /// so everything here is defensive. Returns null when there is nothing useful.
  static TmdbInfo? parseInfo(dynamic j) {
    final info = j is Map ? j['info'] : null;
    if (info is! Map) return null;

    final bp = info['backdrop_path'];
    final backdrop = _str(bp is List && bp.isNotEmpty ? bp.first : bp);
    final poster = _str(info['movie_image']) ?? _str(info['cover_big']) ?? _str(info['cover']);

    var rating = double.tryParse(_str(info['rating']) ?? '');
    if (rating != null && rating <= 0) rating = null;

    final year = RegExp(r'(19|20)\d{2}')
        .firstMatch(_str(info['releasedate'] ?? info['releaseDate'] ?? info['year']) ?? '')?[0];

    final secs = int.tryParse(_str(info['duration_secs']) ?? '');
    final runtime = secs != null && secs > 0
        ? (secs / 60).round()
        : int.tryParse(_str(info['episode_run_time']) ?? '');

    final cast = (_str(info['cast']) ?? _str(info['actors']) ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(8)
        .toList();

    var trailer = _str(info['youtube_trailer']);
    if (trailer != null && trailer.contains('/')) {
      final u = Uri.tryParse(trailer);
      trailer = u?.queryParameters['v'] ?? (u != null && u.pathSegments.isNotEmpty ? u.pathSegments.last : null);
    }

    final overview = _str(info['plot']) ?? _str(info['description']);
    final out = TmdbInfo(
      overview: overview,
      rating: rating,
      year: year,
      backdrop: backdrop,
      poster: poster,
      runtimeMin: runtime,
      cast: cast,
      trailerKey: trailer,
    );
    final empty = overview == null && rating == null && year == null && backdrop == null &&
        poster == null && runtime == null && cast.isEmpty && trailer == null;
    return empty ? null : out;
  }

  Future<List<Episode>> episodes(String seriesId) async {
    final j = await _get('get_series_info', {'series_id': seriesId});
    final out = <Episode>[];
    final eps = (j is Map ? j['episodes'] : null);
    if (eps is Map) {
      eps.forEach((season, list) {
        for (final e in (list as List)) {
          final ext = e['container_extension'] ?? 'mp4';
          out.add(Episode(
            '${e['id']}',
            int.tryParse('$season') ?? 0,
            int.tryParse('${e['episode_num']}') ?? 0,
            '${e['title'] ?? 'Episode ${e['episode_num']}'}',
            '$base/series/$user/$pass/${e['id']}.$ext',
          ));
        }
      });
    }
    out.sort((a, b) => a.season != b.season ? a.season - b.season : a.number - b.number);
    return out;
  }

  /// Now / next programme for a live stream (Xtream short EPG).
  Future<List<EpgEntry>> shortEpg(String streamId) async {
    final j = await _get('get_short_epg', {'stream_id': streamId, 'limit': '3'});
    String dec(dynamic v) {
      try {
        return utf8.decode(base64.decode('$v'));
      } catch (_) {
        return '$v';
      }
    }

    return [
      for (final e in ((j is Map ? j['epg_listings'] : null) as List? ?? const []))
        EpgEntry(
          dec(e['title']),
          DateTime.fromMillisecondsSinceEpoch(
              (int.tryParse('${e['start_timestamp']}') ?? 0) * 1000),
          DateTime.fromMillisecondsSinceEpoch(
              (int.tryParse('${e['stop_timestamp']}') ?? 0) * 1000),
        ),
    ];
  }
}

class EpgEntry {
  final String title;
  final DateTime start, end;
  const EpgEntry(this.title, this.start, this.end);

  bool get isNow {
    final n = DateTime.now();
    return !n.isBefore(start) && n.isBefore(end);
  }
}
