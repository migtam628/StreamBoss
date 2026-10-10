import '../models/media.dart';
import 'countries.dart';

/// A language that channels, movies and series can be filtered by.
class Language {
  final String code, name;

  /// Lower-case words and codes that name it ("en", "eng", "english", "latino").
  final List<String> aliases;
  const Language(this.code, this.name, this.aliases);
}

const languages = <Language>[
  Language('en', 'English', ['en', 'eng', 'english', 'inglés', 'ingles', 'anglais']),
  Language('es', 'Spanish', ['es', 'spa', 'esp', 'spanish', 'español', 'espanol', 'castellano', 'latino', 'latina', 'espanhol']),
  Language('fr', 'French', ['fr', 'fre', 'fra', 'french', 'français', 'francais', 'vostfr', 'truefrench', 'vff']),
  Language('de', 'German', ['de', 'ger', 'deu', 'german', 'deutsch', 'alemán']),
  Language('it', 'Italian', ['it', 'ita', 'italian', 'italiano']),
  Language('pt', 'Portuguese', ['pt', 'por', 'portuguese', 'português', 'portugues', 'dublado', 'legendado']),
  Language('nl', 'Dutch', ['nl', 'dut', 'nld', 'dutch', 'nederlands']),
  Language('pl', 'Polish', ['pl', 'pol', 'polish', 'polski']),
  Language('ru', 'Russian', ['ru', 'rus', 'russian', 'русский']),
  Language('uk', 'Ukrainian', ['ukrainian', 'українська']),
  Language('tr', 'Turkish', ['tr', 'tur', 'turkish', 'türkçe', 'turkce']),
  Language('ar', 'Arabic', ['ar', 'ara', 'arabic', 'عربي']),
  Language('he', 'Hebrew', ['he', 'heb', 'hebrew', 'עברית']),
  Language('fa', 'Persian', ['fa', 'persian', 'farsi']),
  Language('hi', 'Hindi', ['hi', 'hin', 'hindi']),
  Language('ur', 'Urdu', ['ur', 'urd', 'urdu']),
  Language('bn', 'Bengali', ['bn', 'ben', 'bengali', 'bangla']),
  Language('ta', 'Tamil', ['ta', 'tam', 'tamil']),
  Language('te', 'Telugu', ['te', 'tel', 'telugu']),
  Language('zh', 'Chinese', ['zh', 'chi', 'zho', 'chinese', 'mandarin', 'cantonese']),
  Language('ja', 'Japanese', ['ja', 'jpn', 'jap', 'japanese']),
  Language('ko', 'Korean', ['ko', 'kor', 'korean']),
  Language('th', 'Thai', ['th', 'tha', 'thai']),
  Language('vi', 'Vietnamese', ['vi', 'vie', 'vietnamese']),
  Language('id', 'Indonesian', ['indonesian', 'bahasa']),
  Language('tl', 'Filipino', ['tl', 'fil', 'tagalog', 'filipino']),
  Language('el', 'Greek', ['el', 'gre', 'ell', 'greek']),
  Language('ro', 'Romanian', ['ro', 'rom', 'ron', 'romanian']),
  Language('hu', 'Hungarian', ['hu', 'hun', 'hungarian']),
  Language('cs', 'Czech', ['cs', 'cze', 'ces', 'czech']),
  Language('sv', 'Swedish', ['sv', 'swe', 'swedish', 'svenska']),
  Language('no', 'Norwegian', ['nor', 'norwegian', 'norsk']),
  Language('da', 'Danish', ['da', 'dan', 'danish', 'dansk']),
  Language('fi', 'Finnish', ['fi', 'fin', 'finnish', 'suomi']),
];

final Map<String, Language> _byCode = {for (final l in languages) l.code: l};
final Map<String, Language> _byAlias = {
  for (final l in languages)
    for (final a in l.aliases) a: l,
};

