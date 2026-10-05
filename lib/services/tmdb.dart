import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media.dart';

class TmdbInfo {
  final String? overview;
  final double? rating;
  final String? year;
  final String? backdrop;
  final String? poster;
  final int? runtimeMin;
  final List<String> cast;
  final String? trailerKey;
  const TmdbInfo({
    this.overview,
    this.rating,
    this.year,
    this.backdrop,
    this.poster,
    this.runtimeMin,
    this.cast = const [],
    this.trailerKey,
  });
}

/// Strips quality tags, years and brackets that providers add to titles.
String cleanTitle(String raw) {
  var t = raw.replaceAll(RegExp(r'[\[\(\{][^\]\)\}]*[\]\)\}]'), ' ');
  t = t.replaceAll(RegExp(r'^\s*[A-Z]{2,3}\s*[-:|]\s*'), '');
  t = t.replaceAll(RegExp(r'\b(4k|uhd|fhd|hd|sd|1080p|720p|2160p|x264|x265|hevc|multi|vostfr)\b',
      caseSensitive: false), ' ');
  t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class TmdbService {
  final String apiKey;
  TmdbService(this.apiKey);

  static const _img = 'https://image.tmdb.org/t/p';

  Future<Map<String, dynamic>?> _json(String path, Map<String, String> q) async {
    final uri = Uri.https('api.themoviedb.org', '/3/$path', {'api_key': apiKey, ...q});
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<TmdbInfo?> lookup(MediaItem item) async {
    if (apiKey.isEmpty || item.kind == MediaKind.live) return null;
    final type = item.kind == MediaKind.series ? 'tv' : 'movie';
    try {
      final search = await _json('search/$type', {'query': cleanTitle(item.name)});
      final results = search?['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final id = results.first['id'];
      final d = await _json('$type/$id', {'append_to_response': 'credits,videos'});
      if (d == null) return null;

      final date = (d['release_date'] ?? d['first_air_date'] ?? '') as String;
      String? trailer;
      for (final v in ((d['videos']?['results'] as List?) ?? const [])) {
        if (v['site'] == 'YouTube' && v['type'] == 'Trailer') {
          trailer = v['key'] as String;
          break;
        }
      }
      String? img(String? p, String size) => p == null ? null : '$_img/$size$p';
      return TmdbInfo(
        overview: d['overview'] as String?,
        rating: (d['vote_average'] as num?)?.toDouble(),
        year: date.length >= 4 ? date.substring(0, 4) : null,
        backdrop: img(d['backdrop_path'] as String?, 'w780'),
        poster: img(d['poster_path'] as String?, 'w342'),
        runtimeMin: (d['runtime'] as num?)?.toInt(),
        cast: [
          for (final c in ((d['credits']?['cast'] as List?) ?? const []).take(8))
            c['name'] as String,
        ],
        trailerKey: trailer,
      );
    } catch (_) {
      return null;
    }
  }
}
