import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/globe_view.dart';
import 'package:streamboss/layouts/playground_view.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/countries.dart';
import 'package:streamboss/services/playground.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/tv.dart';

MediaItem live(String id, String name, String cat) => MediaItem(
    id: id,
    name: name,
    kind: MediaKind.live,
    streamUrl: 'http://x/$id',
    categoryId: cat);
MediaItem movie(String id, String name, String cat) => MediaItem(
    id: id,
    name: name,
    kind: MediaKind.movie,
    streamUrl: 'http://x/$id',
    categoryId: cat);
MediaItem series(String id, String name, String cat) =>
    MediaItem(id: id, name: name, kind: MediaKind.series, categoryId: cat);

void main() {
  group('countryOf', () {
    test('reads codes in front of a name', () {
      expect(countryOf('ES | Sports')?.code, 'ES');
      expect(countryOf('[UK] News')?.code, 'GB');
      expect(countryOf('(US) Movies')?.code, 'US');
      expect(countryOf('USA: Kids')?.code, 'US');
      expect(countryOf('IN | Hindi')?.code, 'IN');
      expect(countryOf('DE - Nachrichten')?.code, 'DE');
    });

    test('reads a country name at the start', () {
      expect(countryOf('Spain - Movies')?.code, 'ES');
      expect(countryOf('United States | News')?.code, 'US');
      expect(countryOf('Turkey News HD')?.code, 'TR');
    });

    test('leaves ordinary names alone', () {
      for (final n in [
        'Sports',
        'Movies HD',
        'It Takes Two',
        'No Limit Sports',
        'Kids',
        ''
      ]) {
        expect(countryOf(n), isNull, reason: n);
      }
    });

    test('categoryLabel drops the country', () {
      expect(categoryLabel('ES | Sports'), 'Sports');
      expect(categoryLabel('Spain - News'), 'News');
      expect(categoryLabel('[UK] Movies'), 'Movies');
      expect(categoryLabel('Sports'), 'Sports');
      expect(categoryLabel('ES |'), 'General');
    });

    test(
        'every country has a code, a spot on the map and its own name as an alias',
        () {
      final seen = <String>{};
      for (final c in countries) {
        expect(seen.add(c.code), isTrue, reason: 'duplicate ${c.code}');
        expect(c.lon, inInclusiveRange(-180, 180));
        expect(c.lat, inInclusiveRange(-90, 90));
        expect(c.aliases, contains(c.code.toLowerCase()));
      }
    });
  });

  group('groupByCountry', () {
    final c = Catalog(
      liveCategories: const [
        Category('1', 'ES | Sports'),
        Category('2', 'ES | News'),
        Category('3', 'UK | News'),
        Category('4', 'Misc')
      ],
      live: [
        live('1', 'La Uno', '1'),
        live('2', 'Canal Sur', '2'),
        live('3', 'Sports Two', '1'),
        live('4', 'BBC One', '3'),
        live('5', 'US: Weather Now',
            '4'), // the category says nothing, the channel does
        live('6', 'Random Channel', '4'),
      ],
    );

    test(
        'biggest first, by category or by channel name, and channels with no country are left out',
        () {
      final g = groupByCountry(c);
      expect(g.map((x) => x.country.code), ['ES', 'GB', 'US']);
      expect(g.first.channels.map((e) => e.name),
          ['La Uno', 'Canal Sur', 'Sports Two']);
      expect(g.expand((x) => x.channels).any((e) => e.name == 'Random Channel'),
          isFalse);
    });
  });

  group('Playground logic', () {
    final cat = Catalog(
      liveCategories: const [
        Category('l1', 'Kids Cartoons'),
        Category('l2', 'News')
      ],
      movieCategories: const [
        Category('m1', 'Kids Movies'),
        Category('m2', 'Action'),
        Category('m3', 'Family Music')
      ],
      seriesCategories: const [
        Category('s1', 'Kids Learning'),
        Category('s2', 'Adult XXX')
      ],
      live: [live('1', 'Toon TV', 'l1'), live('2', 'Metro News', 'l2')],
      movies: [
        movie('3', 'Captain Pancake', 'm1'),
        movie('4', 'Salt Road', 'm2'),
        movie('5', 'Sing Along', 'm3')
      ],
      series: [
        series('6', 'Number Friends', 's1'),
        series('7', 'Bad Show', 's2')
      ],
    );

    test('only children\'s categories are ever used', () {
      final names = kidsItems(cat).map((e) => e.name).toSet();
      expect(names,
          {'Toon TV', 'Captain Pancake', 'Sing Along', 'Number Friends'});
    });

    test('each tile holds its own kind of title', () {
      Set<String> n(PlayTile t, [Set<String> fav = const {}]) =>
          playgroundItems(t, cat, fav).map((e) => e.name).toSet();
      expect(n(PlayTile.movies), {'Captain Pancake', 'Sing Along'});
      expect(n(PlayTile.cartoons), {'Toon TV', 'Number Friends'});
      expect(n(PlayTile.songs), {'Sing Along'});
      expect(n(PlayTile.learn), {'Number Friends'});
      expect(n(PlayTile.sleepy), isEmpty);
    });

    test('favorites are only kid-safe ones', () {
      final keys = {'movie:3', 'movie:4'};
      final fav = playgroundItems(PlayTile.favorites, cat, {
        for (final i in cat.all)
          if (keys.contains(i.key)) i.key
      });
      expect(fav.map((e) => e.name), ['Captain Pancake']);
    });

    test('bedtime: off, before, at and after, and the small hours', () {
      DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 9, h, m);
      expect(pastBedtime(at(23), 'off'), isFalse);
      expect(pastBedtime(at(19, 59), '20:00'), isFalse);
      expect(pastBedtime(at(20), '20:00'), isTrue);
      expect(pastBedtime(at(2), '20:00'), isTrue, reason: 'still night');
      expect(pastBedtime(at(5), '20:00'), isFalse, reason: 'morning');
      expect(untilBedtime(at(19, 20), '20:00'), const Duration(minutes: 40));
      expect(untilBedtime(at(21), '20:00'), isNull);
      expect(untilBedtime(at(12), 'off'), isNull);
      expect(untilBedtime(at(12), 'garbage'), isNull);
      expect(bedtimeLabel(const Duration(minutes: 40)), 'Bedtime in 40 min');
      expect(
          bedtimeLabel(const Duration(minutes: 135)), 'Bedtime in 2 h 15 min');
    });
  });

  Future<(SettingsState, AppState)> setup(
      Catalog catalog, Map<String, Object> prefs) async {
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

  group('Globe screen', () {
    final world = Catalog(
      liveCategories: const [
        Category('1', 'ES | Sports'),
        Category('2', 'ES | News'),
        Category('3', 'UK | News'),
        Category('4', 'FR | General')
      ],
      live: [
        live('1', 'La Uno', '1'),
        live('2', 'Canal Sur', '2'),
        live('3', 'Sports Two', '1'),
        live('4', 'BBC One', '3'),
        live('5', 'France Info', '4'),
      ],
    );

    testWidgets('TV: opens on the biggest country with its channels and chips',
        (t) async {
      final (st, app) = await setup(world, {'layout': 'globe', 'tvMode': 'on'});
      await pump(t, st, app, const GlobeHome(), const Size(1920, 1080),
          UiLayout.globe);
      expect(find.text('Spain'), findsWidgets);
      expect(find.text('3 channels'), findsOneWidget);
      expect(find.text('La Uno'), findsOneWidget);
      expect(find.text('BBC One'), findsNothing);
      expect(find.textContaining('Sports'),
          findsWidgets); // a chip named without the country
      final map = find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_MapPainter');
      expect(map, findsOneWidget);
      expect(t.getSize(map).width, greaterThan(300),
          reason: 'the map must not collapse');
      expect(t.getSize(map).height, greaterThan(150));
      expect(t.takeException(), isNull);
    });

    testWidgets('a category chip narrows the list', (t) async {
      final (st, app) = await setup(world, {'layout': 'globe', 'tvMode': 'on'});
      await pump(t, st, app, const GlobeHome(), const Size(1920, 1080),
          UiLayout.globe);
      await t.tap(find.textContaining('News').first);
      await t.pumpAndSettle();
      expect(find.text('Canal Sur'), findsOneWidget);
      expect(find.text('La Uno'), findsNothing);
    });

    testWidgets('arrow keys hop to the next pin and the panel follows',
        (t) async {
      final (st, app) = await setup(world, {'layout': 'globe', 'tvMode': 'on'});
      await pump(t, st, app, const GlobeHome(), const Size(1920, 1080),
          UiLayout.globe);
      expect(find.text('Spain'), findsWidgets);
      // France is the nearest pin to the north of Spain, then the UK above it.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(find.text('Spain'), findsNothing);
      expect(find.text('France'), findsWidgets);
      expect(find.text('France Info'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(find.text('United Kingdom'), findsWidgets);
      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets('Enter moves into the channel list, Left comes back',
        (t) async {
      final (st, app) = await setup(world, {'layout': 'globe', 'tvMode': 'on'});
      await pump(t, st, app, const GlobeHome(), const Size(1920, 1080),
          UiLayout.globe);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      final inList = FocusManager.instance.primaryFocus;
      expect(inList, isNotNull);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(same(inList)));
    });

    testWidgets('channels that name no country show the plain list and say so',
        (t) async {
      final plain = Catalog(
        liveCategories: const [Category('1', 'Sports'), Category('2', 'News')],
        live: [
          live('1', 'Arena Sports 1', '1'),
          live('2', 'Metro News 24', '2')
        ],
      );
      final (st, app) = await setup(plain, {'layout': 'globe', 'tvMode': 'on'});
      await pump(t, st, app, const GlobeHome(), const Size(1920, 1080),
          UiLayout.globe);
      expect(
          find.textContaining('do not name their countries'), findsOneWidget);
      expect(find.text('Arena Sports 1'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('phone: the map, the name and the list stack without overflow',
        (t) async {
      final (st, app) = await setup(world, {'layout': 'globe'});
      await pump(
          t, st, app, const GlobeHome(), const Size(420, 900), UiLayout.globe);
      expect(find.text('Spain'), findsOneWidget);
      expect(find.text('La Uno'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('Playground screen', () {
    final kids = Catalog(
      liveCategories: const [Category('l1', 'Kids Cartoons')],
      movieCategories: const [Category('m1', 'Kids Movies')],
      seriesCategories: const [Category('s1', 'Kids Learning')],
      live: [live('1', 'Toon TV', 'l1')],
      movies: [movie('3', 'Captain Pancake', 'm1')],
      series: [series('6', 'Number Friends', 's1')],
    );

    testWidgets(
        'TV: a greeting, Grown-ups, and a tile for each kind that has titles',
        (t) async {
      final (st, app) =
          await setup(kids, {'layout': 'playground', 'tvMode': 'on'});
      await pump(t, st, app, const PlaygroundHome(), const Size(1920, 1080),
          UiLayout.playground);
      expect(find.text('Hi there!'), findsOneWidget);
      expect(find.text('Grown-ups'), findsOneWidget);
      for (final tile in [PlayTile.cartoons, PlayTile.movies, PlayTile.learn]) {
        expect(find.text(tile.label), findsOneWidget, reason: tile.label);
      }
      expect(find.text('Songs'), findsNothing,
          reason: 'nothing for it, so no tile');
      expect(find.text('Search'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a tile opens a shelf of its titles and Back returns',
        (t) async {
      final (st, app) =
          await setup(kids, {'layout': 'playground', 'tvMode': 'on'});
      await pump(t, st, app, const PlaygroundHome(), const Size(1920, 1080),
          UiLayout.playground);
      await t.tap(find.text('Movies'));
      await t.pumpAndSettle();
      expect(find.text('Captain Pancake'), findsWidgets);
      expect(find.text('Number Friends'), findsNothing);
      await t.tap(find.byIcon(Icons.arrow_back));
      await t.pumpAndSettle();
      expect(find.text('Hi there!'), findsOneWidget);
    });

    testWidgets('past bedtime: all done for today, no tiles', (t) async {
      final (st, app) =
          await setup(kids, {'layout': 'playground', 'tvMode': 'on'});
      st.set('bedtime', '00:00'); // midnight has always passed
      await pump(t, st, app, const PlaygroundHome(), const Size(1920, 1080),
          UiLayout.playground);
      expect(find.text('All done for today'), findsOneWidget);
      expect(find.text('Cartoons'), findsNothing);
      expect(find.text('Grown-ups'), findsOneWidget);
    });

    testWidgets('before bedtime: a pill says how long is left', (t) async {
      final (st, app) =
          await setup(kids, {'layout': 'playground', 'tvMode': 'on'});
      final soon = DateTime.now().add(const Duration(minutes: 50));
      if (soon.day != DateTime.now().day || DateTime.now().hour < 5) {
        return; // too close to midnight to say
      }
      st.set(
          'bedtime', '${soon.hour}:${soon.minute.toString().padLeft(2, '0')}');
      await pump(t, st, app, const PlaygroundHome(), const Size(1920, 1080),
          UiLayout.playground);
      expect(find.textContaining('Bedtime in'), findsOneWidget);
    });

    testWidgets('a source with no children\'s categories says so', (t) async {
      final (st, app) = await setup(
          const Catalog(live: []), {'layout': 'playground', 'tvMode': 'on'});
      await pump(t, st, app, const PlaygroundHome(), const Size(1920, 1080),
          UiLayout.playground);
      expect(find.textContaining('No children'), findsOneWidget);
    });

    testWidgets('phone: tiles in two columns without overflow', (t) async {
      final (st, app) = await setup(kids, {'layout': 'playground'});
      await pump(t, st, app, const PlaygroundHome(), const Size(420, 900),
          UiLayout.playground);
      expect(find.text('Cartoons'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  test('both are layouts with their own palette, and Playground is a light one',
      () {
    expect(UiLayout.fromKey('globe'), UiLayout.globe);
    expect(UiLayout.fromKey('playground'), UiLayout.playground);
    expect(LayoutPalette.forLayout(UiLayout.playground).light, isTrue);
    expect(LayoutPalette.forLayout(UiLayout.globe).light, isFalse);
  });
}
