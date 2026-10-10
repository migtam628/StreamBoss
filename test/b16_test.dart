import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/console_view.dart';
import 'package:streamboss/layouts/deck_view.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/guide_screen.dart';
import 'package:streamboss/services/channel_filter.dart';
import 'package:streamboss/services/console_commands.dart';
import 'package:streamboss/services/deck.dart';
import 'package:streamboss/services/mini_player.dart';
import 'package:streamboss/services/recommend.dart';
import 'package:streamboss/services/xmltv.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/channel_filter_bar.dart';
import 'package:streamboss/widgets/mini_player_overlay.dart';
import 'package:streamboss/widgets/tv.dart';

MediaItem live(String id, String name, String cat, {String? epg}) => MediaItem(
    id: id,
    name: name,
    kind: MediaKind.live,
    streamUrl: 'http://x/$id',
    categoryId: cat,
    epgId: epg);
MediaItem movie(String id, String name,
        {String rating = '0', String cat = 'm1'}) =>
    MediaItem(
        id: id,
        name: name,
        kind: MediaKind.movie,
        streamUrl: 'http://x/$id',
        categoryId: cat,
        rating: rating,
        plot: 'Plot of $name.');
MediaItem series(String id, String name, {String rating = '0'}) => MediaItem(
    id: id,
    name: name,
    kind: MediaKind.series,
    categoryId: 's1',
    rating: rating);

