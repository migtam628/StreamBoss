import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/channel_merge.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';

MediaItem ch(String id, String name,
        {String? epg, String? poster, String cat = 'c'}) =>
    MediaItem(
        id: id,
        name: name,
        kind: MediaKind.live,
        streamUrl: 'http://x/$id',
        epgId: epg,
        poster: poster,
        categoryId: cat);

void main() {
  group('channelBase', () {
    test('drops delivery words but keeps what makes the channel', () {
      expect(channelBase('Sky Sports 1 HD'), 'sky sports 1');
      expect(channelBase('Sky Sports 1 [FHD]'), 'sky sports 1');
      expect(channelBase('Sky Sports 1 (SD)'), 'sky sports 1');
      expect(channelBase('SKY SPORTS 1 4K'), 'sky sports 1');
      expect(channelBase('Sky Sports 1 HEVC 50fps'), 'sky sports 1');
      expect(channelBase('Sky Sports 1 1080p'), 'sky sports 1');
    });

    test('keeps numbers and country tags apart', () {
      expect(channelBase('Sports 1'), isNot(channelBase('Sports 2')));
      expect(channelBase('US: Fox HD'), isNot(channelBase('UK: Fox HD')));
      expect(channelBase('Fox (US) HD'), 'fox us');
    });

    test('a name that is only a delivery word stays as it is', () {
      expect(channelBase('HD'), 'hd');
      expect(channelBase('4K'), '4k');
    });
  });

  test('quality order', () {
    expect(channelQuality('Chan 4K'), 4);
    expect(channelQuality('Chan UHD'), 4);
    expect(channelQuality('Chan FHD'), 3);
    expect(channelQuality('Chan 1080p'), 3);
    expect(channelQuality('Chan HD'), 2);
    expect(channelQuality('Chan'), 1);
    expect(channelQuality('Chan SD'), 0);
  });

  group('mergeDuplicateChannels', () {
    test(
        'shows one entry per channel, the best copy, in the place of the first',
        () {
      final r = mergeDuplicateChannels([
        ch('1', 'News One SD'),
        ch('2', 'Weather'),
        ch('3', 'News One HD'),
        ch('4', 'News One'),
      ]);
      expect(r.channels.map((e) => e.name), ['News One HD', 'Weather']);
      expect(r.alternates['live:3']!.map((e) => e.id),
          ['4', '1']); // plain before SD
      expect(r.alternates.containsKey('live:2'), isFalse);
    });

    test('leaves different channels alone', () {
      final r = mergeDuplicateChannels([
        ch('1', 'Sports 1'),
        ch('2', 'Sports 2'),
        ch('3', 'US: Fox'),
        ch('4', 'UK: Fox')
      ]);
      expect(r.channels, hasLength(4));
      expect(r.alternates, isEmpty);
    });

    test('prefers a copy that is not known to be dead', () {
      final r = mergeDuplicateChannels(
          [ch('1', 'Movie Max HD'), ch('2', 'Movie Max SD')],
          deadKeys: {'live:1'});
      expect(r.channels.single.id, '2');
      expect(r.alternates['live:2']!.single.id, '1');
    });

    test('lends the guide id and the logo of a copy to the one that is shown',
        () {
      final r = mergeDuplicateChannels([
        ch('1', 'Docu HD'),
        ch('2', 'Docu SD', epg: 'docu.tv', poster: 'http://x/logo.png'),
      ]);
      expect(r.channels.single.id, '1');
      expect(r.channels.single.epgId, 'docu.tv');
      expect(r.channels.single.poster, 'http://x/logo.png');
      expect(r.channels.single.streamUrl,
          'http://x/1'); // still plays its own stream
    });

    test('an empty or single list comes back as it was', () {
      expect(mergeDuplicateChannels(const []).channels, isEmpty);
      final one = ch('1', 'Solo');
      expect(mergeDuplicateChannels([one]).channels.single, same(one));
    });

    test('ties keep the provider order', () {
      final r = mergeDuplicateChannels([ch('9', 'Zed'), ch('1', 'Zed')]);
      expect(r.channels.single.id, '9');
    });
  });

  group('in the app', () {
    Future<(AppState, SettingsState)> app(
        {Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final st = SettingsState();
      await st.init();
      final a = AppState()..bindSettings(st);
      await a.init();
      a.catalog = Catalog(
        liveCategories: const [Category('c', 'News')],
        live: [
          ch('1', 'News One SD'),
          ch('2', 'News One HD'),
          ch('3', 'Weather')
        ],
      );
      return (a, st);
    }

    test('merging is on by default and can be turned off', () async {
      final (a, st) = await app();
      expect(a.shown.live.map((e) => e.name), ['News One HD', 'Weather']);
      expect(a.alternatesFor(a.shown.live.first).single.id, '1');
      st.set('mergeDuplicates', false);
      expect(a.shown.live, hasLength(3));
      expect(a.alternatesFor(a.shown.live.first), isEmpty);
    });

    test('a favorite copy keeps the merged channel a favorite', () async {
      final (a, _) = await app();
      final shown = a.shown.live.first;
      expect(a.isFavorite(shown), isFalse);
      a.favorites.add('live:1'); // saved from the SD copy
      expect(a.isFavorite(shown), isTrue);
    });

    test('a copy found dead gives way to the other', () async {
      final (a, _) = await app();
      a.active = const Source(name: 'S', type: SourceType.m3u, url: 'x');
      // Pretend the HD copy failed a check.
      await a.setDeadForTest({'live:2'});
      expect(a.shown.live.first.id, '1');
    });
  });
}
