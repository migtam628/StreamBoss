import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/channel_filter.dart';
import 'package:streamboss/services/languages.dart';
import 'package:streamboss/services/vod_filter.dart';

MediaItem item(String id, String name, String cat, {MediaKind kind = MediaKind.live}) =>
    MediaItem(id: id, name: name, kind: kind, categoryId: cat, streamUrl: 'http://x/$id');

void main() {
  group('languageOf', () {
    test('reads tags, words and countries', () {
      expect(languageOf('EN | Movies')?.code, 'en');
      expect(languageOf('[FR] Cinéma')?.code, 'fr');
      expect(languageOf('Latino Series')?.code, 'es');
      expect(languageOf('Harbor Lights VOSTFR')?.code, 'fr');
      expect(languageOf('UK | News')?.code, 'en');
      expect(languageOf('UA | News')?.code, 'uk');
      expect(languageOf('Sports'), isNull);
      expect(languageOf(''), isNull);
    });
  });

  group('multi-select filters', () {
    final cats = {'1': 'US | News', '2': 'GB | News', '3': 'ES | Deportes', '4': 'IT | Calcio', '5': 'Misc'};
    final ch = [
      item('a', 'CNN', '1'),
      item('b', 'BBC One', '2'),
      item('c', 'La 1', '3'),
      item('d', 'Rai 1', '4'),
      item('e', 'Plain', '5'),
    ];
    List<String> names(ChannelFilter f) => [
          for (final c in applyChannelFilter(ch, f,
              categoryName: (c) => cats[c.categoryId]!,
              isFavorite: (_) => false,
              hasGuide: (_) => true))
            c.name
        ];

    test('several countries at once', () {
      expect(names(const ChannelFilter(countries: {'US', 'GB'})), ['CNN', 'BBC One']);
    });
    test('several languages at once', () {
      expect(names(const ChannelFilter(languages: {'es', 'en', 'it'})), ['CNN', 'BBC One', 'La 1', 'Rai 1']);
      expect(names(const ChannelFilter(languages: {'it'})), ['Rai 1']);
    });
    test('count and equality ignore order', () {
      expect(const ChannelFilter(countries: {'US', 'GB'}).count, 1);
      expect(const ChannelFilter(languages: {'es', 'en'}) == const ChannelFilter(languages: {'en', 'es'}), isTrue);
      expect(const ChannelFilter().copyWith(languages: {'en'}).copyWith(languages: {}).active, isFalse);
    });
    test('vod filter keeps the chosen languages', () {
      final m = [
        item('1', 'Una', '3', kind: MediaKind.movie),
        item('2', 'Uno', '4', kind: MediaKind.movie),
        item('3', 'One', '1', kind: MediaKind.movie),
      ];
      final out = applyVodFilter(m, const VodFilter(languages: {'es', 'en'}),
          categoryName: (i) => cats[i.categoryId]!, isFavorite: (_) => false, started: (_) => false);
      expect([for (final i in out) i.name], ['Una', 'One']);
      expect(const VodFilter(languages: {'es'}).count, 1);
    });
    test('languagesIn counts, biggest first', () {
      final l = languagesIn(ch, (c) => cats[c.categoryId]!);
      expect([for (final e in l) e.$1.code].toSet(), {'en', 'es', 'it'});
      expect(l.first.$2, 2);
    });
  });
}
