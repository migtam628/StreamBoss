import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/shell_nav.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/edited_channels_screen.dart';
import 'package:streamboss/screens/my_lists_screen.dart';
import 'package:streamboss/services/anime.dart';
import 'package:streamboss/services/channel_edits.dart';
import 'package:streamboss/services/chapters.dart';
import 'package:streamboss/services/library_view.dart';
import 'package:streamboss/services/skip_memory.dart';
import 'package:streamboss/services/vod_filter.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/airplay_button.dart';
import 'package:streamboss/widgets/channel_sheet.dart';

MediaItem live(String id, String name, {String cat = 'l1'}) =>
    MediaItem(id: id, name: name, kind: MediaKind.live, streamUrl: 'http://x/$id', categoryId: cat);
MediaItem movie(String id, String name, {String cat = 'm1', String? rating}) =>
    MediaItem(id: id, name: name, kind: MediaKind.movie, streamUrl: 'http://x/$id', categoryId: cat, rating: rating);

void main() {
  final chans = [live('1', 'One HD'), live('2', 'Two'), live('3', 'Three'), live('4', 'Four')];
  List<String> names(List<MediaItem> l) => [for (final c in l) c.name];

  group('applyChannelEdits', () {
    test('nothing to do returns the list itself', () {
      expect(identical(applyChannelEdits(chans, ChannelEdits()), chans), isTrue);
    });

    test('hidden channels go, renamed ones are renamed, pinned ones come first in pin order', () {
      final e = ChannelEdits({
        'live:2': const ChannelEdit(name: 'Mine', original: 'Two'),
        'live:3': const ChannelEdit(original: 'Three', hidden: true),
      }, ['live:4', 'live:1']);
      expect(names(applyChannelEdits(chans, e)), ['Four', 'One HD', 'Mine']);
    });

    test('a pin for a channel that is not in the list is ignored', () {
      expect(names(applyChannelEdits(chans, ChannelEdits({}, ['live:99', 'live:3']))), ['Three', 'One HD', 'Two', 'Four']);
    });

    test('an edit with no rename and not hidden is empty', () {
      expect(const ChannelEdit(original: 'x').isEmpty, isTrue);
      expect(const ChannelEdit(original: 'x', hidden: true).isEmpty, isFalse);
    });

    test('buildView applies edits after merging and sorting', () {
      final c = Catalog(live: chans, liveCategories: const [Category('l1', 'All')]);
      final v = buildView(c, hideAdult: false, sortAz: true, channelEdits: ChannelEdits({'live:2': const ChannelEdit(name: 'Zed', original: 'Two')}, ['live:3']));
      expect(names(v.live), ['Three', 'Four', 'One HD', 'Zed']);
    });
  });

  group('AppState', () {
    Future<(SettingsState, AppState)> setup(Catalog c, [Map<String, Object> prefs = const {}]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      app.catalog = c;
      return (st, app);
    }

    final cat = Catalog(liveCategories: const [Category('l1', 'All')], live: chans, movieCategories: const [Category('m1', 'All')], movies: [
      movie('1', 'A (2020)'),
      movie('2', 'B (2019)'),
      movie('3', 'C (2018)'),
      movie('4', 'D (2017)'),
    ]);

    test('rename, hide, pin and undo change what is shown, and are kept', () async {
      final (_, app) = await setup(cat);
      app.renameChannel(chans[1], '  My Two ');
      expect(names(app.shown.live), ['One HD', 'My Two', 'Three', 'Four']);
      app.pinChannel(chans[3]);
      app.pinChannel(chans[2]);
      expect(names(app.shown.live), ['Four', 'Three', 'One HD', 'My Two']);
      app.movePinned('live:3', -1);
      expect(names(app.shown.live).take(2), ['Three', 'Four']);
      app.hideChannel(chans[0]);
      expect(names(app.shown.live), ['Three', 'Four', 'My Two']);
      expect(app.channelEdits.hiddenKeys, {'live:1'});
      // Renaming back to the provider's name takes the rename away.
      app.renameChannel(chans[1], 'Two');
      expect(app.channelEdits.edits.containsKey('live:2'), isFalse);
      app.unhideChannel('live:1');
      app.resetChannel('live:3');
      expect(names(app.shown.live), ['Four', 'One HD', 'Two', 'Three']);
      app.resetAllChannelEdits();
      expect(app.channelEdits.isEmpty, isTrue);
      expect(names(app.shown.live), ['One HD', 'Two', 'Three', 'Four']);
    });

    test('edits survive a restart and belong to the profile', () async {
      final (st, app) = await setup(cat);
      app.renameChannel(chans[2], 'Third');
      app.hideChannel(chans[3]);
      app.pinChannel(chans[1]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('channelEdits'), contains('Third'));
      final again = AppState()..bindSettings(st);
      await again.init();
      again.catalog = cat;
      expect(names(again.shown.live), ['Two', 'One HD', 'Third']);
    });

    test('a renamed channel still finds its guide by the provider name', () async {
      final (_, app) = await setup(cat);
      app.renameChannel(chans[0], 'Renamed');
      expect(app.channelEdits.edits['live:1']!.original, 'One HD');
    });

    test('My list keeps the order it was given and can be moved', () async {
      final (_, app) = await setup(cat);
      final m = cat.movies;
      for (final i in [m[2], m[0], m[3], m[1]]) {
        app.toggleFavorite(i);
      }
      expect(names(app.favoriteItems), ['C (2018)', 'A (2020)', 'D (2017)', 'B (2019)']);
      app.moveFavorite(m[1].key, toTop: true);
      expect(names(app.favoriteItems).first, 'B (2019)');
      app.moveFavorite(m[1].key, by: 2);
      expect(names(app.favoriteItems), ['C (2018)', 'A (2020)', 'B (2019)', 'D (2017)']);
      app.moveFavorite(m[2].key, by: -3); // already first: nothing moves
      expect(names(app.favoriteItems).first, 'C (2018)');
    });

    test('moving steps over items that are not in the library', () async {
      final (_, app) = await setup(cat);
      final m = cat.movies;
      app.toggleFavorite(m[0]);
      app.favorites.add('movie:gone');
      app.toggleFavorite(m[1]);
      expect(app.favorites.toList(), ['movie:1', 'movie:gone', 'movie:2']);
      app.moveFavorite(m[1].key, by: -1);
      expect(names(app.favoriteItems), ['B (2019)', 'A (2020)'], reason: 'one visible place, not one hidden one');
    });

    test('collections move the same way, and backups carry lists and edits', () async {
      final (_, app) = await setup(cat);
      app.createCollection('Friday');
      for (final i in cat.movies.take(3)) {
        app.toggleInCollection('Friday', i);
      }
      app.moveInCollection('Friday', cat.movies[2].key, toTop: true);
      expect([for (final i in app.collectionItems('Friday')) i.name], ['C (2018)', 'A (2020)', 'B (2019)']);
      app.pinChannel(chans[1]);
      final dump = app.exportData();
      expect(dump['collections'], isNotNull);
      final (_, other) = await setup(cat);
      other.importData(dump);
      expect(other.collections['Friday'], app.collections['Friday']);
      expect(other.channelEdits.pins, ['live:2']);
    });

    test('Anime page: Auto shows it when the library has anime, On and Off decide', () async {
      final plain = cat;
      const withAnime = Catalog(
        seriesCategories: [Category('s1', 'Anime Series')],
        series: [MediaItem(id: '1', name: 'Sky Pirates', kind: MediaKind.series, categoryId: 's1')],
      );
      final (st, app) = await setup(plain);
      expect(app.animeVisible, isFalse);
      st.set('animePage', 'on');
      expect(app.animeVisible, isTrue);
      st.set('animePage', 'auto');
      app.catalog = withAnime;
      expect(app.animeCount, 1);
      expect(app.animeVisible, isTrue);
      st.set('animePage', 'off');
      expect(app.animeVisible, isFalse);
    });

    test('anime is found once per library, not on every ask', () async {
      final (_, app) = await setup(Catalog(
        movieCategories: const [Category('m1', 'Anime Movies')],
        movies: [movie('1', 'Spirit Valley', cat: 'm1')],
      ));
      expect(identical(app.animeFor(MediaKind.movie), app.animeFor(MediaKind.movie)), isTrue);
    });

    test('filtering is kept while the same list and filter are asked about again', () async {
      final (_, app) = await setup(cat);
      app.setVodFilter('movie', const VodFilter(text: 'a'));
      final first = app.filterVod('movie', cat.movies);
      expect(identical(first, app.filterVod('movie', cat.movies)), isTrue);
      app.setVodFilter('movie', const VodFilter(text: 'b'));
      expect(names(app.filterVod('movie', cat.movies)), ['B (2019)']);
      // Filters that depend on favorites are never kept.
      app.setVodFilter('movie', const VodFilter(favoritesOnly: true));
      expect(app.filterVod('movie', cat.movies), isEmpty);
      app.toggleFavorite(cat.movies[0]);
      expect(names(app.filterVod('movie', cat.movies)), ['A (2020)']);
    });
  });

  group('navigation hides Anime when asked', () {
    test('top tabs and phone tabs drop destination 7', () {
      for (final l in UiLayout.values) {
        expect(topTabs(l, anime: false), isNot(contains(7)), reason: l.name);
        final t = phoneTabs(l, anime: false);
        expect(t.bar, isNot(contains(7)), reason: l.name);
        expect(t.more, isNot(contains(7)), reason: l.name);
      }
      expect(topTabs(UiLayout.marquee), contains(7));
      expect(phoneTabs(UiLayout.marquee).more, contains(7));
    });
  });

  group('skip memory', () {
    const total = Duration(minutes: 45);
    test('a skip of an opening is learned, anything else is not', () {
      expect(learnIntro(const Duration(seconds: 12), const Duration(seconds: 102), total), const IntroWindow(Duration(seconds: 12), Duration(seconds: 102)));
      expect(learnIntro(const Duration(minutes: 20), const Duration(minutes: 21, seconds: 30), total), isNull, reason: 'too late in the episode');
      expect(learnIntro(const Duration(seconds: 12), const Duration(seconds: 32), total), isNull, reason: 'a small jump is just seeking');
      expect(learnIntro(const Duration(seconds: 12), const Duration(minutes: 8), total), isNull, reason: 'too long to be an opening');
      expect(learnIntro(const Duration(seconds: 12), const Duration(seconds: 102), const Duration(minutes: 5)), isNull, reason: 'not an episode');
    });

    test('the hint shows from just before where the skip began until just before it ends', () {
      const w = IntroWindow(Duration(seconds: 40), Duration(seconds: 130));
      expect(introHintFromMemory(w, const Duration(seconds: 20), total), isNull);
      final h = introHintFromMemory(w, const Duration(seconds: 31), total)!;
      expect(h.kind, SkipKind.intro);
      expect(h.to, const Duration(seconds: 130));
      expect(introHintFromMemory(w, const Duration(seconds: 128), total), isNull);
    });

    test('an opening skipped from the very start is offered from the first frame', () {
      const w = IntroWindow(Duration(seconds: 5), Duration(seconds: 95));
      expect(introHintFromMemory(w, Duration.zero, total), isNotNull);
    });

    test('it survives being saved and read back', () {
      const w = IntroWindow(Duration(seconds: 7), Duration(seconds: 99));
      expect(IntroWindow.fromJson(w.toJson()), w);
    });

    test('the app remembers a series skip per profile', () async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      app.rememberIntro('series:1', const IntroWindow(Duration(seconds: 10), Duration(seconds: 100)));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('introSkips'), contains('series:1'));
    });
  });

  group('screens', () {
    Future<(SettingsState, AppState)> setup(Catalog c, [Map<String, Object> prefs = const {}]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      await app.init();
      app.catalog = c;
      return (st, app);
    }

    Future<void> pump(WidgetTester t, SettingsState st, AppState app, Widget home, {Size size = const Size(700, 1000)}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(theme: Boss.theme(), home: home),
      ));
      await t.pumpAndSettle();
    }

    final cat = Catalog(liveCategories: const [Category('l1', 'All')], live: chans, movieCategories: const [Category('m1', 'All')], movies: [
      movie('1', 'Alpha'),
      movie('2', 'Bravo'),
      movie('3', 'Charlie'),
    ]);

    testWidgets('the channel sheet renames, pins and hides', (t) async {
      final (st, app) = await setup(cat);
      await pump(t, st, app, Scaffold(body: Builder(builder: (c) => Center(child: TextButton(onPressed: () => showChannelSheet(c, chans[1]), child: const Text('open'))))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Pin to the top'), findsOneWidget);
      await t.tap(find.text('Pin to the top'));
      await t.pumpAndSettle();
      expect(app.isPinned('live:2'), isTrue);
      expect(find.text('Unpin'), findsOneWidget);
      await t.tap(find.text('Rename'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Two Prime');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(app.channelEdits.edits['live:2']!.name, 'Two Prime');
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Provider name: Two'), findsOneWidget);
      await t.tap(find.text('Hide this channel'));
      await t.pumpAndSettle();
      expect(app.channelEdits.hiddenKeys, {'live:2'});
      expect(app.channelEdits.pins, isEmpty, reason: 'hiding takes the pin away');
    });

    testWidgets('a long press on a movie opens the quick look; on a channel it opens the sheet', (t) async {
      final (st, app) = await setup(cat);
      late BuildContext ctx;
      await pump(t, st, app, Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      itemMenu(ctx, cat.movies[0]);
      await t.pumpAndSettle();
      expect(find.text('Full details'), findsOneWidget);
      await t.tap(find.text('My list'));
      await t.pumpAndSettle();
      expect(app.isFavorite(cat.movies[0]), isTrue);
      Navigator.of(ctx).pop();
      await t.pumpAndSettle();
      itemMenu(ctx, chans[0]);
      await t.pumpAndSettle();
      expect(find.text('Hide this channel'), findsOneWidget);
    });

    testWidgets('Edited channels lists what changed and undoes it', (t) async {
      final (st, app) = await setup(cat);
      app.renameChannel(chans[0], 'Uno');
      app.hideChannel(chans[1]);
      app.pinChannel(chans[2]);
      await pump(t, st, app, const EditedChannelsScreen());
      expect(find.text('Uno'), findsOneWidget);
      expect(find.text('Was "One HD"'), findsOneWidget);
      expect(find.textContaining('Hidden'), findsOneWidget);
      expect(find.textContaining('Pinned (1)'), findsOneWidget);
      await t.tap(find.text('Undo').first);
      await t.pumpAndSettle();
      expect(app.channelEdits.pins, isEmpty, reason: 'the pinned channel is listed first, and Undo takes the pin away');
      await t.tap(find.text('Undo all'));
      await t.pumpAndSettle();
      await t.tap(find.text('Undo all').last);
      await t.pumpAndSettle();
      expect(app.channelEdits.isEmpty, isTrue);
      expect(find.textContaining('No channel has been changed'), findsOneWidget);
    });

    testWidgets('My lists: chips for My list and collections, and moving a title', (t) async {
      final (st, app) = await setup(cat);
      for (final m in cat.movies) {
        app.toggleFavorite(m);
      }
      app.createCollection('Friday');
      app.toggleInCollection('Friday', cat.movies[1]);
      await pump(t, st, app, const MyListsScreen());
      expect(find.text('My list  3'), findsOneWidget);
      expect(find.text('Friday  1'), findsOneWidget);
      await t.longPress(find.text('Charlie'));
      await t.pumpAndSettle();
      await t.tap(find.text('Move to the top'));
      await t.pumpAndSettle();
      expect(app.favoriteItems.first.name, 'Charlie');
      // A to Z leaves the order alone and offers no moving.
      await t.tap(find.text('A to Z'));
      await t.pumpAndSettle();
      await t.longPress(find.text('Bravo'));
      await t.pumpAndSettle();
      expect(find.text('Move to the top'), findsNothing);
      expect(find.text('Remove from My list'), findsOneWidget);
      await t.tap(find.text('Remove from My list'));
      await t.pumpAndSettle();
      expect(app.isFavorite(cat.movies[1]), isFalse);
      await t.tap(find.text('Friday  1'));
      await t.pumpAndSettle();
      expect(find.text('Bravo'), findsWidgets);
    });

    testWidgets('the AirPlay button draws nothing off iPhone', (t) async {
      final (st, app) = await setup(cat);
      await pump(t, st, app, const Scaffold(body: AirPlayButton()));
      expect(airPlaySupported, isFalse);
      expect(find.byType(SizedBox), findsWidgets);
      expect(t.takeException(), isNull);
    });
  });

  group('big libraries', () {
    test('a 100,000 title library filters and sorts in well under a few seconds', () {
      final items = [
        for (var i = 0; i < 100000; i++)
          MediaItem(id: '$i', name: 'Movie number $i (${1980 + i % 45}) Édition', kind: MediaKind.movie, streamUrl: 'u', categoryId: '${i % 200}', rating: '${i % 10}.${i % 7}')
      ];
      String cat(MediaItem i) => 'Category ${i.categoryId}';
      final sw = Stopwatch()..start();
      // The first pass reads every title once; the passes after it reuse that.
      applyVodFilter(items, const VodFilter(text: 'number 99'), categoryName: cat, isFavorite: (_) => false, started: (_) => false);
      final warm = Stopwatch()..start();
      applyVodFilter(items, const VodFilter(text: 'number 98', era: Era.y2010), categoryName: cat, isFavorite: (_) => false, started: (_) => false);
      final sorted = applyVodFilter(items, const VodFilter(sort: VodSort.newest), categoryName: cat, isFavorite: (_) => false, started: (_) => false);
      warm.stop();
      sw.stop();
      expect(sorted.length, items.length);
      expect(yearOf(sorted.first)! >= yearOf(sorted.last)!, isTrue);
      expect(warm.elapsedMilliseconds, lessThan(3000), reason: 'a filter and a sort after the first pass');
    });
  });

  test('anime categories and the AnimeFound shape', () {
    expect(isAnimeCategory('Anime Movies'), isTrue);
    final AnimeFound f = animeOf(const Catalog(), MediaKind.live);
    expect(f.items, isEmpty);
  });
}
