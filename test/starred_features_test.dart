import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/screens/setup_screen.dart';
import 'package:streamboss/screens/settings_screen.dart';
import 'package:streamboss/services/channel_number.dart';
import 'package:streamboss/services/m3u_parser.dart';
import 'package:streamboss/services/next_episode.dart';
import 'package:streamboss/services/xtream_client.dart';
import 'package:streamboss/state/app_state.dart';
import 'package:streamboss/state/settings_state.dart';
import 'package:streamboss/theme.dart';

MediaItem ep(String id) => MediaItem(id: 'ep$id', name: 'Episode $id', kind: MediaKind.movie, streamUrl: 'http://x/$id');

Future<void> pumpScreen(WidgetTester t, Widget home, Size size, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final st = SettingsState();
  await st.init();
  final app = AppState()..bindSettings(st);
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

void main() {
  group('typing a channel number', () {
    test('maps digits to a position in the list', () {
      expect(channelIndexForDigits('1', 30), 0);
      expect(channelIndexForDigits('207', 300), 206);
      expect(channelIndexForDigits('30', 30), 29);
    });
    test('rejects numbers that are not a channel', () {
      expect(channelIndexForDigits('0', 30), isNull);
      expect(channelIndexForDigits('31', 30), isNull);
      expect(channelIndexForDigits('', 30), isNull);
      expect(channelIndexForDigits('12', 0), isNull);
    });
  });

  group('next episode', () {
    final eps = [ep('1'), ep('2'), ep('3')];
    test('is the one after the current', () {
      expect(nextEpisodeAfter(eps, eps[0])?.id, 'ep2');
      expect(nextEpisodeAfter(eps, eps[1])?.id, 'ep3');
    });
    test('is null at the end, for a stranger or without a list', () {
      expect(nextEpisodeAfter(eps, eps[2]), isNull);
      expect(nextEpisodeAfter(eps, ep('9')), isNull);
      expect(nextEpisodeAfter(null, eps[0]), isNull);
    });
  });

  group('playlist headers', () {
    const body = '#EXTM3U\n'
        '#EXTINF:-1 group-title="News",Needs Headers\n'
        '#EXTVLCOPT:http-referrer=https://site.example/\n'
        '#EXTVLCOPT:http-user-agent=Mozilla/5.0 (X11)\n'
        'https://cdn.example/a.m3u8\n'
        '#EXTINF:-1 group-title="News",Plain\n'
        'https://cdn.example/b.m3u8\n'
        '#EXTINF:-1 group-title="News",Origin only\n'
        '#EXTVLCOPT:http-origin=https://o.example\n'
        '#EXTVLCOPT:network-caching=1000\n'
        'https://cdn.example/c.m3u8\n';

    test('Referer, User-Agent and Origin lines attach to the next stream only', () {
      final c = parseM3u(body);
      expect(c.live[0].headers, {'Referer': 'https://site.example/', 'User-Agent': 'Mozilla/5.0 (X11)'});
      expect(c.live[1].headers, isNull, reason: 'must not leak to the next channel');
      expect(c.live[2].headers, {'Origin': 'https://o.example'}, reason: 'other VLC options are ignored');
    });

    test('survive saving and merging', () {
      final c = parseM3u(body);
      final back = MediaItem.fromJson(c.live[0].toJson());
      expect(back.headers, c.live[0].headers);
      expect(MediaItem.fromJson(c.live[1].toJson()).headers, isNull);
      final merged = mergeCatalogs([c, parseM3u(body)]);
      expect(merged.live.first.headers, c.live[0].headers);
    });
  });

  group('account info', () {
    final now = DateTime(2026, 10, 8, 12);
    final exp = DateTime(2026, 10, 18, 12).millisecondsSinceEpoch ~/ 1000;

    test('reads the provider fields', () {
      final a = AccountInfo.fromUserInfo({
        'auth': 1,
        'status': 'Active',
        'exp_date': '$exp',
        'max_connections': '2',
        'active_cons': '1',
        'is_trial': '0',
      });
      expect(a.status, 'Active');
      expect(a.maxConnections, 2);
      expect(a.activeConnections, 1);
      expect(a.trial, isFalse);
      expect(a.daysLeft(now), 10);
      expect(a.describe(now), ['Active', 'Expires 2026-10-18 (in 10 days)', '1 of 2 connections in use']);
    });

    test('handles no expiry, expired and trial accounts', () {
      expect(AccountInfo.fromUserInfo({'exp_date': null}).describe(now)[1], 'No expiry date');
      expect(AccountInfo.fromUserInfo({'exp_date': '0'}).expires, isNull);
      final old = DateTime(2026, 9, 1).millisecondsSinceEpoch ~/ 1000;
      expect(AccountInfo.fromUserInfo({'status': 'Expired', 'exp_date': '$old'}).describe(now)[1], 'Expired on 2026-09-01');
      expect(AccountInfo.fromUserInfo({'is_trial': '1', 'max_connections': '1'}).describe(now),
          ['Active (trial)', 'No expiry date', '0 of 1 connection in use']);
    });
  });

  group('settings', () {
    testWidgets('new playback options default sensibly and are on the Playback page', (t) async {
      await pumpScreen(t, const Scaffold(body: SettingsScreen()), const Size(1200, 900));
      final st = Provider.of<SettingsState>(t.element(find.byType(SettingsScreen)), listen: false);
      expect(st.autoplayNext, isTrue);
      expect(st.aspect, 'auto');
      await t.tap(find.text('Playback'));
      await t.pumpAndSettle();
      expect(find.text('Play the next episode'), findsOneWidget);
      expect(find.text('Picture shape'), findsOneWidget);
      await t.tap(find.text('Play the next episode'));
      await t.pumpAndSettle();
      expect(st.autoplayNext, isFalse);
    });
  });

  group('test connection', () {
    testWidgets('asks for an address when there is none', (t) async {
      await pumpScreen(t, const SetupScreen(), const Size(900, 900));
      await t.ensureVisible(find.text('Test connection'));
      await t.tap(find.text('Test connection'));
      await t.pumpAndSettle();
      expect(find.text('Enter a server address first.'), findsOneWidget);
    });
  });
}
