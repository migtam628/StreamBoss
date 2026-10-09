import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media.dart';
import 'tmdb.dart' show cleanTitle;

/// Season and episode numbers from a name like "Show S02E05 - Title" or "Show 2x05", else null.
(int, int)? parseSeasonEpisode(String name) {
  final m = RegExp(r'\bS(\d{1,2})\s*E(\d{1,3})\b', caseSensitive: false)
          .firstMatch(name) ??
      RegExp(r'\b(\d{1,2})x(\d{2,3})\b', caseSensitive: false).firstMatch(name);
  if (m == null) return null;
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

/// One subtitle file offered by OpenSubtitles.
class SubtitleHit {
  final String fileId;
  final String name;
  final String language;
  final int downloads;
  final bool hearingImpaired;
  const SubtitleHit({
    required this.fileId,
    required this.name,
    required this.language,
    this.downloads = 0,
    this.hearingImpaired = false,
  });
}

class SubtitleSearchError implements Exception {
  final String message;
  const SubtitleSearchError(this.message);
  @override
  String toString() => message;
}

/// Finds subtitles on OpenSubtitles.com with the person's own API key (the same arrangement as the
/// TMDB key). Downloads need an account, so a username and password are used when given.
class SubtitleSearch {
  final String apiKey;
  final String username, password;
  final http.Client? _client;
  final Uri base;

  SubtitleSearch(
    this.apiKey, {
    this.username = '',
    this.password = '',
    http.Client? client,
    Uri? baseUri,
  })  : _client = client,
        base = baseUri ?? Uri.parse('https://api.opensubtitles.com/api/v1/');

  static const _agent = 'StreamBoss v0.3';

  Map<String, String> get _headers => {
        'Api-Key': apiKey,
        'User-Agent': _agent,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  http.Client get _c => _client ?? http.Client();

  Future<http.Response> _get(Uri u, Map<String, String> h) async {
    final c = _c;
    try {
      return await c.get(u, headers: h).timeout(const Duration(seconds: 20));
    } finally {
      if (_client == null) c.close();
    }
  }

  Future<http.Response> _post(Uri u, Map<String, String> h, Object body) async {
    final c = _c;
    try {
      return await c
          .post(u, headers: h, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } finally {
      if (_client == null) c.close();
    }
  }

  /// What to ask for from a title like "Movie Name (2019)" or a series episode.
  static Map<String, String> queryFor(MediaItem item,
      {int? season, int? episode, String language = ''}) {
    final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(item.name)?.group(0);
    final isEp = season != null && episode != null;
    return {
      'query': cleanTitle(isEp
          ? item.name
              .split(RegExp(r'\bS\d{1,2}\s*E\d{1,3}\b|\b\d{1,2}x\d{2,3}\b',
                  caseSensitive: false))
              .first
          : item.name),
      'type': isEp ? 'episode' : 'movie',
      if (isEp) 'season_number': '$season',
      if (isEp) 'episode_number': '$episode',
      if (!isEp && year != null) 'year': year,
      if (language.isNotEmpty) 'languages': language.toLowerCase(),
      'order_by': 'download_count',
    };
  }

  Future<List<SubtitleHit>> search(Map<String, String> query) async {
    if (apiKey.isEmpty) {
      throw const SubtitleSearchError(
          'Add your OpenSubtitles API key in Settings first.');
    }
    final res = await _get(
        base.resolve('subtitles').replace(queryParameters: query), _headers);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const SubtitleSearchError(
          'OpenSubtitles did not accept the API key.');
    }
    if (res.statusCode != 200) {
      throw SubtitleSearchError('OpenSubtitles answered ${res.statusCode}.');
    }
    return parseHits(res.body);
  }

  static List<SubtitleHit> parseHits(String body) {
    final j = jsonDecode(body);
    final out = <SubtitleHit>[];
    for (final d in (j is Map ? (j['data'] as List? ?? const []) : const [])) {
      final a = (d as Map)['attributes'] as Map? ?? const {};
      final files = a['files'] as List? ?? const [];
      if (files.isEmpty) continue;
      final f = files.first as Map;
      final id = f['file_id'];
      if (id == null) continue;
      out.add(SubtitleHit(
        fileId: '$id',
        name: ((f['file_name'] ?? a['release'] ?? '') as String),
        language: (a['language'] ?? '') as String,
        downloads: (a['download_count'] as num?)?.toInt() ?? 0,
        hearingImpaired: a['hearing_impaired'] == true,
      ));
    }
    return out;
  }

  Future<String?> _token() async {
    if (username.isEmpty || password.isEmpty) return null;
    final res = await _post(base.resolve('login'), _headers,
        {'username': username, 'password': password});
    if (res.statusCode != 200) {
      throw const SubtitleSearchError(
          'OpenSubtitles did not accept that username and password.');
    }
    return (jsonDecode(res.body) as Map)['token'] as String?;
  }

  /// The text of the subtitle file, ready to hand to the player.
  Future<String> download(SubtitleHit hit) async {
    final token = await _token();
    final res = await _post(base.resolve('download'), {
      ..._headers,
      if (token != null) 'Authorization': 'Bearer $token',
    }, {
      'file_id': int.tryParse(hit.fileId) ?? hit.fileId
    });
    if (res.statusCode == 406) {
      throw const SubtitleSearchError(
          'Today\'s OpenSubtitles download limit is used up.');
    }
    if (res.statusCode == 401) {
      throw const SubtitleSearchError(
          'Downloading needs your OpenSubtitles username and password in Settings.');
    }
    if (res.statusCode != 200) {
      throw SubtitleSearchError('OpenSubtitles answered ${res.statusCode}.');
    }
    final link = (jsonDecode(res.body) as Map)['link'] as String?;
    if (link == null) {
      throw const SubtitleSearchError('OpenSubtitles sent no file.');
    }
    final file = await _get(Uri.parse(link), {'User-Agent': _agent});
    if (file.statusCode != 200) {
      throw SubtitleSearchError(
          'The subtitle file could not be fetched (${file.statusCode}).');
    }
    return utf8.decode(file.bodyBytes, allowMalformed: true);
  }
}
