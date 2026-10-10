import '../models/media.dart';

/// A country that live channels can be filed under, with where its pin goes on the map.
class Country {
  final String code, name;
  final double lon, lat;

  /// Lower-case spellings that name it: its two and three letter codes and the common words.
  final List<String> aliases;
  const Country(this.code, this.name, this.lon, this.lat, this.aliases);
}

const countries = <Country>[
  Country('US', 'United States', -98, 39,
      ['us', 'usa', 'united states', 'america']),
  Country('CA', 'Canada', -100, 57, ['ca', 'can', 'canada']),
  Country('MX', 'Mexico', -102, 23, ['mx', 'mex', 'mexico']),
  Country('BR', 'Brazil', -52, -10, ['br', 'bra', 'brazil', 'brasil']),
  Country('AR', 'Argentina', -64, -34, ['ar', 'arg', 'argentina']),
  Country('CL', 'Chile', -71, -33, ['cl', 'chl', 'chile']),
  Country('CO', 'Colombia', -74, 4, ['co', 'col', 'colombia']),
  Country('PE', 'Peru', -76, -10, ['pe', 'per', 'peru']),
  Country('VE', 'Venezuela', -66, 8, ['ve', 'ven', 'venezuela']),
  Country('GB', 'United Kingdom', -2, 54,
      ['gb', 'uk', 'gbr', 'united kingdom', 'britain', 'england']),
  Country('IE', 'Ireland', -8, 53, ['ie', 'irl', 'ireland']),
  Country('FR', 'France', 2, 46, ['fr', 'fra', 'france']),
  Country('ES', 'Spain', -4, 40, ['es', 'esp', 'spain', 'espana']),
  Country('PT', 'Portugal', -8, 39.5, ['pt', 'prt', 'portugal']),
  Country(
      'DE', 'Germany', 10, 51, ['de', 'ger', 'deu', 'germany', 'deutschland']),
  Country('IT', 'Italy', 12, 42, ['it', 'ita', 'italy', 'italia']),
  Country('NL', 'Netherlands', 5, 52, ['nl', 'nld', 'netherlands', 'holland']),
  Country('BE', 'Belgium', 4.5, 50.5, ['be', 'bel', 'belgium']),
  Country('CH', 'Switzerland', 8, 47, ['ch', 'che', 'switzerland']),
  Country('AT', 'Austria', 14, 47.5, ['at', 'aut', 'austria']),
  Country('SE', 'Sweden', 16, 62, ['se', 'swe', 'sweden']),
  Country('NO', 'Norway', 9, 61, ['no', 'nor', 'norway']),
  Country('DK', 'Denmark', 10, 56, ['dk', 'dnk', 'denmark']),
  Country('FI', 'Finland', 26, 63, ['fi', 'fin', 'finland']),
  Country('PL', 'Poland', 19, 52, ['pl', 'pol', 'poland']),
  Country(
      'CZ', 'Czechia', 15.5, 49.8, ['cz', 'cze', 'czechia', 'czech republic']),
  Country('GR', 'Greece', 22, 39, ['gr', 'grc', 'greece']),
  Country('RO', 'Romania', 25, 46, ['ro', 'rou', 'romania']),
  Country('HU', 'Hungary', 19, 47, ['hu', 'hun', 'hungary']),
  Country('UA', 'Ukraine', 31, 49, ['ua', 'ukr', 'ukraine']),
  Country('RU', 'Russia', 60, 60, ['ru', 'rus', 'russia']),
  Country('TR', 'Turkey', 35, 39, ['tr', 'tur', 'turkey', 'turkiye']),
  Country('IL', 'Israel', 35, 31, ['il', 'isr', 'israel']),
  Country('SA', 'Saudi Arabia', 45, 24, ['sa', 'sau', 'saudi arabia']),
  Country('AE', 'United Arab Emirates', 54, 24,
      ['ae', 'uae', 'are', 'united arab emirates']),
  Country('EG', 'Egypt', 30, 27, ['eg', 'egy', 'egypt']),
  Country('MA', 'Morocco', -7, 32, ['ma', 'mar', 'morocco']),
  Country('NG', 'Nigeria', 8, 9, ['ng', 'nga', 'nigeria']),
  Country('ZA', 'South Africa', 25, -29, ['za', 'zaf', 'south africa']),
  Country('KE', 'Kenya', 38, 0, ['ke', 'ken', 'kenya']),
  Country('IN', 'India', 78, 22, ['in', 'ind', 'india']),
  Country('PK', 'Pakistan', 70, 30, ['pk', 'pak', 'pakistan']),
  Country('BD', 'Bangladesh', 90, 24, ['bd', 'bgd', 'bangladesh']),
  Country('CN', 'China', 104, 35, ['cn', 'chn', 'china']),
  Country('JP', 'Japan', 138, 36, ['jp', 'jpn', 'japan']),
  Country('KR', 'South Korea', 128, 36, ['kr', 'kor', 'south korea', 'korea']),
  Country('TH', 'Thailand', 101, 15, ['th', 'tha', 'thailand']),
  Country('VN', 'Vietnam', 106, 16, ['vn', 'vnm', 'vietnam']),
  Country('PH', 'Philippines', 122, 13, ['ph', 'phl', 'philippines']),
  Country('ID', 'Indonesia', 114, -2, ['id', 'idn', 'indonesia']),
  Country('MY', 'Malaysia', 102, 4, ['my', 'mys', 'malaysia']),
  Country('AU', 'Australia', 134, -25, ['au', 'aus', 'australia']),
  Country('NZ', 'New Zealand', 172, -41, ['nz', 'nzl', 'new zealand']),
];

