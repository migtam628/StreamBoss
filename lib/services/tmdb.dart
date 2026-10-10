import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media.dart';

/// A person in the cast, with the part they play and a photo when there is one.
class Person {
  final String name;
  final String? role, photo;
  const Person(this.name, [this.role, this.photo]);
}

/// What the provider says about the file itself (Xtream passes on what ffprobe found).
class TechInfo {
  final String? videoCodec, audioCodec, container, audioLanguage;
  final int? width, height, audioChannels, bitrateKbps;
  const TechInfo({
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.audioLanguage,
    this.width,
    this.height,
    this.audioChannels,
    this.bitrateKbps,
  });

  bool get isEmpty =>
      videoCodec == null && audioCodec == null && container == null && width == null && audioChannels == null && bitrateKbps == null;

  /// "1080p" for 1920x1080 and "4K" for 3840 wide; null when the size is unknown.
  String? get resolution {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    if (w >= 3200 || h >= 2000) return '4K';
    if (w >= 1800 || h >= 1000) return '1080p';
    if (w >= 1200 || h >= 700) return '720p';
    return '${h}p';
  }

  /// "5.1" for six channels, "Stereo" for two.
  String? get channels => switch (audioChannels) {
        null => null,
        1 => 'Mono',
        2 => 'Stereo',
        6 => '5.1',
        8 => '7.1',
        final n => '$n ch',
      };
}

class TmdbInfo {
  final String? overview;
  final double? rating;
  final String? year;
  final String? backdrop;
  final String? poster;
  final int? runtimeMin;
  final List<String> cast;
  final String? trailerKey;

  /// More facts for the details pages. Empty or null when nobody knew.
  final List<Person> people;
  final List<String> genres, directors, countries;
  final String? certification, status, network, tagline;
  final int? seasons, episodes;
  final TechInfo? tech;
  const TmdbInfo({
    this.overview,
    this.rating,
    this.year,
    this.backdrop,
    this.poster,
    this.runtimeMin,
    this.cast = const [],
    this.trailerKey,
    this.people = const [],
    this.genres = const [],
    this.directors = const [],
    this.countries = const [],
    this.certification,
    this.status,
    this.network,
    this.tagline,
    this.seasons,
    this.episodes,
    this.tech,
  });
}

/// Combines two sources field by field: values from [a] win, [b] fills the gaps.
TmdbInfo? mergeInfo(TmdbInfo? a, TmdbInfo? b) {
  if (a == null) return b;
  if (b == null) return a;
  String? nz(String? v) => (v == null || v.trim().isEmpty) ? null : v;
  return TmdbInfo(
    overview: nz(a.overview) ?? nz(b.overview),
    rating: a.rating ?? b.rating,
    year: a.year ?? b.year,
    backdrop: a.backdrop ?? b.backdrop,
    poster: a.poster ?? b.poster,
    runtimeMin: a.runtimeMin ?? b.runtimeMin,
    cast: a.cast.isNotEmpty ? a.cast : b.cast,
    trailerKey: a.trailerKey ?? b.trailerKey,
    people: a.people.isNotEmpty ? a.people : b.people,
    genres: a.genres.isNotEmpty ? a.genres : b.genres,
    directors: a.directors.isNotEmpty ? a.directors : b.directors,
    countries: a.countries.isNotEmpty ? a.countries : b.countries,
    certification: nz(a.certification) ?? nz(b.certification),
    status: nz(a.status) ?? nz(b.status),
    network: nz(a.network) ?? nz(b.network),
    tagline: nz(a.tagline) ?? nz(b.tagline),
    seasons: a.seasons ?? b.seasons,
    episodes: a.episodes ?? b.episodes,
    tech: a.tech ?? b.tech,
  );
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
  final http.Client? _client;
  TmdbService(this.apiKey, {http.Client? client}) : _client = client;

  static const _img = 'https://image.tmdb.org/t/p';

  Future<Map<String, dynamic>?> _json(String path, Map<String, String> q) async {
    final uri = Uri.https('api.themoviedb.org', '/3/$path', {'api_key': apiKey, ...q});
    final res = await (_client?.get(uri) ?? http.get(uri)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// A poster address for a movie or series that came without one: '' when TMDB has none for it,
  /// null when it could not be asked (no key, no network), so a later try is allowed.
  Future<String?> posterFor(MediaItem item) async {
    if (apiKey.isEmpty || item.kind == MediaKind.live) return null;
    final type = item.kind == MediaKind.series ? 'tv' : 'movie';
    final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(item.name)?.group(0);
    try {
      final search = await _json('search/$type', {
        'query': cleanTitle(item.name),
        if (year != null) (type == 'tv' ? 'first_air_date_year' : 'primary_release_year'): year,
      });
      if (search == null) return null;
      for (final r in (search['results'] as List? ?? const [])) {
        final path = r['poster_path'] as String?;
        if (path != null && path.isNotEmpty) return '$_img/w342$path';
      }
      return '';
    } catch (_) {
      return null;
    }
  }

  Future<TmdbInfo?> lookup(MediaItem item) async {
    if (apiKey.isEmpty || item.kind == MediaKind.live) return null;
    final type = item.kind == MediaKind.series ? 'tv' : 'movie';
    try {
      final search = await _json('search/$type', {'query': cleanTitle(item.name)});
      final results = search?['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final id = results.first['id'];
      final d = await _json(
          '$type/$id', {'append_to_response': type == 'tv' ? 'credits,videos,content_ratings' : 'credits,videos,release_dates'});
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
        people: [
          for (final c in ((d['credits']?['cast'] as List?) ?? const []).take(16))
            Person(c['name'] as String, c['character'] as String?, img(c['profile_path'] as String?, 'w185')),
        ],
        genres: [for (final g in (d['genres'] as List? ?? const [])) '${g['name']}'],
        directors: type == 'tv'
            ? [for (final c in (d['created_by'] as List? ?? const [])) '${c['name']}']
            : [
                for (final c in ((d['credits']?['crew'] as List?) ?? const []))
                  if (c['job'] == 'Director') '${c['name']}',
              ],
        countries: [for (final c in (d['production_countries'] as List? ?? const [])) '${c['name']}'],
        certification: certificationOf(d, type),
        status: d['status'] as String?,
        network: (d['networks'] as List?)?.isNotEmpty == true ? '${d['networks'][0]['name']}' : null,
        tagline: (d['tagline'] as String?)?.isNotEmpty == true ? d['tagline'] as String : null,
        seasons: (d['number_of_seasons'] as num?)?.toInt(),
        episodes: (d['number_of_episodes'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

}

/// The age rating TMDB lists, preferring the US one ("PG-13", "TV-MA"), else the first it has.
String? certificationOf(Map<String, dynamic> d, String type) {
  String? pick(List results, String Function(Map) cert) {
    String? first;
    for (final r in results.whereType<Map>()) {
      final c = cert(r).trim();
      if (c.isEmpty) continue;
      if (r['iso_3166_1'] == 'US') return c;
      first ??= c;
    }
    return first;
  }

  if (type == 'tv') {
    return pick((d['content_ratings']?['results'] as List?) ?? const [], (r) => '${r['rating'] ?? ''}');
  }
  return pick((d['release_dates']?['results'] as List?) ?? const [], (r) {
    for (final x in (r['release_dates'] as List? ?? const [])) {
      final c = '${x['certification'] ?? ''}'.trim();
      if (c.isNotEmpty) return c;
    }
    return '';
  });
}