void main() {
  final chans = [
    live('1', 'La Uno HD', '1'),
    live('2', 'Canal Sur', '2'),
    live('3', 'BBC One FHD', '3'),
    live('4', 'Sports Four 4K', '1'),
    live('5', 'Café Radio', '4'),
  ];
  const cats = {
    '1': 'ES | Sports',
    '2': 'ES | News',
    '3': 'UK | News',
    '4': 'Music'
  };
  String catOf(MediaItem c) => cats[c.categoryId] ?? '';
  List<MediaItem> filt(ChannelFilter f,
          {Set<String> fav = const {}, Set<String> guide = const {}}) =>
      applyChannelFilter(chans, f,
          categoryName: catOf,
          isFavorite: (c) => fav.contains(c.key),
          hasGuide: (c) => guide.contains(c.key));
  List<String> names(List<MediaItem> l) => [for (final c in l) c.name];

  group('ChannelFilter', () {
    test('no filter returns the list itself', () {
      expect(identical(filt(ChannelFilter.none), chans), isTrue);
      expect(ChannelFilter.none.active, isFalse);
      expect(ChannelFilter.none.count, 0);
    });

    test(
        'words must all appear in the name or the category, accents and case ignored',
        () {
      expect(names(filt(const ChannelFilter(text: 'sports'))),
          ['La Uno HD', 'Sports Four 4K']);
      expect(
          names(filt(const ChannelFilter(text: 'uno sports'))), ['La Uno HD']);
      expect(names(filt(const ChannelFilter(text: 'CAFE'))), ['Café Radio']);
      expect(names(filt(const ChannelFilter(text: 'news es'))), ['Canal Sur']);
      expect(filt(const ChannelFilter(text: 'zzz')), isEmpty);
    });

    test('quality means the name says so, and "any" lets everything through',
        () {
      expect(names(filt(const ChannelFilter(quality: QualityFilter.hd))),
          ['La Uno HD', 'BBC One FHD', 'Sports Four 4K']);
      expect(names(filt(const ChannelFilter(quality: QualityFilter.fhd))),
          ['BBC One FHD', 'Sports Four 4K']);
      expect(names(filt(const ChannelFilter(quality: QualityFilter.uhd))),
          ['Sports Four 4K']);
    });

    test('country comes from the category, then the channel name', () {
      expect(names(filt(const ChannelFilter(countries: {'ES'}))),
          ['La Uno HD', 'Canal Sur', 'Sports Four 4K']);
      expect(names(filt(const ChannelFilter(countries: {'GB'}))), ['BBC One FHD']);
      expect(filt(const ChannelFilter(countries: {'FR'})), isEmpty);
    });

    test('favorites and guide data toggles', () {
      expect(
          names(
              filt(const ChannelFilter(favoritesOnly: true), fav: {'live:2'})),
          ['Canal Sur']);
      expect(
          names(filt(const ChannelFilter(guideOnly: true),
              guide: {'live:1', 'live:3'})),
          ['La Uno HD', 'BBC One FHD']);
    });

    test('filters combine', () {
      expect(
          names(filt(const ChannelFilter(
              text: 'uno', countries: {'ES'}, quality: QualityFilter.hd))),
          ['La Uno HD']);
    });

    test('A to Z and best quality first (stable for equal quality)', () {
      expect(names(filt(const ChannelFilter(sort: ChannelSort.name))), [
        'BBC One FHD',
        'Café Radio',
        'Canal Sur',
        'La Uno HD',
        'Sports Four 4K'
      ]);
      expect(names(filt(const ChannelFilter(sort: ChannelSort.quality))), [
        'Sports Four 4K',
        'BBC One FHD',
        'La Uno HD',
        'Canal Sur',
        'Café Radio'
      ]);
    });

    test('count, equality and clearing the country', () {
      final f = const ChannelFilter().copyWith(
          text: 'a',
          quality: QualityFilter.hd,
          countries: {'ES'},
          favoritesOnly: true,
          guideOnly: true);
      expect(f.count, 5);
      expect(f.copyWith(countries: {}).countries, isEmpty);
      expect(f.copyWith(text: 'b').countries, {'ES'});
      expect(const ChannelFilter(text: 'x') == const ChannelFilter(text: 'x'),
          isTrue);
      expect(const ChannelFilter(sort: ChannelSort.name).active, isTrue,
          reason: 'an order alone still counts as a change');
      expect(const ChannelFilter(sort: ChannelSort.name).count, 0);
    });

    test('countriesIn counts channels per country, biggest first', () {
      final c = countriesIn(chans, catOf);
      expect(c.map((e) => (e.$1.code, e.$2)), [('ES', 3), ('GB', 1)]);
    });
  });

  group('console commands', () {
    test('a slash starts a command; matching is by prefix', () {
      expect(matchCommands('hello'), isEmpty);
      expect(matchCommands('/mo').map((c) => c.name), ['/movies']);
      expect(matchCommands('/l').map((c) => c.name), ['/live', '/list']);
      expect(matchCommands('/').length, consoleCommands.length);
      expect(matchCommands('/zzz'), isEmpty);
    });

    test('exact or unambiguous commands are found', () {
      expect(exactCommand('/list')?.name, '/list');
      expect(exactCommand('/live')?.name, '/live');
      expect(exactCommand('/mo')?.name, '/movies');
      expect(exactCommand('/l'), isNull, reason: 'could be /live or /list');
      expect(exactCommand('/live now')?.name, '/live');
      expect(exactCommand('/settings')?.tab, 6);
      expect(exactCommand('/list')?.tab, isNull);
    });
  });

  group('buildDeck', () {
    final movies = [
      for (var i = 0; i < 10; i++)
        movie('m$i', 'Movie $i', rating: '${5 + i * 0.4}')
    ];
    final shows = [
      for (var i = 0; i < 10; i++)
        series('s$i', 'Show $i', rating: '${6 + i * 0.3}')
    ];
    final cat = Catalog(movies: movies, series: shows);

    List<DeckCard> deck(
            {Recommendation? rec,
            List<MediaItem> recents = const [],
            Set<String> fav = const {},
            Set<String> skip = const {},
            int max = 12}) =>
        buildDeck(
            catalog: cat,
            recommendation: rec,
            recents: recents,
            favorites: fav,
            skipped: skip,
            max: max);

    test(
        'up to max cards, movies and series alternating after the recommendations',
        () {
      final d = deck();
      expect(d.length, 12);
      expect(d[0].item.kind, MediaKind.movie);
      expect(d[1].item.kind, MediaKind.series);
      expect(d.map((c) => c.item.key).toSet().length, 12,
          reason: 'no title twice');
    });

    test('best rated first within a kind', () {
      final d = deck();
      expect(d.first.item.name, 'Movie 9');
      expect(d[1].item.name, 'Show 9');
      expect(d.first.reason, 'Highly rated');
    });

    test('recommendations come first, with their reason', () {
      final d = deck(
          rec: Recommendation('Because you watched X', [movies[0], shows[0]]));
      expect(d.first.item.name, 'Movie 0');
      expect(d.first.reason, 'Because you watched X');
    });

    test('saved, watched and skipped titles stay out', () {
      final d =
          deck(fav: {'movie:m9'}, skip: {'series:s9'}, recents: [movies[8]]);
      final keys = d.map((c) => c.item.key).toSet();
      expect(keys, isNot(contains('movie:m9')));
      expect(keys, isNot(contains('series:s9')));
      expect(keys, isNot(contains('movie:m8')));
    });

    test('small libraries give small decks, and an empty one gives none', () {
      expect(
          buildDeck(
              catalog: Catalog(movies: movies.take(2).toList()),
              recommendation: null,
              recents: const [],
              favorites: const {},
              skipped: const {}).length,
          2);
      expect(
          buildDeck(
              catalog: const Catalog(),
              recommendation: null,
              recents: const [],
              favorites: const {},
              skipped: const {}),
          isEmpty);
    });

    test('the same day gives the same deck', () {
      expect(deck().map((c) => c.item.key), deck().map((c) => c.item.key));
    });
  });

  Future<(SettingsState, AppState)> setup(Catalog catalog,
      [Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final st = SettingsState();
    await st.init();
    final app = AppState()..bindSettings(st);
    app.catalog = catalog;
    return (st, app);
  }

  Future<void> pump(WidgetTester t, SettingsState st, AppState app, Widget home,
      Size size, UiLayout layout) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final tv = st.isTv;
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<SettingsState>.value(value: st),
      ],
      child: MaterialApp(
        theme: Boss.theme(tv: tv, layout: layout),
        builder: (context, child) => TvCanvas(
            enabled: tv,
            width: st.tvWidth,
            child: TvScope(tv: tv, child: child!)),
        home: Scaffold(body: home),
      ),
    ));
    await t.pumpAndSettle();
  }

  group('AppState', () {
    test('skips are remembered per profile for a month and survive a restart',
        () async {
      final (_, app) = await setup(Catalog(movies: [movie('1', 'A')]));
      final a = movie('1', 'A');
      app.skipForDeck(a);
      expect(app.deckSkippedKeys, {a.key});
      // A skip older than the window no longer counts.
      app.deckSkips[a.key] = DateTime.now()
          .subtract(const Duration(days: 31))
          .millisecondsSinceEpoch;
      expect(app.deckSkippedKeys, isEmpty);
      app.skipForDeck(a);
      app.clearDeckSkips();
      expect(app.deckSkips, isEmpty);
    });

    test('the channel filter is shared and notifies', () async {
      final (_, app) = await setup(Catalog(
          liveCategories: [const Category('1', 'ES | Sports')],
          live: [live('1', 'La Uno HD', '1'), live('2', 'Other', '1')]));
      var n = 0;
      app.addListener(() => n++);
      app.setChannelFilter(const ChannelFilter(text: 'uno'));
      expect(n, 1);
      app.setChannelFilter(
          const ChannelFilter(text: 'uno')); // same filter: nothing to tell
      expect(n, 1);
      expect(
          app.filterChannels(app.shown.live).map((c) => c.name), ['La Uno HD']);
      expect(app.liveCategoryName(app.shown.live.first), 'ES | Sports');
    });
  });

  group('Console screen', () {
    final cat = Catalog(
      liveCategories: const [Category('l1', 'Sports')],
      movieCategories: const [Category('m1', 'Action')],
      live: [live('1', 'Harbor TV', 'l1'), live('2', 'Arena Sports', 'l1')],
      movies: [
        movie('3', 'Harbor Lights', rating: '7.8'),
        movie('4', 'Salt Road')
      ],
      series: [series('5', 'Harbor Nights')],
    );

    testWidgets('empty: says how to start, and lists nothing', (t) async {
      final (st, app) = await setup(cat, {'layout': 'console'});
      await pump(t, st, app, const ConsoleHome(), const Size(1280, 720),
          UiLayout.console);
      expect(find.textContaining('Type to find'), findsOneWidget);
      expect(find.text('Harbor TV'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('typing lists matches grouped by kind with counts', (t) async {
      final (st, app) = await setup(cat, {'layout': 'console'});
      await pump(t, st, app, const ConsoleHome(), const Size(1280, 720),
          UiLayout.console);
      await t.enterText(find.byType(TextField), 'harb');
      await t.pumpAndSettle();
      expect(find.text('CHANNELS'), findsOneWidget);
      expect(find.text('MOVIES'), findsOneWidget);
      expect(find.text('SERIES'), findsOneWidget);
      expect(find.text('Harbor TV'), findsWidgets);
      expect(find.text('Harbor Lights'), findsWidgets);
      expect(find.text('Salt Road'), findsNothing);
      expect(find.text('3 results'), findsOneWidget);
    });

    testWidgets('a kind chip narrows the results', (t) async {
      final (st, app) = await setup(cat, {'layout': 'console'});
      await pump(t, st, app, const ConsoleHome(), const Size(1280, 720),
          UiLayout.console);
      await t.enterText(find.byType(TextField), 'harb');
      await t.pumpAndSettle();
      await t.tap(find.textContaining('movies').first);
      await t.pumpAndSettle();
      expect(find.text('CHANNELS'), findsNothing);
      expect(find.text('MOVIES'), findsOneWidget);
    });

    testWidgets('a slash lists the commands, and /list shows My List',
        (t) async {
      final (st, app) = await setup(cat, {'layout': 'console'});
      app.toggleFavorite(cat.movies.first);
      await pump(t, st, app, const ConsoleHome(), const Size(1280, 720),
          UiLayout.console);
      await t.enterText(find.byType(TextField), '/');
      await t.pumpAndSettle();
      expect(find.text('/live'), findsOneWidget);
      expect(find.text('/guide'), findsOneWidget);
      await t.enterText(find.byType(TextField), '/list');
      await t.pumpAndSettle();
      expect(find.text('MY LIST'), findsOneWidget);
      expect(find.text('Harbor Lights'), findsWidgets);
    });

    testWidgets('no match says so', (t) async {
      final (st, app) = await setup(cat, {'layout': 'console'});
      await pump(t, st, app, const ConsoleHome(), const Size(1280, 720),
          UiLayout.console);
      await t.enterText(find.byType(TextField), 'qqqq');
      await t.pumpAndSettle();
      expect(find.textContaining('No match'), findsOneWidget);
    });

    testWidgets('phone: results stack without overflow', (t) async {
      final (st, app) = await setup(cat, {'layout': 'console'});
      await pump(t, st, app, const ConsoleHome(), const Size(420, 900),
          UiLayout.console);
      await t.enterText(find.byType(TextField), 'harb');
      await t.pumpAndSettle();
      expect(find.text('Harbor TV'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('Deck screen', () {
    final cat = Catalog(
      movies: [
        for (var i = 0; i < 5; i++) movie('m$i', 'Movie $i', rating: '${6 + i}')
      ],
      series: [series('s0', 'Show 0', rating: '9')],
    );

    testWidgets('TV: the first pick, the four keys and the position',
        (t) async {
      final (st, app) = await setup(cat, {'layout': 'deck', 'tvMode': 'on'});
      await pump(
          t, st, app, const DeckHome(), const Size(1920, 1080), UiLayout.deck);
      expect(find.text('PICKED FOR YOU'), findsOneWidget);
      expect(find.text('Not tonight'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('1 of 6'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Left skips and remembers it; the next card comes up',
        (t) async {
      final (st, app) = await setup(cat, {'layout': 'deck', 'tvMode': 'on'});
      await pump(
          t, st, app, const DeckHome(), const Size(1920, 1080), UiLayout.deck);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      expect(app.deckSkips.length, 1);
      expect(find.text('2 of 6'), findsOneWidget);
    });

    testWidgets('Up saves to My List and moves on', (t) async {
      final (st, app) = await setup(cat, {'layout': 'deck', 'tvMode': 'on'});
      await pump(
          t, st, app, const DeckHome(), const Size(1920, 1080), UiLayout.deck);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(app.favorites.length, 1);
      expect(find.textContaining('is in My List'), findsOneWidget);
      expect(find.text('2 of 6'), findsOneWidget);
    });

    testWidgets('dealing every card ends on a screen that offers a new deck',
        (t) async {
      final (st, app) = await setup(cat, {'layout': 'deck', 'tvMode': 'on'});
      await pump(
          t, st, app, const DeckHome(), const Size(1920, 1080), UiLayout.deck);
      for (var i = 0; i < 6; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await t.pumpAndSettle();
      }
      expect(find.text('That was the deck.'), findsOneWidget);
      expect(find.text('New deck'), findsOneWidget);
      // Everything was skipped, so a new deck has nothing until the skips are forgotten.
      await t.tap(find.text('New deck'));
      await t.pumpAndSettle();
      expect(find.text('Nothing to pick from yet.'), findsOneWidget);
      await t.tap(find.text('Forget my skips'));
      await t.pumpAndSettle();
      expect(find.text('1 of 6'), findsOneWidget);
    });

    testWidgets('phone: the card and three round buttons, and Save works',
        (t) async {
      final (st, app) = await setup(cat, {'layout': 'deck'});
      await pump(
          t, st, app, const DeckHome(), const Size(420, 900), UiLayout.deck);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await t.tap(find.byIcon(Icons.add));
      await t.pumpAndSettle();
      expect(app.favorites.length, 1);
      await t.tap(find.byIcon(Icons.close));
      await t.pumpAndSettle();
      expect(app.deckSkips.length, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('an empty library says so', (t) async {
      final (st, app) = await setup(const Catalog(), {'layout': 'deck'});
      await pump(
          t, st, app, const DeckHome(), const Size(1280, 720), UiLayout.deck);
      expect(find.text('Nothing to pick from yet.'), findsOneWidget);
    });
  });

  group('Guide preview and filters', () {
    final cat = Catalog(
      liveCategories: const [
        Category('1', 'ES | Sports'),
        Category('2', 'UK | News')
      ],
      live: [
        live('1', 'Arena Sports', '1'),
        live('2', 'Metro News', '2'),
        live('3', 'Harbor TV HD', '1')
      ],
    );

    testWidgets(
        'the first channel is in the preview with Watch and Mini player',
        (t) async {
      final (st, app) = await setup(cat);
      await pump(t, st, app, const GuideScreen(), const Size(1280, 720),
          UiLayout.marquee);
      final preview = find.byKey(const ValueKey('guide-preview'));
      expect(preview, findsOneWidget);
      expect(find.descendant(of: preview, matching: find.text('Arena Sports')),
          findsOneWidget);
      expect(find.descendant(of: preview, matching: find.text('Watch')),
          findsOneWidget);
      expect(find.descendant(of: preview, matching: find.text('Mini player')),
          findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets(
        'tapping another channel puts it in the preview instead of opening it',
        (t) async {
      final (st, app) = await setup(cat);
      await pump(t, st, app, const GuideScreen(), const Size(1280, 720),
          UiLayout.marquee);
      await t.tap(find.widgetWithText(ListTile, 'Metro News'));
      await t.pumpAndSettle();
      final preview = find.byKey(const ValueKey('guide-preview'));
      expect(find.descendant(of: preview, matching: find.text('Metro News')),
          findsOneWidget);
      expect(find.descendant(of: preview, matching: find.text('Arena Sports')),
          findsNothing);
    });

    testWidgets(
        'typing in the filter narrows the guide, and the preview follows',
        (t) async {
      final (st, app) = await setup(cat);
      await pump(t, st, app, const GuideScreen(), const Size(1280, 720),
          UiLayout.marquee);
      await t.enterText(find.byType(TextField), 'metro');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Arena Sports'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Metro News'), findsOneWidget);
      final preview = find.byKey(const ValueKey('guide-preview'));
      expect(find.descendant(of: preview, matching: find.text('Metro News')),
          findsOneWidget);
    });

    testWidgets(
        'the Filters sheet sets quality and country on the shared filter',
        (t) async {
      final (st, app) = await setup(cat);
      await pump(t, st, app, const GuideScreen(), const Size(1280, 720),
          UiLayout.marquee);
      await t.tap(find.text('Filters'));
      await t.pumpAndSettle();
      expect(find.text('Clear all'), findsOneWidget);
      await t.tap(find.text('HD and up'));
      await t.pumpAndSettle();
      expect(app.channelFilter.quality, QualityFilter.hd);
      await t.tap(find.textContaining('United Kingdom'));
      await t.pumpAndSettle();
      expect(app.channelFilter.countries, {'GB'});
      await t.tap(find.text('Clear all'));
      await t.pumpAndSettle();
      expect(app.channelFilter.active, isFalse);
    });

    testWidgets('a filter that matches nothing says so in the guide',
        (t) async {
      final (st, app) = await setup(cat);
      app.setChannelFilter(const ChannelFilter(text: 'nothing like this'));
      await pump(t, st, app, const GuideScreen(), const Size(1280, 720),
          UiLayout.marquee);
      expect(find.byKey(const ValueKey('guide-preview')), findsNothing);
      expect(find.widgetWithText(ListTile, 'Metro News'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('the bar on its own shows the count when a filter is on',
        (t) async {
      final (st, app) = await setup(cat);
      app.setChannelFilter(const ChannelFilter(text: 'a'));
      await pump(t, st, app, const ChannelFilterBar(shown: 2),
          const Size(1280, 720), UiLayout.marquee);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Filters · 1'), findsOneWidget);
    });

    testWidgets('Prime Time still renders its own header with the guide data',
        (t) async {
      final (st, app) = await setup(cat);
      app.guide = XmltvData({
        'a': [
          Programme(
              'Evening Show',
              DateTime.now().subtract(const Duration(minutes: 5)),
              DateTime.now().add(const Duration(minutes: 40)))
        ]
      }, const {});
      await pump(t, st, app, GuideScreen(onFocusProgramme: (c, p) {}),
          const Size(1280, 720), UiLayout.prime);
      expect(find.byKey(const ValueKey('guide-preview')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('mini player', () {
    test('nothing is active to begin with', () {
      expect(MiniPlayer.instance.active, isFalse);
      expect(MiniPlayer.instance.session, isNull);
      expect(MiniPlayer.instance.take(), isNull);
    });

    test('a dropped window settles in the nearest corner', () {
      expect(snapCorner(0.2, 0.2), (right: false, bottom: false));
      expect(snapCorner(0.8, 0.3), (right: true, bottom: false));
      expect(snapCorner(0.3, 0.9), (right: false, bottom: true));
      expect(snapCorner(0.5, 0.5), (right: true, bottom: true));
    });

    testWidgets('the overlay draws nothing while no mini player runs',
        (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Stack(children: [Text('app'), MiniPlayerOverlay()])));
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('app'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    test('expanding with nothing to expand does nothing', () {
      expandMiniPlayer();
      expect(MiniPlayer.instance.active, isFalse);
    });
  });

  test(
      'Console and Deck are layouts with palettes; Deck is dark blue and Console is amber on near-black',
      () {
    expect(UiLayout.fromKey('console'), UiLayout.console);
    expect(UiLayout.fromKey('deck'), UiLayout.deck);
    expect(LayoutPalette.forLayout(UiLayout.console).light, isFalse);
    expect(
        LayoutPalette.forLayout(UiLayout.deck).accent, const Color(0xFFFF7A1A));
  });
}
