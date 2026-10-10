import 'dart:async';
import 'package:cast/cast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/layouts/layout_picker.dart';
import 'package:streamboss/layouts/lounge_view.dart';
import 'package:streamboss/layouts/ui_layout.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/cast_service.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';
import 'package:streamboss/widgets/cast_sheet.dart';
import 'package:streamboss/widgets/tv.dart';

MediaItem live(String id, String name, String cat) => MediaItem(
    id: id,
    name: name,
    kind: MediaKind.live,
    streamUrl: 'http://x/$id',
    categoryId: cat);

void main() {
  Future<(SettingsState, AppState)> setup(Catalog catalog,
      [Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final st = SettingsState();
    await st.init();
    final app = AppState()..bindSettings(st);
    app.catalog = catalog;
    return (st, app);
  }

  Future<void> pump(
      WidgetTester t, SettingsState st, AppState app, Size size) async {
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
        theme: Boss.theme(tv: tv, layout: UiLayout.lounge),
        builder: (context, child) => TvCanvas(
            enabled: tv,
            width: st.tvWidth,
            child: TvScope(tv: tv, child: child!)),
        home: const Scaffold(body: LoungeHome()),
      ),
    ));
    await t.pumpAndSettle();
  }

  final cat = Catalog(
    liveCategories: const [Category('1', 'Sports'), Category('2', 'News')],
    live: [
      live('1', 'La Uno', '2'),
      live('2', 'Arena Sports', '1'),
      live('3', 'World News', '2'),
    ],
  );

  group('Lounge', () {
    testWidgets(
        'TV: the strip lists the channels with numbers; the first is selected',
        (t) async {
      final (st, app) = await setup(cat, {'layout': 'lounge', 'tvMode': 'on'});
      await pump(t, st, app, const Size(1920, 1080));
      expect(find.text('La Uno'), findsWidgets);
      expect(find.text('Arena Sports'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('a category chip narrows the strip', (t) async {
      final (st, app) = await setup(cat, {'layout': 'lounge', 'tvMode': 'on'});
      await pump(t, st, app, const Size(1920, 1080));
      await t.tap(find.text('Sports').first);
      await t.pumpAndSettle();
      expect(find.text('Arena Sports'), findsWidgets);
      expect(find.text('World News'), findsNothing);
    });

    testWidgets('phone: the first tap selects a channel, no overflow',
        (t) async {
      final (st, app) = await setup(cat, {'layout': 'lounge'});
      await pump(t, st, app, const Size(420, 900));
      await t.tap(find.text('Arena Sports').last);
      await t.pumpAndSettle();
      expect(find.text('Arena Sports'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('no live channels says so', (t) async {
      final (st, app) = await setup(const Catalog(), {'layout': 'lounge'});
      await pump(t, st, app, const Size(420, 900));
      expect(find.textContaining('No live channels'), findsOneWidget);
    });
  });

  test('Lounge is in the roster with its own palette', () {
    expect(UiLayout.fromKey('lounge'), UiLayout.lounge);
    expect(LayoutPalette.forLayout(UiLayout.lounge).accent,
        const Color(0xFF2DD4BF));
  });

  group('Layout picker', () {
    test('every layout belongs to a group, and every group has layouts', () {
      for (final l in UiLayout.values) {
        expect(LayoutGroup.values, contains(l.group));
      }
      for (final g in LayoutGroup.values) {
        expect(UiLayout.values.where((l) => l.group == g), isNotEmpty, reason: g.label);
      }
    });

    testWidgets('groups are listed, and a changed layout can be undone', (t) async {
      final (st, app) = await setup(cat, {'layout': 'marquee'});
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SettingsState>.value(value: st),
        ],
        child: MaterialApp(
          theme: Boss.theme(tv: false, layout: UiLayout.marquee),
          home: const Scaffold(body: SingleChildScrollView(child: LayoutPicker())),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Live TV'), findsOneWidget);
      expect(find.text('Decide for me'), findsOneWidget);
      expect(find.textContaining('Go back to'), findsNothing);
      await t.ensureVisible(find.text('Lounge'));
      await t.pumpAndSettle();
      await t.tap(find.text('Lounge'));
      await t.pumpAndSettle();
      expect(st.layout, UiLayout.lounge);
      expect(find.text('Not for you? Go back to Marquee'), findsOneWidget);
      await t.ensureVisible(find.text('Not for you? Go back to Marquee'));
      await t.pumpAndSettle();
      await t.tap(find.text('Not for you? Go back to Marquee'));
      await t.pumpAndSettle();
      expect(st.layout, UiLayout.marquee);
      expect(find.textContaining('Go back to'), findsNothing);
    });
  });

  group('Cast', () {
    test('content type follows the address, ignoring the query', () {
      expect(
          castContentType('http://h/live/u/p/1.m3u8'), 'application/x-mpegURL');
      expect(castContentType('http://h/movie/u/p/2.MKV?token=a.mp4'),
          'video/x-matroska');
      expect(castContentType('http://h/live/u/p/1.ts'), 'video/mp2t');
      expect(castContentType('http://h/movie/u/p/2.mp4'), 'video/mp4');
      expect(castContentType('http://h/stream'), 'video/mp4');
    });

    test('the load message says live or buffered and carries the title', () {
      final m = castLoadMessage(
          requestId: 7,
          url: 'http://h/a.m3u8',
          title: 'La Uno',
          live: true,
          poster: 'http://p/x.png');
      expect(m['type'], 'LOAD');
      expect(m['requestId'], 7);
      final media = m['media'] as Map;
      expect(media['streamType'], 'LIVE');
      expect(media['contentId'], 'http://h/a.m3u8');
      expect((media['metadata'] as Map)['title'], 'La Uno');
      expect(((media['metadata'] as Map)['images'] as List).length, 1);
      final vod = castLoadMessage(
          requestId: 8, url: 'http://h/a.mp4', title: 'X', live: false);
      expect((vod['media'] as Map)['streamType'], 'BUFFERED');
      expect(((vod['media'] as Map)['metadata'] as Map).containsKey('images'),
          isFalse);
    });

    const tvA = CastDevice(
        serviceName: 'a', name: 'Living room', host: '10.0.0.5', port: 8009);
    const tvB = CastDevice(
        serviceName: 'b', name: 'Bedroom', host: '10.0.0.6', port: 8009);

    test('scan lists the devices found, and a failed search says so', () async {
      final ok = CastController(search: () async => [tvA, tvB]);
      await ok.scan();
      expect(ok.devices.map((d) => d.name), ['Living room', 'Bedroom']);
      expect(ok.scanning, isFalse);
      final bad =
          CastController(search: () async => throw Exception('no network'));
      await bad.scan();
      expect(bad.error, contains('Could not search'));
    });

    test(
        'play connects once, loads the stream, and pause uses the media session',
        () async {
      final links = <_FakeLink>[];
      final c = CastController(
          search: () async => [tvA],
          link: (d) => _FakeLink(d)..also(links.add));
      expect(
          await c.play(tvA,
              url: 'http://h/a.m3u8', title: 'La Uno', live: true),
          isTrue);
      expect(c.casting, isTrue);
      expect(c.device, tvA);
      final l = links.single;
      expect(l.launched, 1);
      expect(l.sent.last.$2['type'], 'LOAD');
      // The receiver reports its media session; pause and resume refer to it.
      l.feed({
        'type': 'MEDIA_STATUS',
        'status': [
          {'mediaSessionId': 5, 'playerState': 'PLAYING'}
        ]
      });
      await Future<void>.delayed(Duration.zero);
      c.togglePause();
      expect(l.sent.last.$2, containsPair('type', 'PAUSE'));
      expect(l.sent.last.$2, containsPair('mediaSessionId', 5));
      l.feed({
        'type': 'MEDIA_STATUS',
        'status': [
          {'mediaSessionId': 5, 'playerState': 'PAUSED'}
        ]
      });
      await Future<void>.delayed(Duration.zero);
      expect(c.paused, isTrue);
      c.togglePause();
      expect(l.sent.last.$2, containsPair('type', 'PLAY'));
      // A second title on the same device reuses the connection.
      await c.play(tvA, url: 'http://h/b.m3u8', title: 'Canal Sur', live: true);
      expect(links.length, 1);
      expect(l.launched, 1);
      await c.stop();
      expect(c.casting, isFalse);
      expect(l.closed, isTrue);
    });

    test('a device that will not connect leaves an error and no cast',
        () async {
      final c = CastController(
          search: () async => [tvA],
          link: (d) => _FakeLink(d, failLaunch: true));
      expect(await c.play(tvA, url: 'http://h/a.m3u8', title: 'T', live: true),
          isFalse);
      expect(c.casting, isFalse);
      expect(c.error, contains('Living room'));
    });

    test('the receiver reporting an error is shown', () async {
      late _FakeLink l;
      final c = CastController(
          search: () async => [tvA], link: (d) => l = _FakeLink(d));
      await c.play(tvA, url: 'http://h/a.m3u8', title: 'T', live: true);
      l.feed({
        'type': 'MEDIA_STATUS',
        'status': [
          {'mediaSessionId': 1, 'playerState': 'IDLE', 'idleReason': 'ERROR'}
        ]
      });
      await Future<void>.delayed(Duration.zero);
      expect(c.error, contains('could not play'));
    });

    testWidgets(
        'the sheet lists devices, casts to the one tapped and calls back',
        (t) async {
      final c = CastController(
          search: () async => [tvA, tvB], link: (d) => _FakeLink(d));
      var started = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CastSheet(
                controller: c,
                url: 'http://h/a.m3u8',
                title: 'La Uno',
                live: true,
                onStarted: () => started++),
          ),
        ),
      ));
      await c.scan();
      await t.pumpAndSettle();
      expect(find.text('EXPERIMENTAL'), findsOneWidget);
      expect(find.text('Living room'), findsOneWidget);
      expect(find.text('Bedroom'), findsOneWidget);
      await t.tap(find.text('Bedroom'));
      await t.pumpAndSettle();
      expect(started, 1);
      expect(find.text('Casting to Bedroom'), findsOneWidget);
      await t.tap(find.byTooltip('Stop casting'));
      await t.pumpAndSettle();
      expect(find.text('Casting to Bedroom'), findsNothing);
    });

    testWidgets('the sheet says when nothing is found', (t) async {
      final c = CastController(search: () async => <CastDevice>[]);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CastSheet(
                      controller: c, url: 'u', title: 'T', live: true)))));
      await c.scan();
      await t.pumpAndSettle();
      expect(find.text('No devices found'), findsOneWidget);
    });
  });
}

class _FakeLink implements CastLink {
  final CastDevice device;
  final bool failLaunch;
  int launched = 0;
  bool closed = false;
  final sent = <(String, Map<String, dynamic>)>[];
  final _msgs = StreamController<Map<String, dynamic>>.broadcast();
  _FakeLink(this.device, {this.failLaunch = false});
  void also(void Function(_FakeLink) f) => f(this);
  void feed(Map<String, dynamic> m) => _msgs.add(m);
  @override
  Future<void> launch() async {
    launched++;
    if (failLaunch) throw Exception('refused');
  }

  @override
  void send(String namespace, Map<String, dynamic> payload) =>
      sent.add((namespace, payload));
  @override
  Stream<Map<String, dynamic>> get messages => _msgs.stream;
  @override
  Future<void> close() async => closed = true;
}
