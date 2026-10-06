import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/media.dart';
import 'http_client.dart';
import 'm3u_parser.dart';
import 'net_config.dart';

/// A public playlist the user can add with one tap.
class FreeList {
  final String id, name, blurb, url;

  /// Several MB: slow to download and to parse on a weak device.
  final bool large;
  const FreeList(this.id, this.name, this.blurb, this.url,
      {this.large = false});
}

const _org = 'https://iptv-org.github.io/iptv';

/// Public playlists maintained by the iptv-org project (https://github.com/iptv-org/iptv), a directory
/// of publicly available channels. They are third-party lists: StreamBoss does not host them, check
/// that a stream is still up, or know what rights apply where you are.
const _categories = <(String, String)>[
  ('news', 'News'),
  ('sports', 'Sports'),
  ('movies', 'Movies'),
  ('series', 'Series'),
  ('entertainment', 'Entertainment'),
  ('kids', 'Kids'),
  ('animation', 'Animation'),
  ('family', 'Family'),
  ('comedy', 'Comedy'),
  ('documentary', 'Documentary'),
  ('music', 'Music'),
  ('culture', 'Culture'),
  ('education', 'Education'),
  ('science', 'Science'),
  ('lifestyle', 'Lifestyle'),
  ('cooking', 'Cooking'),
  ('travel', 'Travel'),
  ('outdoor', 'Outdoor'),
  ('classic', 'Classic'),
  ('business', 'Business'),
  ('weather', 'Weather'),
  ('legislative', 'Government and parliament'),
  ('public', 'Public service'),
  ('religious', 'Religious'),
  ('auto', 'Auto'),
  ('shop', 'Shopping'),
  ('relax', 'Relax'),
  ('general', 'General'),
];

final List<FreeList> freeCategories = [
  for (final c in _categories)
    FreeList('cat-${c.$1}', c.$2, 'Free channels tagged ${c.$2.toLowerCase()}',
        '$_org/categories/${c.$1}.m3u'),
];

const _languages = <(String, String)>[
  ('eng', 'English'),
  ('spa', 'Spanish'),
  ('fra', 'French'),
  ('deu', 'German'),
  ('por', 'Portuguese'),
  ('ita', 'Italian'),
  ('nld', 'Dutch'),
  ('rus', 'Russian'),
  ('ukr', 'Ukrainian'),
  ('pol', 'Polish'),
  ('tur', 'Turkish'),
  ('ara', 'Arabic'),
  ('heb', 'Hebrew'),
  ('fas', 'Persian'),
  ('hin', 'Hindi'),
  ('ben', 'Bengali'),
  ('urd', 'Urdu'),
  ('tam', 'Tamil'),
  ('zho', 'Chinese'),
  ('jpn', 'Japanese'),
  ('kor', 'Korean'),
  ('vie', 'Vietnamese'),
  ('tha', 'Thai'),
  ('ind', 'Indonesian'),
  ('swe', 'Swedish'),
  ('nor', 'Norwegian'),
  ('dan', 'Danish'),
  ('fin', 'Finnish'),
  ('ell', 'Greek'),
  ('ron', 'Romanian'),
  ('hun', 'Hungarian'),
  ('ces', 'Czech'),
  ('srp', 'Serbian'),
  ('hrv', 'Croatian'),
  ('bul', 'Bulgarian'),
];

final List<FreeList> freeLanguages = [
  for (final l in _languages)
    FreeList('lang-${l.$1}', l.$2, 'Free channels in ${l.$2}',
        '$_org/languages/${l.$1}.m3u'),
];

/// Ready-made collections: another curated directory and the big combined list.
const freeCollections = <FreeList>[
  FreeList(
      'freetv',
      'Free-TV',
      'Free-to-air channels curated by the Free-TV project (github.com/Free-TV/IPTV), grouped by country',
      'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8'),
  FreeList(
      'org-all-country',
      'Every iptv-org channel, by country',
      'The whole iptv-org directory in one list. Large: slow to load on a weak device',
      '$_org/index.country.m3u',
      large: true),
];

/// iptv-org names a country's file with its lower-case ISO code, except the United Kingdom ("uk").
String _countryFile(String code) {
  final c = code.toLowerCase();
  return c == 'gb' ? 'uk' : c;
}

/// Countries from iptv-org's countries.json: `[{"name": "Albania", "code": "AL"}, ...]`.
List<FreeList> freeCountriesFrom(Object? json) {
  final out = <FreeList>[];
  if (json is List) {
    for (final e in json) {
      if (e is Map && e['name'] is String && e['code'] is String) {
        final name = e['name'] as String;
        out.add(FreeList(
            'country-${(e['code'] as String).toLowerCase()}',
            name,
            'Free channels from $name',
            '$_org/countries/${_countryFile(e['code'] as String)}.m3u'));
      }
    }
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// The built-in list used when countries.json can't be fetched.
final List<FreeList> fallbackCountries = freeCountriesFrom([
  for (final c in const [
    ('United States', 'US'),
    ('United Kingdom', 'GB'),
    ('Canada', 'CA'),
    ('Australia', 'AU'),
    ('Spain', 'ES'),
    ('Mexico', 'MX'),
    ('France', 'FR'),
    ('Germany', 'DE'),
    ('Italy', 'IT'),
    ('Brazil', 'BR'),
    ('India', 'IN'),
    ('Turkey', 'TR'),
  ])
    {'name': c.$1, 'code': c.$2},
]);

Future<List<FreeList>> loadFreeCountries({http.Client? client}) async {
  try {
    final res = await (client ?? appHttp)
        .get(Uri.parse('https://iptv-org.github.io/api/countries.json'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) {
      final list = freeCountriesFrom(jsonDecode(utf8.decode(res.bodyBytes)));
      if (list.isNotEmpty) return list;
    }
  } catch (_) {}
  return fallbackCountries;
}

/// Name for the source made from [picked].
String freeSourceName(List<FreeList> picked) => picked.length == 1
    ? 'Free: ${picked.first.name}'
    : 'Free channels (${picked.length} lists)';

/// Downloads every playlist in [urls] (a few at a time, so a long list is polite to the host) and
/// merges them. A list that fails to load is skipped; it only throws when none loads.
Future<Catalog> loadMergedPlaylists(List<String> urls,
    {http.Client? client, int parallel = 6}) async {
  final parts = <Catalog>[];
  for (var i = 0; i < urls.length; i += parallel) {
    final batch = urls.skip(i).take(parallel);
    final got = await Future.wait(batch.map((u) async {
      try {
        final res = await (client ?? appHttp)
            .get(Uri.parse(u), headers: NetConfig.headers)
            .timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) return null;
        return parseM3u(utf8.decode(res.bodyBytes, allowMalformed: true));
      } catch (_) {
        return null;
      }
    }));
    parts.addAll(got.whereType<Catalog>());
  }
  if (parts.isEmpty) {
    throw Exception('None of the ${urls.length} playlists could be loaded');
  }
  return mergeCatalogs(parts);
}