/// The language most often spoken in a country, for names that only say the country ("UK | News").
const _countryLanguage = {
  'US': 'en', 'CA': 'en', 'GB': 'en', 'IE': 'en', 'AU': 'en', 'NZ': 'en', 'ZA': 'en', 'NG': 'en', 'KE': 'en', 'PH': 'tl',
  'MX': 'es', 'ES': 'es', 'AR': 'es', 'CL': 'es', 'CO': 'es', 'PE': 'es', 'VE': 'es',
  'FR': 'fr', 'DE': 'de', 'AT': 'de', 'IT': 'it', 'PT': 'pt', 'BR': 'pt', 'NL': 'nl',
  'PL': 'pl', 'RU': 'ru', 'UA': 'uk', 'TR': 'tr', 'SA': 'ar', 'AE': 'ar', 'EG': 'ar', 'MA': 'ar', 'IL': 'he',
  'IN': 'hi', 'PK': 'ur', 'BD': 'bn', 'CN': 'zh', 'JP': 'ja', 'KR': 'ko', 'TH': 'th', 'VN': 'vi', 'ID': 'id',
  'GR': 'el', 'RO': 'ro', 'HU': 'hu', 'CZ': 'cs', 'SE': 'sv', 'NO': 'no', 'DK': 'da', 'FI': 'fi',
};

/// Two letter prefixes that are really about a country, even though they are also a language's code:
/// "UK" is the United Kingdom (English), not Ukrainian.
final _prefix = RegExp(r'^[\s\[\(\|]*([A-Za-z]{2,3})\s*[\]\)\|:/\-]');
final _bracket = RegExp(r'[\[\(]\s*([A-Za-z]{2,10})\s*[\]\)]');
final _words = RegExp(r"[\p{L}\p{N}']+", unicode: true);

Language? _fromCode(String c) {
  final l = c.toLowerCase();
  if (l == 'uk') return null; // the country, handled through its language
  return _byAlias[l];
}

/// The language a category or title name points to: a language tag or code ("EN | Movies", "[FR]",
/// "Latino", "VOSTFR"), else the main language of the country it names ("UK | News"), else null.
Language? languageOf(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final pre = _prefix.firstMatch(t);
  if (pre != null) {
    final l = _fromCode(pre.group(1)!);
    if (l != null) return l;
  }
  for (final m in _bracket.allMatches(t)) {
    final l = _fromCode(m.group(1)!);
    if (l != null) return l;
  }
  // Whole words that name a language (not the short codes, which are too easy to hit by accident).
  for (final m in _words.allMatches(t.toLowerCase())) {
    final w = m.group(0)!;
    if (w.length > 3) {
      final l = _byAlias[w];
      if (l != null) return l;
    }
  }
  final c = countryOf(t);
  if (c != null) {
    final code = _countryLanguage[c.code];
    if (code != null) return _byCode[code];
  }
  return null;
}

/// The language name for a code ("es" gives "Spanish").
String languageName(String code) => _byCode[code]?.name ?? code;

final _catCache = <String, String?>{};
final _itemLang = Expando<String>('itemLanguage');
const _none = '';

/// The language code of [item]: from its category name, else from its own name; null when neither says.
String? languageCodeOf(MediaItem item, String category) {
  var cached = _catCache[category];
  if (cached == null && !_catCache.containsKey(category)) {
    if (_catCache.length > 4000) _catCache.clear();
    cached = _catCache[category] = languageOf(category)?.code;
  }
  if (cached != null) return cached;
  var own = _itemLang[item];
  own ??= _itemLang[item] = languageOf(item.name)?.code ?? _none;
  return own == _none ? null : own;
}

/// The languages that appear among [items], most titles first, for a filter's language list.
List<(Language, int)> languagesIn(Iterable<MediaItem> items, String Function(MediaItem) categoryName) {
  final counts = <String, int>{};
  final catNames = <String, String>{};
  for (final i in items) {
    final c = languageCodeOf(i, catNames.putIfAbsent(i.categoryId, () => categoryName(i)));
    if (c != null) counts[c] = (counts[c] ?? 0) + 1;
  }
  final out = [for (final e in counts.entries) (_byCode[e.key]!, e.value)];
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}