final Map<String, Country> _byAlias = {
  for (final c in countries)
    for (final a in c.aliases) a: c,
};

final _prefixCode = RegExp(r'^[\s\[\(\|]*([A-Za-z]{2,3})\s*[\]\)\|:/\-]\s*',
    caseSensitive: false);
final _bracketCode = RegExp(r'^\s*[\[\(]([A-Za-z]{2,3})[\]\)]');
final _separators = RegExp(r'\s*[\|:/\-\[\]\(\)]\s*');

/// The country a category or channel name belongs to ("ES | Sports", "[UK] News", "Spain - Movies"), or null.
Country? countryOf(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final m = _bracketCode.firstMatch(t) ?? _prefixCode.firstMatch(t);
  if (m != null) {
    final c = _byAlias[m.group(1)!.toLowerCase()];
    if (c != null) return c;
  }
  // A whole country name as the first part: "Spain - News", "United States | Sports".
  final first = t
      .split(_separators)
      .firstWhere((s) => s.isNotEmpty, orElse: () => '')
      .toLowerCase();
  final c = first.length > 3 ? _byAlias[first] : null;
  if (c != null) return c;
  final lower = t.toLowerCase();
  for (final cn in countries) {
    for (final a in cn.aliases) {
      if (a.length > 3 && lower.startsWith('$a ')) return cn;
    }
  }
  return null;
}

/// A category name without its country: "ES | Sports" becomes "Sports".
String categoryLabel(String name) {
  var t = name.trim();
  final m = _bracketCode.firstMatch(t) ?? _prefixCode.firstMatch(t);
  if (m != null && _byAlias.containsKey(m.group(1)!.toLowerCase())) {
    t = t.substring(m.end).trim();
  } else {
    final parts = t.split(_separators).where((s) => s.isNotEmpty).toList();
    if (parts.length > 1 && countryOf(parts.first) != null) {
      t = parts.skip(1).join(' ').trim();
    }
  }
  return t.isEmpty ? 'General' : t;
}

class CountryGroup {
  final Country country;
  final List<MediaItem> channels;
  const CountryGroup(this.country, this.channels);
}

/// Files the live channels under countries, biggest first. A category names the country for all its
/// channels; a channel name can name it when the category does not. Channels with no country are left out.
List<CountryGroup> groupByCountry(Catalog c) {
  final byCat = <String, Country?>{
    for (final cat in c.liveCategories) cat.id: countryOf(cat.name),
  };
  final map = <String, List<MediaItem>>{};
  final by = <String, Country>{};
  for (final ch in c.live) {
    final cn = byCat[ch.categoryId] ?? countryOf(ch.name);
    if (cn == null) continue;
    by[cn.code] = cn;
    (map[cn.code] ??= []).add(ch);
  }
  final out = [for (final e in map.entries) CountryGroup(by[e.key]!, e.value)];
  out.sort((a, b) => b.channels.length.compareTo(a.channels.length));
  return out;
}
