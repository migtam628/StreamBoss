import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/screens/browse_screen.dart';
import 'package:streamboss/screens/shell.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/layouts/common.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/channel_filter.dart';
import 'package:streamboss/services/languages.dart';
import 'package:streamboss/services/vod_filter.dart';
import 'package:streamboss/widgets/tv.dart';
import 'package:streamboss/widgets/tv_text_field.dart';

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
      expect({for (final e in l) e.$1.code}, {'en', 'es', 'it'});
      expect(l.first.$2, 2);
    });
  });

  group('TvTextField', () {
    Widget host(bool tv, TextEditingController c, {List<String>? sent}) => MaterialApp(
          home: TvScope(
            tv: tv,
            child: Scaffold(
              body: TvTextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Filter'),
                onSubmitted: (v) => sent?.add(v),
              ),
            ),
          ),
        );

    testWidgets('off TV it is a normal text field', (t) async {
      await t.pumpWidget(host(false, TextEditingController()));
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('on TV, highlighting it does not open the input', (t) async {
      final c = TextEditingController(text: 'abc');
      await t.pumpWidget(host(true, c));
      await t.pump();
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('abc'), findsOneWidget);
    });

    testWidgets('OK opens the input, submitting closes it and keeps focus on the box', (t) async {
      final c = TextEditingController();
      final sent = <String>[];
      await t.pumpWidget(host(true, c, sent: sent));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      await t.pump();
      expect(find.byType(EditableText), findsOneWidget);
      await t.enterText(find.byType(EditableText), 'news');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.pump();
      expect(sent, ['news']);
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('news'), findsOneWidget);
    });

    testWidgets('tapping it also opens the input', (t) async {
      await t.pumpWidget(host(true, TextEditingController()));
      await t.tap(find.byType(InputDecorator));
      await t.pump();
      expect(find.byType(EditableText), findsOneWidget);
    });
  });

  group('open where I left off', () {
    Future<(SettingsState, AppState)> boot(WidgetTester t, Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final st = SettingsState();
      await st.init();
      final app = AppState()..bindSettings(st);
      app.catalog = Catalog(
        movies: [item('m', 'Movie', '1', kind: MediaKind.movie)],
        movieCategories: const [Category('1', 'Movies')],
        series: [item('s', 'Show', '2', kind: MediaKind.series)],
        seriesCategories: const [Category('2', 'Shows')],
      );
      t.view.physicalSize = const Size(1000, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(theme: Boss.theme(tv: false, layout: st.layout), home: const Shell()),
      ));
      await t.pump();
      return (st, app);
    }

    bool onSeries() => find.byWidgetPredicate((w) => w is BrowseScreen && w.kind == MediaKind.series).evaluate().isNotEmpty;

    testWidgets('reopens the last screen', (t) async {
      await boot(t, {'startTab': -1, 'lastTab': 4});
      expect(onSeries(), isTrue);
    });

    testWidgets('a fixed start screen ignores the last one', (t) async {
      await boot(t, {'startTab': 0, 'lastTab': 4});
      expect(onSeries(), isFalse);
    });

    test('defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final st = SettingsState();
      await st.init();
      expect(st.startOnBoot, isFalse);
      expect(st.lastLiveOpen, isFalse);
      expect(st.lastLive, '');
      st.set('startTab', -1);
      expect(st.startTab, -1);
    });
  });

  group('remote Menu key', () {
    testWidgets('Menu on a focused tile does what a long press does', (t) async {
      var tapped = 0, held = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FocusSurface(
            autofocus: true,
            onTap: () => tapped++,
            onLongPress: () => held++,
            builder: (_, __) => const SizedBox(width: 100, height: 50),
          ),
        ),
      ));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await t.sendKeyEvent(LogicalKeyboardKey.info);
      expect(held, 2);
      expect(tapped, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      expect(tapped, 1);
    });
  });
}
