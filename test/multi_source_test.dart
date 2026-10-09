import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/combine_sources.dart';
import 'package:streamboss/services/xmltv.dart';
import 'package:streamboss/state/app_state.dart';

// Real loopback servers, so this lives apart from the widget tests.

MediaItem it(String id, String name, MediaKind k, {String cat = '1'}) =>
    MediaItem(
        id: id,
        name: name,
        kind: k,
        categoryId: cat,
        streamUrl: 'http://x/$id');

void main() {
  group('combineSources', () {
    final main = Catalog(
      liveCategories: const [Category('1', 'News'), Category('2', 'Sports')],
      movieCategories: const [Category('m', 'Drama')],
      live: [
        it('1', 'Main One', MediaKind.live),
        it('2', 'Main Two', MediaKind.live, cat: '2')
      ],
      movies: [it('9', 'A Movie', MediaKind.movie, cat: 'm')],
      epgUrl: 'http://main/guide.xml',
    );
    final other = Catalog(
      liveCategories: const [Category('1', 'News'), Category('7', 'Kids')],
      seriesCategories: const [Category('s', 'Shows')],
      live: [
        it('1', 'Other One', MediaKind.live),
        it('3', 'Other Kids', MediaKind.live, cat: '7')
      ],
      series: [it('50', 'A Show', MediaKind.series, cat: 's')],
    );

    test('with nothing to add the main library comes back as it was', () {
      expect(identical(combineSources(main, const []), main), isTrue);
    });

    test('keeps the main source as it is and tags everything from the others',
        () {
      final c = combineSources(main, [('B', other)]);
      expect(c.live.map((e) => e.key),
          ['live:1', 'live:2', 'live:B:1', 'live:B:3']);
      expect(c.live.first.src, isNull);
      expect(c.live[2].src, 'B');
      expect(c.live[2].id, '1'); // the id stays what the provider knows it as
      expect(c.series.single.key, 'series:B:50');
      expect(c.movies.single.key, 'movie:9');
      expect(c.epgUrl, 'http://main/guide.xml');
    });

    test(
        'makes category ids unique and tells apart categories with the same name',
        () {
      final c = combineSources(main, [('B', other)]);
      expect(c.liveCategories.map((e) => '${e.id}=${e.name}'),
          ['1=News', '2=Sports', 'B:1=News (B)', 'B:7=Kids']);
      expect(c.live.firstWhere((e) => e.id == '3').categoryId, 'B:7');
      expect(c.seriesCategories.single.id, 'B:s');
      // Every item points at a category that exists.
      final ids = c.liveCategories.map((e) => e.id).toSet();
      expect(c.live.every((e) => ids.contains(e.categoryId)), isTrue);
    });

    test(
        'three sources keep apart, and an item without a category stays without',
        () {
      final c = combineSources(main, [
        ('B', other),
        (
          'C',
          Catalog(
              live: [it('1', 'C One', MediaKind.live, cat: '')],
              liveCategories: const [Category('1', 'News')])
        ),
      ]);
      expect(c.live.map((e) => e.key).toSet().length, c.live.length);
      expect(c.live.last.categoryId, '');
      expect(c.liveCategories.map((e) => e.name), contains('News (C)'));
    });

    test('an item survives being saved with its source', () {
      final c = combineSources(main, [('B', other)]);
      final back = MediaItem.fromJson(c.live[2].toJson());
      expect(back.src, 'B');
      expect(back.key, 'live:B:1');
      expect(back.copyWith(epgId: 'x').src, 'B');
    });
  });

  test(
      'mergeXmltv puts the programmes of a shared channel together in time order',
      () {
    final a = parseXmltv(
        '<tv><programme start="20240101100000 +0000" stop="20240101110000 +0000" channel="x"><title>Late</title></programme></tv>',
        from: DateTime.utc(2024),
        to: DateTime.utc(2025));
    final b = parseXmltv(
        '<tv><channel id="y"><display-name>Why</display-name></channel><programme start="20240101080000 +0000" stop="20240101090000 +0000" channel="x"><title>Early</title></programme>'
        '<programme start="20240101080000 +0000" stop="20240101090000 +0000" channel="y"><title>Only B</title></programme></tv>',
        from: DateTime.utc(2024),
        to: DateTime.utc(2025));
    final m = mergeXmltv([a, b]);
    expect(m.programmes['x']!.map((e) => e.title), ['Early', 'Late']);
    expect(m.programmes['y']!.single.title, 'Only B');
    expect(m.nameToId['why'], 'y');
    expect(mergeXmltv(const []).programmes, isEmpty);
    expect(identical(mergeXmltv([a]), a), isTrue);
  });

  group('AppState with several sources', () {
    late HttpServer srv;
    final hits = <String>[];
    String url(String p) => 'http://127.0.0.1:${srv.port}$p';

    String xml(String ch, String title) {
      final s = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      String f(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}00 +0000';
      return '<tv><channel id="$ch"><display-name>$ch</display-name></channel>'
          '<programme start="${f(s)}" stop="${f(s.add(const Duration(hours: 2)))}" channel="$ch"><title>$title</title></programme></tv>';
    }

    setUp(() async {
      hits.clear();
      srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((r) {
        hits.add('${r.uri.path}?${r.uri.queryParameters['action'] ?? ''}');
        final res = r.response;
        void json(Object o) {
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode(o));
        }

        switch (r.uri.path) {
          case '/a.m3u':
            res.write('#EXTM3U url-tvg="http://127.0.0.1:${srv.port}/a.xml"\n'
                '#EXTINF:-1 tvg-id="aone" group-title="News",A One\nhttp://x/a1.m3u8\n'
                '#EXTINF:-1 group-title="Movies",A Film\nhttp://x/movie/u/p/1.mp4\n');
          case '/a.xml':
            res.write(xml('aone', 'Show on A'));
          case '/xmltv.php':
            res.write(xml('bone', 'Show on B'));
          case '/player_api.php':
            if (r.uri.queryParameters['username'] != 'u') {
              json({
                'user_info': {'auth': 0}
              });
              break;
            }
            switch (r.uri.queryParameters['action'] ?? '') {
              case '':
                json({
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'server_info': {}
                });
              case 'get_live_categories':
                json([
                  {'category_id': '1', 'category_name': 'News'}
                ]);
              case 'get_live_streams':
                json([
                  {
                    'stream_id': 101,
                    'name': 'B One',
                    'category_id': '1',
                    'epg_channel_id': 'bone',
                    'tv_archive': 1,
                    'tv_archive_duration': '2'
                  }
                ]);
              case 'get_series_categories':
                json([
                  {'category_id': '5', 'category_name': 'Shows'}
                ]);
              case 'get_series':
                json([
                  {'series_id': 900, 'name': 'B Show', 'category_id': '5'}
                ]);
              case 'get_series_info':
                json({
                  'episodes': {
                    '1': [
                      {
                        'id': '7001',
                        'episode_num': 1,
                        'title': 'Pilot',
                        'container_extension': 'mp4'
                      }
                    ]
                  }
                });
              case 'get_short_epg':
                json({'epg_listings': []});
              default:
                json([]);
            }
          default:
            res.statusCode = 404;
        }
        res.close();
      });
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() => srv.close(force: true));

    Future<AppState> app({Source? failing}) async {
      final a = AppState();
      await a.init();
      a.sources = [
        Source(name: 'A', type: SourceType.m3u, url: url('/a.m3u')),
        Source(
            name: 'B',
            type: SourceType.xtream,
            url: 'http://127.0.0.1:${srv.port}',
            username: 'u',
            password: 'p'),
        if (failing != null) failing,
      ];
      return a;
    }

    test(
        'an extra source joins the library, with its own channels, series and categories',
        () async {
      final a = await app();
      await a.setExtraSource('B', true);
      await a.activate(a.sources.first);
      expect(a.error, isNull);
      expect(a.sourceCount, 2);
      expect(a.catalog.live.map((e) => e.key), ['live:0', 'live:B:101']);
      expect(a.catalog.live.last.archiveDays, 2);
      expect(a.catalog.series.single.key, 'series:B:900');
      expect(a.catalog.liveCategories.map((e) => e.name), ['News', 'News (B)']);
      expect(a.extraErrors, isEmpty);
    });

    test('guide data, episodes and catch-up go to the source an item came from',
        () async {
      final a = await app();
      await a.setExtraSource('B', true);
      await a.activate(a.sources.first);
      final bOne = a.catalog.live.last;
      final show = a.catalog.series.single;

      hits.clear();
      await a.epg(bOne);
      expect(hits, ['/player_api.php?get_short_epg']);
      final eps = await a.episodes(show);
      expect(eps.single.title, 'Pilot');
      expect(eps.single.url,
          contains('/series/u/p/7001.mp4')); // built from B's login

      expect(a.canCatchUp(bOne), isTrue);
      expect(
          a.catchUpUrl(
              bOne,
              Programme('P', DateTime.utc(2026, 1, 1, 10),
                  DateTime.utc(2026, 1, 1, 11)))!,
          contains('/timeshift/u/p/60/'));
      expect(a.canCatchUp(a.catalog.live.first),
          isFalse); // the M3U source has no archive
    });

    test('the guides of every source are loaded and joined', () async {
      final a = await app();
      await a.setExtraSource('B', true);
      await a.activate(a.sources.first);
      expect(a.hasGuideSource, isTrue);
      await a.loadGuide();
      expect(a.guideError, isNull);
      expect(a.programmesFor(a.catalog.live.first).single.title, 'Show on A');
      expect(a.programmesFor(a.catalog.live.last).single.title, 'Show on B');
    });

    test(
        'a source that cannot load is skipped and reported, and the rest still work',
        () async {
      final a = await app(
          failing: Source(
              name: 'Broken', type: SourceType.m3u, url: url('/nothing.m3u')));
      await a.setExtraSource('B', true);
      await a.setExtraSource('Broken', true);
      await a.activate(a.sources.first);
      expect(a.error, isNull);
      expect(a.catalog.live, hasLength(2));
      expect(a.extraErrors.keys, ['Broken']);
      expect(a.extraErrors['Broken'], contains('404'));
    });

    test('the choice is remembered, and removing a source takes it out',
        () async {
      final a = await app();
      await a.activate(a.sources.first);
      await a.setExtraSource('B', true);
      expect(
          (await SharedPreferences.getInstance()).getStringList('extraSources'),
          ['B']);
      final again = AppState();
      await again.init();
      expect(again.extraSources, {'B'});
      await a.setExtraSource('B', false);
      expect(a.catalog.live.map((e) => e.key), ['live:0']);
      expect(a.sourceCount, 1);
      await a.setExtraSource('B', true);
      await a.removeSource(a.sources.last);
      expect(a.extraSources, isEmpty);
    });

    test(
        'with a source that is not the main one switched on and then made main, nothing is listed twice',
        () async {
      final a = await app();
      await a.setExtraSource('B', true);
      await a.activate(a.sources
          .last); // B becomes the main source; B as an extra of itself is ignored
      expect(a.catalog.live.map((e) => e.key), ['live:101']);
      expect(a.sourceCount, 1);
    });
  });
}
